// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "./CurveModuleStorage.sol";

/// @title CurveModule
/// @author Angle Labs
/// @dev Only supports pools with two tokens, one of which is an Angle Protocol stablecoin
contract CurveModule is ICurveModule, CurveModuleStorage {
    using SafeERC20 for IERC20;

    // ================================= FUNCTIONS =================================

    function initialize(
        address _accessControlManager,
        address _kheops,
        IMetaPool2 _curvePool,
        address _stakeCurveVault,
        address _stakeGauge,
        address _convexBaseRewardPool,
        uint16 _convexPoolId
    ) external initializer {
        if (_accessControlManager == address(0)) revert ZeroAddress();

        address _agToken = address(IKheops(kheops).agToken());

        address[2] memory coins = [_curvePool.coins(0), _curvePool.coins(1)];
        if (coins[0] != _agToken && coins[1] != _agToken) {
            revert InvalidParam();
        }

        accessControlManager = IAccessControlManager(_accessControlManager);
        kheops = IKheops(_kheops);
        curvePool = _curvePool;
        agToken = IERC20(_agToken);
        uint8 _indexAgToken = coins[0] == _agToken ? 0 : 1;
        indexAgToken = _indexAgToken;
        otherToken = IERC20(coins[1 - _indexAgToken]);
        decimalsOtherToken = uint8(IERC20Metadata(coins[1 - _indexAgToken]).decimals());
        stakeCurveVault = IStakeCurveVault(_stakeCurveVault);
        stakeGauge = ILiquidityGauge(_stakeGauge);
        convexBaseRewardPool = IConvexBaseRewardPool(_convexBaseRewardPool);
        convexPoolId = _convexPoolId;
        _approveMaxSpend(_agToken, address(_curvePool));
        _approveMaxSpend(coins[1 - _indexAgToken], address(_curvePool));
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    // ================================= MODIFIERS =================================

    modifier whenNotPaused() {
        if (paused > 0) revert Paused();
        _;
    }

    // =============================== VIEW FUNCTIONS ==============================

    // Balance solely estimated from LP Tokens here
    function getBalanceAndValue() external view returns (uint256, uint256) {
        (uint256 lpTokenOwned, uint256 amountStablecoin, uint256 amountOtherToken) = _getNavOfInvestedAssets();
        int128 _indexAgToken = int128(uint128(indexAgToken));
        amountOtherToken = curvePool.get_dy(1 - _indexAgToken, _indexAgToken, amountOtherToken);
        /* TODO: estimate best option
        amountOtherToken = _convertToBase(amountOtherToken, decimalsOtherToken);
        if (address(oracle) != address(0)) {
            amountOtherToken = (oracle.read() * amountOtherToken) / _BASE_18;
        }
        */
        return (lpTokenOwned, amountStablecoin + amountOtherToken);
    }

    // Assuming here that everything that is controlled is the LP tokens and only outstanding balances are profits
    function transfer(address receiver, uint256 amount) external {
        if (msg.sender != address(kheops)) revert NotAllowed();
        _unstakeLPTokens();
        IERC20(address(curvePool)).safeTransfer(receiver, amount);
        _stakeLPTokens();
    }

    function nav() public view returns (uint256 lpTokenOwned, uint256 amountStablecoin, uint256 amountOtherToken) {
        (lpTokenOwned, amountStablecoin, amountOtherToken) = _getNavOfInvestedAssets();
        amountStablecoin += agToken.balanceOf(address(this));
        amountOtherToken += otherToken.balanceOf(address(this));
    }

    function getNavOfInvestedAssets() public view returns (uint256, uint256, uint256) {
        return _getNavOfInvestedAssets();
    }

    function estimateProfit() public view returns (int256 agTokenProfit) {
        (, uint256 amountStablecoin, uint256 amountOtherToken) = nav();
        int128 _indexAgToken = int128(uint128(indexAgToken));
        agTokenProfit =
            int256(amountStablecoin) +
            int256(curvePool.get_dy(1 - _indexAgToken, _indexAgToken, amountOtherToken)) -
            int256(kheops.getModuleBorrowed(address(this)));
    }

    function hasOtherTokenDepegged() external view returns (bool) {
        return _depegSafeguard();
    }

    function getRewardTokens() external view returns (IERC20[] memory) {
        return rewardTokens;
    }

    /// @notice Returns the current state that is to say how much agToken should be added or removed to reach equilibrium
    /// @return isOtherTokenDepegged
    /// @return addLiquidity
    /// @return amountAgToken
    /// @return amountOtherToken
    function currentState() public view returns (bool, bool, uint256, uint256) {
        bool isOtherTokenDepegged = _depegSafeguard();
        if (isOtherTokenDepegged) return (true, false, 0, 0);

        uint256[2] memory balances = curvePool.get_balances();
        uint256 _indexAgToken = indexAgToken;
        // Borrowing as much as possible
        uint256 otherTokenBalance = otherToken.balanceOf(address(this));
        balances[1 - _indexAgToken] = _convertDecimalTo(
            balances[1 - _indexAgToken] + otherTokenBalance,
            decimalsOtherToken,
            18
        );

        uint256 total = balances[0] + balances[1];
        uint256 _depositThreshold = depositThreshold;
        uint256 _withdrawThreshold = withdrawThreshold;
        uint256 amountAgToken;
        if (balances[_indexAgToken] * _BASE_9 < total * _depositThreshold) {
            amountAgToken =
                (balances[1 - _indexAgToken] * _depositThreshold) /
                (_BASE_9 - _depositThreshold) -
                balances[_indexAgToken];
            return (false, true, amountAgToken, otherTokenBalance);
        } else if (balances[_indexAgToken] * _BASE_9 > total * _withdrawThreshold) {
            // This is the max theorical amount that can be removed but potentially, we cannot withdraw more than that
            amountAgToken =
                balances[_indexAgToken] -
                (balances[1 - _indexAgToken] * _depositThreshold) /
                (_BASE_9 - _depositThreshold);
            return (false, false, amountAgToken, otherTokenBalance);
        }
        return (false, false, 0, otherTokenBalance);
    }

    /// @notice Adjusts by automatically minting and depositing, or withdrawing and burning the exact
    /// amount needed to put the Curve pool back at balance
    function adjust()
        external
        whenNotPaused
        returns (bool isOtherTokenDepegged, bool addLiquidity, uint256 amountAgToken, uint256 amountOtherToken)
    {
        (isOtherTokenDepegged, addLiquidity, amountAgToken, amountOtherToken) = currentState();
        if (isOtherTokenDepegged) {
            // TODO: in this case we don't repay the debt, but should we do something particular beyond or just wait
            // How do we repay debt in this case
            _unstakeLPTokens();
            uint256[2] memory minAmounts;
            curvePool.remove_liquidity(_lpTokenBalance(), minAmounts);
        } else {
            if (addLiquidity) {
                uint256 agTokenBalance = agToken.balanceOf(address(this));
                amountAgToken = amountAgToken > agTokenBalance ? amountAgToken - agTokenBalance : 0;
                if (amountAgToken > 0) {
                    uint256 amountBorrowed = kheops.borrow(amountAgToken);
                    agTokenBalance += amountBorrowed;
                    amountAgToken = amountAgToken > agTokenBalance ? agTokenBalance : amountAgToken;
                }
                if (amountAgToken > 0 || amountOtherToken > 0) {
                    _curvePoolDeposit(amountAgToken, amountOtherToken);
                    _stakeLPTokens();
                }
            } else {
                if (amountOtherToken > 0) _curvePoolDeposit(0, amountOtherToken);
                if (amountAgToken > 0) {
                    _unstakeLPTokens();
                    _curvePoolWithdraw(amountAgToken, 0);
                    _stakeLPTokens();
                    kheops.repay(agToken.balanceOf(address(this)));
                } else if (amountOtherToken > 0) _stakeLPTokens();
            }
        }
    }

    function claimRewards() external {
        ILiquidityGauge _stakeGauge = stakeGauge;
        // Claim on Stake
        if (address(_stakeGauge) != address(0)) stakeGauge.claim_rewards(address(this));
        IConvexBaseRewardPool _convexBaseRewardPool = convexBaseRewardPool;
        if (address(_convexBaseRewardPool) != address(0)) {
            // Claim on Convex
            address[] memory rewardContracts = new address[](1);
            rewardContracts[0] = address(convexBaseRewardPool);

            _CONVEX_CLAIM_ZAP.claimRewards(
                rewardContracts,
                new address[](0),
                new address[](0),
                new address[](0),
                0,
                0,
                0,
                0,
                0
            );
        }
        // Send rewards to the `rewardHandler` contract
        address _rewardHandler = rewardHandler;
        if (_rewardHandler != address(0)) {
            IERC20[] memory _rewardTokens = rewardTokens;
            uint256 rewardLength = _rewardTokens.length;
            for (uint256 i; i < rewardLength; ++i) {
                _rewardTokens[i].safeTransfer(_rewardHandler, _rewardTokens[i].balanceOf(address(this)));
            }
        }
    }

    // ====================== Restricted Governance Functions ======================

    function forceAdjustTokenPosition(uint256 amount, bool borrow) external onlyGovernor {
        if (borrow) kheops.borrow(amount);
        else kheops.repay(amount);
    }

    function forceWithdrawBothTokens(uint256 amountAgToken, uint256 amountOtherToken) external onlyGovernor {
        _unstakeLPTokens();
        _curvePoolWithdraw(amountAgToken, amountOtherToken);
        _stakeLPTokens();
    }

    function togglePause() external onlyGuardian {
        uint8 pausedStatus = 1 - paused;
        paused = pausedStatus;
        emit ToggledPause(pausedStatus);
    }

    function changeAllowance(
        IERC20[] calldata tokens,
        address[] calldata spenders,
        uint256[] calldata amounts
    ) external onlyGovernor {
        uint256 tokensLength = tokens.length;
        if (tokensLength != spenders.length || tokensLength != amounts.length || tokensLength == 0)
            revert IncompatibleLengths();
        for (uint256 i; i < tokensLength; ++i) {
            _changeAllowance(tokens[i], spenders[i], amounts[i]);
        }
    }

    function recoverERC20(address tokenAddress, address to, uint256 amountToRecover) external onlyGovernor {
        IERC20(tokenAddress).safeTransfer(to, amountToRecover);
        emit Recovered(tokenAddress, to, amountToRecover);
    }

    /// @notice Generic function to execute arbitrary calls with the contract
    function execute(address _to, bytes calldata _data) external onlyGovernor returns (bool, bytes memory) {
        //solhint-disable-next-line
        (bool success, bytes memory result) = _to.call(_data);
        return (success, result);
    }

    /// @notice Sets the proportion of the LP tokens that should be staked on StakeDAO with respect
    /// to Convex
    function setStakeDAOProportion(uint8 _newProp) external onlyGovernor {
        if (_newProp > 100) revert IncompatibleValues();
        if (address(stakeCurveVault) == address(0) || address(stakeGauge) == address(0)) revert InvalidParam();
        stakeDAOProportion = _newProp;
        _unstakeLPTokens();
        _stakeLPTokens();
    }

    function setRewardHandler(address _rewardHandler) external onlyGovernor {
        if (_rewardHandler == address(0)) revert ZeroAddress();
        rewardHandler = _rewardHandler;
    }

    function addRewardToken(IERC20 rewardToken) external onlyGovernor {
        rewardTokens.push(rewardToken);
    }

    function removeRewardToken(IERC20 rewardToken) external onlyGovernor {
        IERC20[] memory list = rewardTokens;
        uint256 listLength = list.length;
        for (uint256 i; i < listLength - 1; ++i) {
            if (list[i] == IERC20(rewardToken)) {
                rewardTokens[i] = list[listLength - 1];
                break;
            }
        }
        rewardTokens.pop();
    }

    function setOracle(IOracle _oracle) external onlyGovernor {
        _oracle.read();
        oracle = _oracle;
    }

    function setUint64(uint64 param, bytes32 what) external onlyGovernor {
        // TODO add safety checks and else revert
        if (param > _BASE_9) revert InvalidParam();
        if (what == "D") {
            if (param < withdrawThreshold) revert InvalidParam();
            depositThreshold = param;
        } else if (what == "W") {
            if (param > depositThreshold) revert InvalidParam();
            withdrawThreshold = param;
        } else if (what == "O") oracleDeviationThreshold = param;
    }

    function setConvexStakeData(
        uint16 _convexPoolId,
        IConvexBaseRewardPool _convexBaseRewardPool,
        ILiquidityGauge _stakeGauge,
        IStakeCurveVault _stakeCurveVault
    ) external onlyGovernor {
        if (
            address(_convexBaseRewardPool) == address(0) ||
            address(_stakeGauge) == address(0) ||
            address(_stakeCurveVault) == address(0)
        ) revert ZeroAddress();
        stakeCurveVault = _stakeCurveVault;
        stakeGauge = _stakeGauge;
        convexBaseRewardPool = _convexBaseRewardPool;
        convexPoolId = _convexPoolId;
    }

    // ========================== Internal Actions =================================

    function _getNavOfInvestedAssets()
        internal
        view
        returns (uint256 lpTokenOwned, uint256 amountStablecoin, uint256 amountOtherToken)
    {
        lpTokenOwned = _lpTokenBalance();
        if (lpTokenOwned != 0) {
            uint256 lpSupply = curvePool.totalSupply();
            uint256[2] memory balances = curvePool.get_balances();
            uint256 amountToken0 = _calcRemoveLiquidityStablePool(balances[0], lpSupply, lpTokenOwned);
            uint256 amountToken1 = _calcRemoveLiquidityStablePool(balances[1], lpSupply, lpTokenOwned);
            if (indexAgToken == 0) {
                amountStablecoin = amountToken0;
                amountOtherToken = amountToken1;
            } else {
                amountStablecoin = amountToken1;
                amountOtherToken = amountToken0;
            }
        }
    }

    /// @notice Changes allowance of this contract for a given token
    /// @param token Address of the token for which allowance should be changed
    /// @param spender Address to approve
    /// @param amount Amount to approve
    function _changeAllowance(IERC20 token, address spender, uint256 amount) internal {
        uint256 currentAllowance = token.allowance(address(this), spender);
        if (currentAllowance < amount) {
            token.safeIncreaseAllowance(spender, amount - currentAllowance);
        } else if (currentAllowance > amount) {
            token.safeDecreaseAllowance(spender, currentAllowance - amount);
        }
    }

    /// @notice Gives a `max(uint256)` approval to `spender` for `token`
    /// @param token Address of token to approve
    /// @param spender Address of spender to approve
    function _approveMaxSpend(address token, address spender) internal {
        IERC20(token).safeApprove(spender, type(uint256).max);
    }

    function _curvePoolDeposit(uint256 amountAgToken, uint256 amountOtherToken) internal {
        // TODO slippage
        if (indexAgToken == 0) curvePool.add_liquidity([amountAgToken, amountOtherToken], 0);
        else curvePool.add_liquidity([amountOtherToken, amountAgToken], 0);
    }

    function _curvePoolWithdraw(uint256 amountAgToken, uint256 amountOtherToken) internal {
        if (amountAgToken > 0 || amountOtherToken > 0) {
            // TODO Slippage -> probably a better way to do this
            uint256[2] memory removalAmounts;
            uint256 _indexAgToken = indexAgToken;
            removalAmounts[_indexAgToken] = amountAgToken;
            removalAmounts[1 - indexAgToken] = amountOtherToken;
            uint256 burntAmount = curvePool.calc_token_amount(removalAmounts, false);
            uint256 lpTokenOwned = _lpTokenBalance();
            if (burntAmount > lpTokenOwned) curvePool.remove_liquidity(lpTokenOwned, removalAmounts);
            else curvePool.remove_liquidity_imbalance(removalAmounts, burntAmount);
        }
    }

    /// @dev In this implementation, Curve LP tokens are deposited into StakeDAO and Convex
    function _stakeLPTokens() internal {
        uint256 balanceLP = IERC20(curvePool).balanceOf(address(this));
        uint256 _stakeDAOProportion = stakeDAOProportion;
        uint256 _convexPoolId = convexPoolId;
        uint256 lpForStakeDAO;
        uint256 lpForConvex;

        // If there are no gauges
        if (_stakeDAOProportion == 0 && _convexPoolId == type(uint256).max) return;
        else if (_stakeDAOProportion != 0 && _convexPoolId == type(uint256).max) lpForStakeDAO = balanceLP;
        else {
            lpForStakeDAO = (balanceLP * stakeDAOProportion) / 100;
            lpForConvex = balanceLP - lpForStakeDAO;
        }

        if (lpForStakeDAO > 0) {
            IStakeCurveVault _stakeCurveVault = stakeCurveVault;
            // Approve the vault contract for the Curve LP tokens
            _changeAllowance(IERC20(address(curvePool)), address(_stakeCurveVault), lpForStakeDAO);
            // Deposit the Curve LP tokens into the vault contract and stake
            _stakeCurveVault.deposit(address(this), lpForStakeDAO, true);
        }

        if (lpForConvex > 0) {
            // Deposit the Curve LP tokens into the Convex contract and stake
            _changeAllowance(IERC20(address(curvePool)), address(_CONVEX_BOOSTER), lpForConvex);
            _CONVEX_BOOSTER.deposit(_convexPoolId, lpForConvex, true);
        }
    }

    /// @notice Withdraws the Curve LP tokens from StakeDAO and Convex
    function _unstakeLPTokens() internal {
        _unstakeStakeLP();
        _unstakeConvexLP();
    }

    function _unstakeStakeLP() internal {
        uint256 lpInStakeDAO = _stakeDAOLPStaked();
        if (lpInStakeDAO > 0) {
            if (stakeCurveVault.withdrawalFee() > 0) revert WithdrawFeeTooLarge();
            stakeCurveVault.withdraw(lpInStakeDAO);
        }
    }

    function _unstakeConvexLP() internal {
        uint256 lpInConvex = _convexLPStaked();
        if (lpInConvex > 0) convexBaseRewardPool.withdrawAllAndUnwrap(true);
    }

    // ========================== INTERNAL VIEW FUNCTIONS ==========================

    function _lpTokenBalance() internal view returns (uint256) {
        return curvePool.balanceOf(address(this)) + _convexLPStaked() + _stakeDAOLPStaked();
    }

    /// @notice Get the balance of the Curve LP tokens staked on StakeDAO for the pool
    function _stakeDAOLPStaked() internal view returns (uint256 amount) {
        ILiquidityGauge _stakeGauge = stakeGauge;
        if (address(_stakeGauge) != address(0)) amount = _stakeGauge.balanceOf(address(this));
    }

    /// @notice Get the balance of the Curve LP tokens staked on Convex for the pool
    function _convexLPStaked() internal view returns (uint256 amount) {
        IConvexBaseRewardPool _convexBaseRewardPool = convexBaseRewardPool;
        if (address(_convexBaseRewardPool) != address(0)) amount = _convexBaseRewardPool.balanceOf(address(this));
    }

    function _depegSafeguard() internal view returns (bool isOtherTokenDepegged) {
        if (address(oracle) != address(0) && oracle.read() < (_BASE_18 * oracleDeviationThreshold) / _BASE_9)
            isOtherTokenDepegged = true;
    }

    /// @notice Compute the underlying tokens amount that will be received upon removing liquidity in a balanced manner
    /// @param tokenSupply Token owned by the Curve pool
    /// @param totalLpSupply Total supply of the metaPool
    /// @param myLpSupply Contract supply of the contract
    /// @return tokenWithdrawn Amount of `tokenToWithdraw` that would be received after removing liquidity
    function _calcRemoveLiquidityStablePool(
        uint256 tokenSupply,
        uint256 totalLpSupply,
        uint256 myLpSupply
    ) internal pure returns (uint256 tokenWithdrawn) {
        if (totalLpSupply > 0) tokenWithdrawn = (tokenSupply * myLpSupply) / totalLpSupply;
    }
}
