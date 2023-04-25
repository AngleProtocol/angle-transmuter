// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/IAgToken.sol";

import "../utils/AccessControl.sol";

import "./KheopsStorage.sol";

/**
 * TODO:
 * contract size
 * virtual agEUR
 * events
 */

/// @title Kheops
/// @author Angle Labs, Inc.
contract Kheops is KheopsStorage {
    using SafeERC20 for IERC20;

    // TODO: potentially agToken address in the implementation
    function initialize(IAgToken _agToken, IAccessControlManager _accessControlManager) external initializer {
        if (address(_accessControlManager) == address(0) || address(_agToken) == address(0)) revert ZeroAddress();
        accessControlManager = _accessControlManager;
        agToken = _agToken;
        accumulator = _BASE_27;
    }

    constructor() initializer {}

    function getCollateralList() external view returns (address[] memory) {
        return _collateralList;
    }

    function getCollateralFees(address collateral, bool mint) external view returns (uint64[] memory, int64[] memory) {
        if (mint) return (collaterals[collateral].xFeeMint, collaterals[collateral].yFeeMint);
        else return (collaterals[collateral].xFeeBurn, collaterals[collateral].yFeeBurn);
    }

    function getRedemptionFees() external view returns (uint64[] memory, int64[] memory) {
        return (_xRedemptionCurve, _yRedemptionCurve);
    }

    function getRedeemableModuleList() external view returns (address[] memory) {
        return _redeemableModuleList;
    }

    function getUnredeemableModuleList() external view returns (address[] memory) {
        return _unredeemableModuleList;
    }

    function getCollateralRatio() external view returns (uint64 collatRatio, uint256 normalizedStablesValue) {
        (collatRatio, normalizedStablesValue, ) = _getCollateralRatio();
    }

    function getIssuedByCollateral(address collateral) external view returns (uint256, uint256) {
        uint256 _accumulator = accumulator;
        return (
            (collaterals[collateral].normalizedStables * _accumulator) / _BASE_27,
            (normalizedStables * _accumulator) / _BASE_27
        );
    }

    function getModuleBorrowed(address module) external view returns (uint256) {
        return (modules[module].normalizedStables * accumulator) / _BASE_27;
    }

    function isModule(address module) external view returns (bool) {
        return modules[module].initialized > 0;
    }

    function quoteIn(uint256 amountIn, address tokenIn, address tokenOut) external view returns (uint256) {
        (bool mint, Collateral memory collatInfo) = _getMintBurn(tokenIn, tokenOut);
        if (mint) return _quoteMintExact(collatInfo, amountIn);
        else {
            uint256 amountOut = _quoteBurnExact(collatInfo, amountIn);
            _checkAmounts(collatInfo, amountOut);
            return amountOut;
        }
    }

    function quoteOut(uint256 amountOut, address tokenIn, address tokenOut) external view returns (uint256) {
        (bool mint, Collateral memory collatInfo) = _getMintBurn(tokenIn, tokenOut);
        if (mint) return _quoteMintForExact(collatInfo, amountOut);
        else {
            _checkAmounts(collatInfo, amountOut);
            return _quoteBurnForExact(collatInfo, amountOut);
        }
    }

    function quoteRedemptionCurve(
        uint256 amountBurnt
    ) external view returns (address[] memory tokens, uint256[] memory amounts) {
        amounts = _quoteRedemptionCurve(amountBurnt);
        address[] memory list = _collateralList;
        uint256 collateralLength = list.length;
        address[] memory depositModuleList = _redeemableModuleList;
        uint256 depositModuleLength = depositModuleList.length;

        tokens = new address[](collateralLength + depositModuleLength);
        for (uint256 i; i < collateralLength; ++i) {
            tokens[i] = list[i];
        }
        for (uint256 i; i < depositModuleLength; ++i) {
            tokens[i + collateralLength] = modules[depositModuleList[i]].token;
        }
    }

    function swapExact(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external returns (uint amountOut) {
        return _swap(amountIn, amountOutMin, tokenIn, tokenOut, to, deadline, true);
    }

    function swapForExact(
        uint256 amountOut,
        uint256 amountInMax,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external returns (uint amountIn) {
        return _swap(amountOut, amountInMax, tokenIn, tokenOut, to, deadline, false);
    }

    function redeem(
        uint256 amount,
        address receiver,
        uint256 deadline,
        uint256[] memory minAmountOuts
    ) external returns (address[] memory tokens, uint256[] memory amounts) {
        address[] memory forfeitTokens;
        return _redeemWithForfeit(amount, receiver, deadline, minAmountOuts, forfeitTokens);
    }

    function redeemWithForfeit(
        uint256 amount,
        address receiver,
        uint256 deadline,
        uint256[] memory minAmountOuts,
        address[] memory forfeitTokens
    ) external returns (address[] memory tokens, uint256[] memory amounts) {
        return _redeemWithForfeit(amount, receiver, deadline, minAmountOuts, forfeitTokens);
    }

    function _swap(
        uint256 amount,
        uint256 slippage,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline,
        bool exactIn
    ) internal returns (uint256 otherAmount) {
        if (block.timestamp < deadline) revert TooLate();
        (bool mint, Collateral memory collatInfo) = _getMintBurn(tokenIn, tokenOut);
        uint256 amountIn;
        uint256 amountOut;
        if (exactIn) {
            otherAmount = mint ? _quoteMintExact(collatInfo, amount) : _quoteBurnExact(collatInfo, amount);
            if (otherAmount < slippage) revert TooSmallAmountOut();
            (amountIn, amountOut) = (amount, otherAmount);
        } else {
            otherAmount = mint ? _quoteMintForExact(collatInfo, amount) : _quoteBurnForExact(collatInfo, amount);
            if (otherAmount > slippage) revert TooBigAmountIn();
            (amountIn, amountOut) = (otherAmount, amount);
        }
        if (mint) {
            address toProtocolAddress = collatInfo.hasManager > 0 ? collatInfo.manager : address(this);
            uint256 changeAmount = (amountOut * _BASE_27) / accumulator;
            collaterals[tokenOut].normalizedStables += changeAmount;
            normalizedStables += changeAmount;
            IERC20(tokenIn).safeTransferFrom(msg.sender, toProtocolAddress, amountIn);
            IAgToken(tokenOut).mint(to, amountOut);
        } else {
            uint256 changeAmount = (amountIn * _BASE_27) / accumulator;
            collaterals[tokenOut].normalizedStables -= changeAmount;
            normalizedStables -= changeAmount;
            IAgToken(tokenIn).burnSelf(amountIn, msg.sender);
            if (collatInfo.hasManager > 0) IManager(collatInfo.manager).transfer(to, amountOut, false);
            else IERC20(tokenOut).safeTransfer(to, amountOut);
        }
    }

    function _redeemWithForfeit(
        uint256 amount,
        address to,
        uint deadline,
        uint256[] memory minAmountOuts,
        address[] memory forfeitTokens
    ) internal returns (address[] memory tokens, uint256[] memory amounts) {
        if (block.timestamp < deadline) revert TooLate();
        if (pausedRedemption == 0) revert Paused();
        amounts = _quoteRedemptionCurve(amount);
        _updateAccumulator(amount, false);

        // Settlement - burn the stable and send the redeemable tokens
        IAgToken(agToken).burnSelf(amount, msg.sender);

        address[] memory collateralListMem = _collateralList;
        address[] memory depositModuleList = _redeemableModuleList;
        uint256 collateralListLength = collateralListMem.length;
        uint256 amountsLength = amounts.length;
        tokens = new address[](amountsLength);
        uint256 startTokenForfeit;
        for (uint256 i; i < amountsLength; ++i) {
            if (amounts[i] < minAmountOuts[i]) revert TooSmallAmountOut();
            if (i < collateralListLength) tokens[i] = collateralListMem[i];
            else tokens[i] = modules[depositModuleList[i - collateralListLength]].token;
            int256 indexFound = _checkForfeit(tokens[i], startTokenForfeit, forfeitTokens);
            if (indexFound < 0) {
                if (i < collateralListLength) {
                    if (collaterals[collateralListMem[i]].hasManager > 0)
                        IManager(collaterals[collateralListMem[i]].manager).transfer(to, amounts[i], false);
                    else IERC20(collateralListMem[i]).safeTransfer(to, amounts[i]);
                } else IModule(depositModuleList[i - collateralListLength]).transfer(to, amounts[i]);
            } else {
                // we force the user to give addresses in the order of collateralList and redeemableModuleList
                // to save on going through array too many times/
                // Not sure empirically worth it, it depends on many tokens will be supported + how many will be
                // open to forfeit
                startTokenForfeit = uint256(indexFound);
                amounts[i] = 0;
            }
        }
    }

    function updateAccumulator(uint256 amount, bool increase) external returns (uint256) {
        // Trusted addresses can call the function (like a savings contract in the case of a LSD)
        if (!accessControlManager.isGovernor(msg.sender) && isTrusted[msg.sender] == 0) revert NotTrusted();
        return _updateAccumulator(amount, increase);
    }

    function _updateAccumulator(uint256 amount, bool increase) internal returns (uint256 newAccumulatorValue) {
        uint256 _accumulator = accumulator;
        uint256 _normalizedStables = normalizedStables;
        if (_normalizedStables == 0) newAccumulatorValue = _BASE_27;
        else if (increase) {
            newAccumulatorValue = _accumulator + (amount * _BASE_27) / _normalizedStables;
        } else {
            newAccumulatorValue = _accumulator - (amount * _BASE_27) / _normalizedStables;
            if (newAccumulatorValue <= _BASE_18) {
                address[] memory collateralListMem = _collateralList;
                address[] memory depositModuleList = _redeemableModuleList;
                uint256 collateralListLength = collateralListMem.length;
                uint256 depositModuleListLength = depositModuleList.length;
                for (uint256 i; i < collateralListLength; i++) {
                    uint256 r = collaterals[collateralListMem[i]].normalizedStables;
                    collaterals[collateralListMem[i]].normalizedStables = (r * newAccumulatorValue) / _BASE_27;
                }
                for (uint256 i; i < depositModuleListLength; i++) {
                    uint256 r = modules[depositModuleList[i]].normalizedStables;
                    modules[depositModuleList[i]].normalizedStables = (r * newAccumulatorValue) / _BASE_27;
                }
                normalizedStables = (_normalizedStables * newAccumulatorValue) / _BASE_27;
                newAccumulatorValue = _BASE_27;
            }
        }
        accumulator = newAccumulatorValue;
    }

    function _quoteMintExact(Collateral memory collatInfo, uint256 amountIn) internal view returns (uint256 amountOut) {
        uint256 oracleValue = _BASE_18;
        if (collatInfo.oracle != address(0)) oracleValue = IOracle(collatInfo.oracle).readMint();
        uint256 _normalizedStables = normalizedStables;
        uint256 _accumulator = accumulator;
        uint256 amountInCorrected = _convertDecimalTo(amountIn, collatInfo.decimals, 18);
        uint64 currentExposure = uint64((collatInfo.normalizedStables * _BASE_9) / _normalizedStables);
        // Over-estimating the amount of stablecoins we'd get, to get an idea of the exposure after the swap
        // TODO: do we need to interate like that -> here doing two iterations but could be less
        // 1. We compute current fees
        int64 fees = _piecewiseMean(currentExposure, currentExposure, collatInfo.xFeeMint, collatInfo.yFeeMint);
        // 2. We estimate the amount of stablecoins we'd get from these current fees
        uint256 estimatedStablecoinAmount = (_applyFeeOut(amountInCorrected, oracleValue, fees) * _BASE_27) /
            _accumulator;
        // 3. We compute the exposure we'd get with the current fees
        uint64 newExposure = uint64(
            ((collatInfo.normalizedStables + estimatedStablecoinAmount) * _BASE_9) /
                (_normalizedStables + estimatedStablecoinAmount)
        );
        // 4. We deduce the amount of fees we would face with this exposure
        fees = _piecewiseMean(newExposure, newExposure, collatInfo.xFeeMint, collatInfo.yFeeMint);
        // 5. We compute the amount of stablecoins it'd give us
        estimatedStablecoinAmount = (_applyFeeOut(amountInCorrected, oracleValue, fees) * _BASE_27) / _accumulator;
        // 6. We get the exposure with these estimated fees
        newExposure = uint64(
            ((collatInfo.normalizedStables + estimatedStablecoinAmount) * _BASE_9) /
                (_normalizedStables + estimatedStablecoinAmount)
        );
        // 7. We deduce a current value of the fees
        fees = _piecewiseMean(currentExposure, newExposure, collatInfo.xFeeMint, collatInfo.yFeeMint);
        // 8. We get the current fee value
        amountOut = _applyFeeOut(amountInCorrected, oracleValue, fees);
    }

    function _quoteMintForExact(
        Collateral memory collatInfo,
        uint256 amountOut
    ) internal view returns (uint256 amountIn) {
        uint256 oracleValue = _BASE_18;
        if (collatInfo.oracle != address(0)) oracleValue = IOracle(collatInfo.oracle).readMint();
        uint256 _normalizedStables = normalizedStables;
        uint256 amountOutCorrected = (amountOut * _BASE_27) / accumulator;
        uint64 newExposure = uint64(
            ((collatInfo.normalizedStables + amountOutCorrected) * _BASE_9) / (_normalizedStables + amountOutCorrected)
        );
        uint64 currentExposure = uint64((collatInfo.normalizedStables * _BASE_9) / _normalizedStables);
        int64 fees = _piecewiseMean(currentExposure, newExposure, collatInfo.xFeeMint, collatInfo.yFeeMint);
        amountIn = _convertDecimalTo(_applyFeeIn(amountOut, oracleValue, fees), 18, collatInfo.decimals);
    }

    function _quoteBurnExact(Collateral memory collatInfo, uint256 amountIn) internal view returns (uint256 amountOut) {
        uint256 oracleValue = _getBurnOracle(collatInfo.oracle);
        uint64 newExposure;
        uint256 _normalizedStables = normalizedStables;
        uint256 amountInCorrected = (amountIn * _BASE_27) / accumulator;
        if (amountInCorrected == normalizedStables) newExposure = 0;
        else
            newExposure = uint64(
                ((collatInfo.normalizedStables - amountInCorrected) * _BASE_9) /
                    (_normalizedStables - amountInCorrected)
            );
        uint64 currentExposure = uint64((collatInfo.normalizedStables * _BASE_9) / _normalizedStables);
        int64 fees = _piecewiseMean(newExposure, currentExposure, collatInfo.xFeeBurn, collatInfo.yFeeBurn);
        amountOut = _convertDecimalTo(_applyFeeOut(amountIn, oracleValue, fees), 18, collatInfo.decimals);
    }

    function _quoteBurnForExact(
        Collateral memory collatInfo,
        uint256 amountOut
    ) internal view returns (uint256 amountIn) {
        uint256 oracleValue = _getBurnOracle(collatInfo.oracle);
        uint256 _normalizedStables = normalizedStables;
        uint256 _accumulator = accumulator;
        uint64 currentExposure = uint64((collatInfo.normalizedStables * _BASE_9) / _normalizedStables);
        // Over estimating the amount of stablecoins that will need to be burnt to overestimate the fees down the line
        // 1. Getting current fee
        int64 fees = _piecewiseMean(currentExposure, currentExposure, collatInfo.xFeeBurn, collatInfo.yFeeBurn);
        // 2. Getting stablecoin amount to burn for these current fees
        uint256 estimatedStablecoinAmount = (_applyFeeIn(amountOut, oracleValue, fees) * _BASE_27) / _accumulator;
        // 3. Getting max exposure with this stablecoin amount
        uint64 newExposure = uint64(
            ((collatInfo.normalizedStables - estimatedStablecoinAmount) * _BASE_9) /
                (_normalizedStables - estimatedStablecoinAmount)
        );
        // 4. Computing the max fee with this exposure
        fees = _piecewiseMean(newExposure, newExposure, collatInfo.xFeeBurn, collatInfo.yFeeBurn);
        // 5. Underestimating the amount that needs to be burnt
        estimatedStablecoinAmount =
            (_applyFeeIn(_convertDecimalTo(amountOut, collatInfo.decimals, 18), oracleValue, fees) * _BASE_27) /
            _accumulator;
        // 6. Getting exposure from this
        if (estimatedStablecoinAmount >= normalizedStables) newExposure = 0;
        else
            newExposure = uint64(
                ((collatInfo.normalizedStables - estimatedStablecoinAmount) * _BASE_9) /
                    (_normalizedStables - estimatedStablecoinAmount)
            );
        // 7. Deducing fees
        fees = _piecewiseMean(newExposure, currentExposure, collatInfo.xFeeBurn, collatInfo.yFeeBurn);
        amountIn = _applyFeeIn(amountOut, oracleValue, fees);
    }

    function _quoteRedemptionCurve(uint256 amountBurnt) internal view returns (uint256[] memory balances) {
        uint64 collatRatio;
        uint256 normalizedStablesValue;
        (collatRatio, normalizedStablesValue, balances) = _getCollateralRatio();
        uint64[] memory xRedemptionCurveMem = _xRedemptionCurve;
        int64[] memory yRedemptionCurveMem = _yRedemptionCurve;
        uint64 penalty;
        if (collatRatio >= _BASE_9) {
            penalty = (uint64(yRedemptionCurveMem[yRedemptionCurveMem.length - 1]) * uint64(_BASE_9)) / collatRatio;
        } else {
            penalty = uint64(_piecewiseMean(collatRatio, collatRatio, xRedemptionCurveMem, yRedemptionCurveMem));
        }
        uint256 balancesLength = balances.length;
        for (uint256 i; i < balancesLength; i++) {
            balances[i] = (amountBurnt * balances[i] * penalty) / (normalizedStablesValue * _BASE_9);
        }
    }

    function _getBurnOracle(address collatOracle) internal view returns (uint256) {
        uint256 oracleValue = _BASE_18;
        address[] memory list = _collateralList;
        uint256 length = list.length;
        uint256 deviation = _BASE_18;
        for (uint256 i; i < length; ++i) {
            address oracle = collaterals[list[i]].oracle;
            uint256 deviationValue = _BASE_18;
            if (oracle != address(0) && oracle != collatOracle) {
                (, deviationValue) = IOracle(oracle).readBurn();
            } else if (oracle != address(0)) {
                (oracleValue, deviationValue) = IOracle(oracle).readBurn();
            }
            if (deviationValue < deviation) deviation = deviationValue;
        }
        // Renormalizing by an overestimated value of the oracle
        return (deviation * _BASE_18) / oracleValue;
    }

    function _applyFeeOut(uint256 amountIn, uint256 oracleValue, int64 fees) internal pure returns (uint256 amountOut) {
        if (fees >= 0) amountOut = (oracleValue * (_BASE_9 - uint256(int256(fees))) * amountIn) / _BASE_27;
        else amountOut = (oracleValue * (_BASE_9 + uint256(int256(-fees))) * amountIn) / _BASE_27;
    }

    function _applyFeeIn(uint256 amountOut, uint256 oracleValue, int64 fees) internal pure returns (uint256 amountIn) {
        if (fees >= 0) {
            uint256 feesDenom = (_BASE_9 - uint256(int256(fees)));
            if (feesDenom == 0) amountIn = type(uint256).max;
            else amountIn = (amountOut * _BASE_27) / (feesDenom * oracleValue);
        } else amountIn = (amountOut * _BASE_27) / ((_BASE_9 + uint256(int256(-fees))) * oracleValue);
    }

    function _checkAmounts(Collateral memory collatInfo, uint256 amountOut) internal view {
        // Checking if enough is available for collateral assets that involve manager addresses
        if (collatInfo.hasManager > 0 && IManager(collatInfo.manager).maxAvailable() < amountOut) revert InvalidSwap();
    }

    function _getCollateralRatio()
        internal
        view
        returns (uint64 collatRatio, uint256 normalizedStablesValue, uint256[] memory balances)
    {
        uint256 totalCollateralization;
        // TODO check whether an oracleList could be smart -> with just list of addresses or stuff
        address[] memory list = _collateralList;
        uint256 listLength = list.length;
        address[] memory depositModuleList = _redeemableModuleList;
        uint256 depositModuleLength = depositModuleList.length;
        balances = new uint256[](listLength + depositModuleLength);

        for (uint256 i; i < listLength; ++i) {
            uint256 balance;
            if (collaterals[list[i]].hasManager > 0)
                balance = IManager(collaterals[list[i]].manager).getUnderlyingBalance();
            else balance = IERC20(list[i]).balanceOf(address(this));
            balances[i] = balance;
            address oracle = collaterals[list[i]].oracle;
            uint256 oracleValue = _BASE_18;
            // Using an underestimated oracle value for the collateral ratio
            if (oracle != address(0)) oracleValue = IOracle(oracle).readMint();
            totalCollateralization += oracleValue * _convertDecimalTo(balance, collaterals[list[i]].decimals, 18);
        }
        for (uint256 i; i < depositModuleLength; ++i) {
            (uint256 balance, uint256 value) = IModule(depositModuleList[i]).getBalanceAndValue();
            balances[i + listLength] = balance;
            totalCollateralization += value;
        }
        normalizedStablesValue = (normalizedStables * accumulator) / _BASE_27;
        if (normalizedStablesValue > 0)
            collatRatio = uint64((totalCollateralization * _BASE_9) / normalizedStablesValue);
        else collatRatio = type(uint64).max;
    }

    function _getMintBurn(
        address tokenIn,
        address tokenOut
    ) internal view returns (bool mint, Collateral memory collatInfo) {
        address _agToken = address(agToken);
        if (tokenIn == _agToken) {
            collatInfo = collaterals[tokenOut];
            mint = false;
            if (collatInfo.unpausedMint == 0) revert Paused();
        } else if (tokenOut == _agToken) {
            collatInfo = collaterals[tokenIn];
            mint = true;
            if (collatInfo.unpausedBurn == 0) revert Paused();
        } else revert InvalidTokens();
    }

    function borrow(uint256 amount) external returns (uint256) {
        Module storage module = modules[msg.sender];
        if (module.unpaused == 0) revert NotModule();
        // Getting borrowing power from the module
        uint256 _normalizedStables = normalizedStables;
        uint256 _accumulator = accumulator;
        uint256 borrowingPower;
        if (module.normalizedStables * _BASE_9 < module.maxExposure * _normalizedStables) {
            if (module.redeemable > 0) {
                borrowingPower =
                    ((module.maxExposure * _normalizedStables - module.normalizedStables * _BASE_9) * _accumulator) /
                    ((_BASE_9 - module.maxExposure) * _BASE_27);
            } else
                borrowingPower =
                    (((module.maxExposure * _normalizedStables) / _BASE_9 - module.normalizedStables) * _accumulator) /
                    _BASE_27;
        }
        amount = amount > borrowingPower ? borrowingPower : amount;
        uint256 amountCorrected = (amount * _BASE_27) / _accumulator;
        module.normalizedStables += amountCorrected;
        normalizedStables += amountCorrected;
        IAgToken(agToken).mint(msg.sender, amount);
        return amount;
    }

    function repay(uint256 amount) external returns (uint256) {
        Module storage module = modules[msg.sender];
        if (module.initialized == 0) revert NotModule();
        uint256 currentR = module.normalizedStables;
        amount = amount > currentR ? currentR : amount;
        uint256 amountCorrected = (amount * _BASE_27) / accumulator;
        module.normalizedStables -= amountCorrected;
        normalizedStables -= amountCorrected;
        IAgToken(agToken).burnSelf(amount, msg.sender);
        return amount;
    }

    /// @dev amount is an absolute amount (like not normalized) -> need to pay attention to this
    /// Why not normalising directly here? easier for Governance
    function adjustReserve(address collateral, uint256 amount, bool addOrRemove) external onlyGovernor {
        Collateral storage collatInfo = collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        if (addOrRemove) {
            collatInfo.normalizedStables += amount;
            normalizedStables += amount;
        } else {
            collatInfo.normalizedStables -= amount;
            normalizedStables -= amount;
        }
    }

    function recoverERC20(IERC20 token, address to, uint256 amount, bool manager) external onlyGovernor {
        if (manager) {
            IManager(collaterals[address(token)].manager).transfer(to, amount, false);
        } else token.safeTransfer(to, amount);
    }

    function setCollateralManager(address collateral, address manager) external onlyGovernor {
        Collateral storage collatInfo = collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        uint8 hasManager = collatInfo.hasManager;
        if (hasManager > 0) IManager(collatInfo.manager).pullAll();
        if (manager != address(0)) {
            collatInfo.hasManager = 1;
            IERC20(collateral).safeTransfer(manager, IERC20(collateral).balanceOf(address(this)));
        }

        collatInfo.manager = manager;
    }

    function togglePause(address collateral, uint8 pausedType) external onlyGuardian {
        if (pausedType == 0 || pausedType == 1) {
            Collateral storage collatInfo = collaterals[collateral];
            if (collatInfo.decimals == 0) revert NotCollateral();
            if (pausedType == 0) {
                uint8 pausedStatus = collatInfo.unpausedMint;
                collatInfo.unpausedMint = 1 - pausedStatus;
            } else {
                uint8 pausedStatus = collatInfo.unpausedBurn;
                collatInfo.unpausedBurn = 1 - pausedStatus;
            }
        } else if (pausedType == 2) {
            Module storage module = modules[collateral];
            if (module.initialized == 0) revert NotModule();
            uint8 pausedStatus = module.unpaused;
            module.unpaused = 1 - pausedStatus;
        } else {
            uint8 pausedStatus = pausedRedemption;
            pausedRedemption = 1 - pausedStatus;
        }
    }

    function toggleTrusted(address sender) external onlyGovernor {
        uint256 trustedStatus = 1 - isTrusted[sender];
        isTrusted[sender] = trustedStatus;
    }

    // Need to be followed by a call to set fees and set oracle and unpaused
    function addCollateral(address collateral) external onlyGovernor {
        Collateral storage collatInfo = collaterals[collateral];
        if (collatInfo.decimals != 0) revert AlreadyAdded();
        collatInfo.decimals = uint8(IERC20Metadata(collateral).decimals());
        _collateralList.push(collateral);
    }

    function addModule(address moduleAddress, address token, uint8 redeemable) external onlyGovernor {
        Module storage module = modules[moduleAddress];
        if (module.initialized != 0) revert AlreadyAdded();
        module.token = token;
        module.redeemable = redeemable;
        module.initialized = 1;
        if (redeemable > 0) _redeemableModuleList.push(moduleAddress);
        else _unredeemableModuleList.push(moduleAddress);
    }

    function revokeCollateral(address collateral) external onlyGovernor {
        Collateral memory collatInfo = collaterals[collateral];
        if (collatInfo.decimals == 0 || collatInfo.normalizedStables > 0) revert NotCollateral();
        delete collaterals[collateral];
        address[] memory collateralListMem = _collateralList;
        uint256 length = collateralListMem.length;
        // We already know that it is in the list
        for (uint256 i; i < length - 1; ++i) {
            if (collateralListMem[i] == collateral) {
                _collateralList[i] = collateralListMem[length - 1];
                break;
            }
        }
        _collateralList.pop();
    }

    function revokeModule(address moduleAddress) external onlyGovernor {
        Module storage module = modules[moduleAddress];
        if (module.initialized == 0 || module.normalizedStables > 0) revert NotModule();
        if (module.redeemable > 0) {
            address[] memory redeemableModuleListMem = _redeemableModuleList;
            uint256 length = redeemableModuleListMem.length;
            // We already know that it is in the list
            for (uint256 i; i < length - 1; ++i) {
                if (_redeemableModuleList[i] == moduleAddress) {
                    _redeemableModuleList[i] = redeemableModuleListMem[length - 1];
                    break;
                }
            }
            _redeemableModuleList.pop();
        }
        // No need to remove from the unredeemable module list -> it is never actually queried
        delete modules[moduleAddress];
    }

    function setFees(address collateral, uint64[] memory xFee, int64[] memory yFee, bool mint) external onlyGuardian {
        Collateral storage collatInfo = collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        uint8 setter;
        if (!mint) setter = 1;
        _checkFees(xFee, yFee, setter);
        if (mint) {
            collatInfo.xFeeMint = xFee;
            collatInfo.yFeeMint = yFee;
        } else {
            collatInfo.xFeeBurn = xFee;
            collatInfo.yFeeBurn = yFee;
        }
    }

    function setRedemptionCurveParams(uint64[] memory xFee, int64[] memory yFee) external onlyGuardian {
        _checkFees(xFee, yFee, 2);
        _xRedemptionCurve = xFee;
        _yRedemptionCurve = yFee;
    }

    function setModuleMaxExposure(address moduleAddress, uint64 maxExposure) external onlyGuardian {
        Module storage module = modules[moduleAddress];
        if (module.initialized == 0) revert NotModule();
        if (maxExposure > _BASE_9) revert InvalidParam();
        module.maxExposure = maxExposure;
    }

    function setOracle(address collateral, address oracle) external onlyGovernor {
        Collateral storage collatInfo = collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        if (oracle != address(0)) IOracle(oracle).readMint();
        collatInfo.oracle = oracle;
    }

    function _checkFees(uint64[] memory xFee, int64[] memory yFee, uint8 setter) internal view {
        uint256 n = xFee.length;
        if (n != yFee.length || n == 0) revert InvalidParams();
        for (uint256 i = 0; i < n - 1; ++i) {
            if (
                (xFee[i] >= xFee[i + 1]) ||
                (setter == 0 && (yFee[i + 1] < yFee[i])) ||
                (setter == 1 && (yFee[i + 1] > yFee[i])) ||
                (setter == 2 && yFee[i] < 0) ||
                xFee[i] > uint64(_BASE_9) ||
                yFee[i] < -int64(uint64(_BASE_9)) ||
                yFee[i] > int64(uint64(_BASE_9))
            ) revert InvalidParams();
        }

        address[] memory collateralListMem = _collateralList;
        uint256 length = collateralListMem.length;
        if (setter == 0 && yFee[0] < 0) {
            // Checking that the mint fee is still bigger than the smallest burn fee everywhere
            for (uint256 i; i < length; ++i) {
                int64[] memory burnFees = collaterals[collateralListMem[i]].yFeeBurn;
                if (burnFees[burnFees.length - 1] + yFee[0] < 0) revert InvalidParams();
            }
        }
        if (setter == 1 && yFee[n - 1] < 0) {
            for (uint256 i; i < length; ++i) {
                int64[] memory mintFees = collaterals[collateralListMem[i]].yFeeMint;
                if (mintFees[0] + yFee[n - 1] < 0) revert InvalidParams();
            }
        }
    }
}
