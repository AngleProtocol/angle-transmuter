// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "./CurveModuleStorage.sol";

/// @title CurveModule
/// @author Angle Labs
abstract contract CurveModule is ICurveModule, CurveModuleStorage {
    using SafeERC20 for IERC20;

    // ================================= CONSTANTS =================================

    /// @notice Address of the Curve pool on which this contract invests
    address public immutable mainPool;

    /// @notice Address of the agToken
    IERC20 public immutable agToken;

    /// @notice Decimals of the other token
    uint256 public immutable decimalsOtherToken;

    /// @notice Index of agToken in the Curve pool
    uint256 public immutable indexAgToken;

    /// @notice StakeDAO vault address
    IStakeCurveVault public immutable vault;

    /// @notice StakeDAO gauge address
    ILiquidityGauge public immutable gauge;

    /// @notice Address of the Convex contract on which to claim rewards
    IConvexBaseRewardPool public immutable baseRewardPool;

    /// @notice ID of the pool associated to the AMO on Convex
    uint256 public immutable poolId;

    // ================================= FUNCTIONS =================================

    /// @inheritdoc ICurveModule
    function initialize(address accessControlManager_, address minter_, address agToken_, address basePool_) external {
        if (
            accessControlManager_ == address(0) ||
            minter_ == address(0) ||
            agToken_ == address(0) ||
            basePool_ == address(0)
        ) revert ZeroAddress();

        accessControlManager = IAccessControlManager(accessControlManager_);
        minter = IMinter(minter_);
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address mainPool_,
        address agToken_,
        address vault_,
        address gauge_,
        address baseRewardPool_,
        uint256 poolId_
    ) initializer {
        mainPool = mainPool_;
        agToken = IERC20(agToken_);

        address[2] memory coins = [IMetaPool2(mainPool_).coins(0), IMetaPool2(mainPool_).coins(1)];
        if (coins[0] != agToken_ && coins[0] != agToken_) {
            revert InvalidParam();
        }
        indexAgToken = coins[0] == agToken_ ? 0 : 1;
        decimalsOtherToken = 10 ** IERC20Metadata(coins[1 - indexAgToken]).decimals();

        vault = IStakeCurveVault(vault_);
        gauge = ILiquidityGauge(gauge_);
        baseRewardPool = IConvexBaseRewardPool(baseRewardPool_);
        poolId = poolId_;
    }

    // ================================= MODIFIERS =================================

    /// @notice Checks whether the `msg.sender` is trusted
    modifier onlyTrusted() {
        if (isTrusted[msg.sender] != 1 || accessControlManager.isGovernorOrGuardian(msg.sender)) revert NotTrusted();
        _;
    }

    /// @notice Checks whether the `msg.sender` is the `AMOMinter` contract
    modifier onlyMinter() {
        if (msg.sender != address(minter)) revert NotAMOMinter();
        _;
    }

    // =============================== VIEW FUNCTIONS ==============================

    /// @inheritdoc ICurveModule
    function balance() external view returns (uint256) {
        uint256 tokenIdleBalance = agToken.balanceOf(address(this));
        uint256 netAssets = _getNavOfInvestedAssets();
        return tokenIdleBalance + netAssets;
    }

    /// @inheritdoc ICurveModule
    function debt() external view returns (uint256) {
        return minter.debt(agToken);
    }

    /// @inheritdoc ICurveModule
    function getNavOfInvestedAssets() external view returns (uint256) {
        return _getNavOfInvestedAssets();
    }

    /// @notice Returns the current state that is to say how much agToken should be added or removed to reach equilibrium
    function currentState() public view returns (bool addLiquidity, uint256 delta) {
        uint256[2] memory balances = IMetaPool2(mainPool).get_balances();

        // Handle decimals
        if (decimalsOtherToken > 18) {
            balances[1 - indexAgToken] = balances[1 - indexAgToken] / 10 ** (decimalsOtherToken - 18);
        } else if (decimalsOtherToken < 18) {
            balances[1 - indexAgToken] = balances[1 - indexAgToken] * 10 ** (18 - decimalsOtherToken);
        }

        // First case the module needs to inject agToken
        if (balances[indexAgToken] < balances[1 - indexAgToken])
            return (true, balances[1 - indexAgToken] - balances[indexAgToken]);
        else {
            uint256 currentDebt = minter.debt(IERC20(agToken));
            delta = balances[indexAgToken] - balances[1 - indexAgToken];
            delta = currentDebt > delta ? delta : currentDebt;
            return (false, delta);
        }
    }

    // ============================ ONLYMINTER FUNCTIONS ===========================

    /// @notice Adjusts by automatically minting and depositing, or withdrawing and burning the exact
    /// amount needed to put the Curve pool back at balance
    /// @return addLiquidity Whether liquidity was added or removed after calling this function
    /// @return delta How much was added or removed from the Curve pool
    function adjust() external onlyTrusted returns (bool addLiquidity, uint256 delta) {
        (addLiquidity, delta) = currentState();

        uint256[] memory amounts = new uint256[](1);
        IERC20[] memory tokens = new IERC20[](1);
        bool[] memory isStablecoin = new bool[](1);
        address[] memory to = new address[](1);
        amounts[0] = delta;
        tokens[0] = IERC20(agToken);
        isStablecoin[0] = true;

        if (addLiquidity) {
            minter.borrow(tokens, isStablecoin, amounts);

            (uint256 netAssets, uint256 idleAssets) = _report(agToken, delta);
            // As the `add_liquidity` function on Curve can only deposit the right amount
            // we can compute directly `lastBalance`
            lastBalances[agToken] = netAssets + idleAssets;

            _changeAllowance(agToken, address(mainPool), delta);
            IMetaPool2(mainPool).add_liquidity([delta, 0], 0); // TODO Slippage

            _depositLPToken();
        } else {
            _pull(tokens, amounts);
            minter.repay(tokens, isStablecoin, amounts, to);
        }
    }

    function setMinter(address minter_) external onlyMinter {
        minter = IMinter(minter_);
    }

    function setToken(IERC20 token) external onlyMinter {
        _setToken(token);
    }

    function removeToken(IERC20 token) external onlyMinter {
        _removeToken(token);
    }

    // ====================== Restricted Governance Functions ======================

    function pushSurplus(IERC20 token, address to) external onlyTrusted {
        if (to == address(0)) revert ZeroAddress();
        uint256 amountToRecover = protocolGains[token];

        IERC20[] memory tokens = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = token;
        amounts[0] = amountToRecover;
        uint256 amountAvailable = _pull(tokens, amounts)[0];

        amountToRecover = amountToRecover <= amountAvailable ? amountToRecover : amountAvailable;
        protocolGains[token] -= amountToRecover;
        token.transfer(to, amountToRecover);
    }

    /// @dev Governance is responsible for handling CRV, SDT, and CVX rewards claimed through this function
    /// @dev Rewards can be used to pay back part of the debt by swapping it for `agToken`
    /// @dev Currently this implementation only supports the Liquidity gauge associated to the StakeDAO Curve vault
    /// @dev Should there be any additional reward contract for Convex or for StakeDAO, we should add to the list
    /// the new contract
    function claimRewards() external onlyTrusted {
        // Claim on StakeDAO
        gauge.claim_rewards(address(this));
        // Claim on Convex
        address[] memory rewardContracts = new address[](1);
        rewardContracts[0] = address(baseRewardPool);

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

    function sellRewards(uint256 minAmountOut, bytes memory payload) external onlyTrusted {
        //solhint-disable-next-line
        (bool success, bytes memory result) = _ONE_INCH_ROUTER.call(payload);
        if (!success) _revertBytes(result);
        // TODO Add safeguard so only rewards tokens are sold

        uint256 amountOut = abi.decode(result, (uint256));
        if (amountOut < minAmountOut) revert TooSmallAmountOut();
    }

    function changeAllowance(
        IERC20[] calldata tokens,
        address[] calldata spenders,
        uint256[] calldata amounts
    ) external onlyGovernor {
        if (tokens.length != spenders.length || tokens.length != amounts.length || tokens.length == 0)
            revert IncompatibleLengths();
        for (uint256 i = 0; i < tokens.length; i++) {
            _changeAllowance(tokens[i], spenders[i], amounts[i]);
        }
    }

    function toggleTrusted(address trusted) public onlyGovernor {
        if (trusted == address(0)) revert ZeroAddress();
        uint256 newValue = 1 - isTrusted[trusted];
        isTrusted[trusted] = newValue;
        emit TrustedToggled(trusted, newValue == 1);
    }

    /// @dev This function is `onlyTrusted` rather than `onlyGovernor` because rewards selling already
    /// happens through an `onlyTrusted` function
    function recoverERC20(address tokenAddress, address to, uint256 amountToRecover) external onlyTrusted {
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
    function setStakeDAOProportion(uint256 _newProp) external onlyTrusted {
        if (_newProp > _BASE_9) revert IncompatibleValues();
        stakeDAOProportion = _newProp;
    }

    // ========================== Internal Actions =================================

    /// @dev Returning an amount here is important as the amounts fed are not comparable to the lp amounts
    function _pull(
        IERC20[] memory tokens,
        uint256[] memory amounts
    ) internal returns (uint256[] memory amountsAvailable) {
        (tokens, amounts) = _checkTokensList(tokens, amounts);

        uint256[] memory idleTokens = new uint256[](tokens.length);

        // Check for profit / loss made on each token. This doesn't take into account rewards
        for (uint256 i = 0; i < tokens.length; i++) {
            (uint256 netAssets, uint256 idleAssets) = _report(tokens[i], 0);
            lastBalances[tokens[i]] = netAssets + idleAssets - amounts[i];
            idleTokens[i] = idleAssets;
        }

        // We first need to unstake and withdraw the staker(s) LP token to get the Curve LP token
        // We unstake all from the staker(s) as we don't know how much will be needed to get back `amounts`
        _withdrawLPToken();
        amountsAvailable = _curvePoolWithdraw(tokens, amounts, idleTokens);
        // The leftover Curve LP token balance is staked back
        _depositLPToken();

        return amountsAvailable;
    }

    /// @notice Internal version of the `setToken` function
    function _setToken(IERC20 token) internal virtual {}

    /// @notice Internal version of the `removeToken` function
    function _removeToken(IERC20 token) internal virtual {}

    /// @notice Gets the net amount of stablecoin owned by this AMO
    /// @dev The assets are estimated by considering that we burn all our LP tokens and receive in a balanced way `agToken` and `collateral`
    /// @dev We then consider that the `collateral` is fully tradable at 1:1 against `agToken`
    function _getNavOfInvestedAssets() internal view returns (uint256 netInvested) {
        // Should be null at all times because invested on a staking platform
        uint256 lpTokenOwned = IMetaPool2(mainPool).balanceOf(address(this)); // TODO Remove this line?

        // Staked LP tokens in Convex or StakeDAO vault
        uint256 stakedLptoken = _convexLPStaked() + _stakeDAOLPStaked();
        lpTokenOwned = lpTokenOwned + stakedLptoken;

        // Why not using `calc_withdraw_one_coin` directly from the Curve pool?
        if (lpTokenOwned != 0) {
            uint256 lpSupply = IMetaPool2(mainPool).totalSupply();
            uint256[2] memory balances = IMetaPool2(mainPool).get_balances();
            netInvested = _calcRemoveLiquidityStablePool(balances[0], lpSupply, lpTokenOwned);
            // Here we consider that the `collateral` is tradable 1:1 for `agToken`
            netInvested += _calcRemoveLiquidityStablePool(balances[1], lpSupply, lpTokenOwned) * _BASE_12;
        }
    }

    /// @notice Checks if any gain/loss has been made since last call
    /// @param token Address of the token to report
    /// @param amountAdded Amount of new tokens added to the AMO
    /// @return netAssets Difference between assets and liabilities for the token in this AMO
    /// @return idleTokens Immediately available tokens in the AMO
    function _report(
        IERC20 token,
        uint256 amountAdded
    ) internal virtual returns (uint256 netAssets, uint256 idleTokens) {
        netAssets = _getNavOfInvestedAssets(); // Assumed to be positive
        idleTokens = token.balanceOf(address(this));

        // Always positive otherwise we couldn't do the operation, and idleTokens >= amountAdded
        uint256 total = idleTokens + netAssets - amountAdded;
        uint256 lastBalance_ = lastBalances[token];

        if (total > lastBalance_) {
            // In case of a yield gain, if there is already a loss, the gain is used to compensate the previous loss
            uint256 gain = total - lastBalance_;
            uint256 protocolDebtPre = protocolDebts[token];
            if (protocolDebtPre <= gain) {
                protocolGains[token] += gain - protocolDebtPre;
                protocolDebts[token] = 0;
            } else protocolDebts[token] -= gain;
        } else if (total < lastBalance_) {
            // In case of a loss, we first try to compensate it from previous gains for the part that concerns
            // the protocol
            uint256 loss = lastBalance_ - total;
            uint256 protocolGainBeforeLoss = protocolGains[token];
            // If the loss can not be entirely soaked by the gains already made then
            // the protocol keeps track of the debt
            if (loss > protocolGainBeforeLoss) {
                protocolDebts[token] += loss - protocolGainBeforeLoss;
                protocolGains[token] = 0;
            } else protocolGains[token] -= loss;
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

    /// @notice Processes 1Inch revert messages
    function _revertBytes(bytes memory errMsg) internal pure {
        if (errMsg.length > 0) {
            //solhint-disable-next-line
            assembly {
                revert(add(32, errMsg), mload(errMsg))
            }
        }
        revert OneInchSwapFailed();
    }

    function _curvePoolWithdraw(
        IERC20[] memory,
        uint256[] memory amounts,
        uint256[] memory
    ) internal returns (uint256[] memory) {
        IMetaPool2(mainPool).remove_liquidity_imbalance([amounts[0], 0], 0); // TODO Slippage
        return amounts;
    }

    /// @dev In this implementation, Curve LP tokens are deposited into StakeDAO and Convex
    function _depositLPToken() internal {
        uint256 balanceLP = IERC20(mainPool).balanceOf(address(this));

        // Compute what should go to Stake and Convex respectively
        uint256 lpForStakeDAO = (balanceLP * stakeDAOProportion) / _BASE_9;
        uint256 lpForConvex = balanceLP - lpForStakeDAO;

        if (lpForStakeDAO > 0) {
            // Approve the vault contract for the Curve LP tokens
            _changeAllowance(IERC20(mainPool), address(vault), lpForStakeDAO);
            // Deposit the Curve LP tokens into the vault contract and stake
            vault.deposit(address(this), lpForStakeDAO, true);
        }

        if (lpForConvex > 0) {
            // Deposit the Curve LP tokens into the convex contract and stake
            _changeAllowance(IERC20(mainPool), address(_CONVEX_BOOSTER), lpForConvex);
            _CONVEX_BOOSTER.deposit(poolId, lpForConvex, true);
        }
    }

    /// @notice Withdraws the Curve LP tokens from StakeDAO and Convex
    function _withdrawLPToken() internal {
        uint256 lpInStakeDAO = _stakeDAOLPStaked();
        uint256 lpInConvex = _convexLPStaked();
        if (lpInStakeDAO > 0) {
            if (vault.withdrawalFee() > 0) revert WithdrawFeeTooLarge();
            vault.withdraw(lpInStakeDAO);
        }
        if (lpInConvex > 0) baseRewardPool.withdrawAllAndUnwrap(true);
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

    // ========================== INTERNAL VIEW FUNCTIONS ==========================

    /// @notice Get the balance of the Curve LP tokens staked on StakeDAO for the pool
    function _stakeDAOLPStaked() internal view returns (uint256) {
        return gauge.balanceOf(address(this));
    }

    /// @notice Get the balance of the Curve LP tokens staked on Convex for the pool
    function _convexLPStaked() internal view returns (uint256) {
        return baseRewardPool.balanceOf(address(this));
    }

    /// @notice Checks on a given `tokens` and `amounts` list that are passed for a `_pull` or `_push` operation,
    /// reverting if the tokens are not supported and filling the arrays if they are missing entries
    /// @param tokens Addresses of tokens to be withdrawn
    /// @param amounts Amounts of each token to be withdrawn
    function _checkTokensList(
        IERC20[] memory tokens,
        uint256[] memory amounts
    ) internal view returns (IERC20[] memory, uint256[] memory) {
        if (tokens.length != 1) revert IncompatibleLengths();
        if (address(tokens[0]) != address(agToken)) revert IncompatibleTokens();
        return (tokens, amounts);
    }
}
