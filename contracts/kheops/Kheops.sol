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
 * function to acknowledge surplus and do some bookkeeping at the oracle level
 * contract size
 * virtual agEUR
 * events
 * function to estimate the collateral ratio -> and acknowledge surplus based on this
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
        return collateralList;
    }

    function getRedeemableModuleList() external view returns (address[] memory) {
        return redeemableModuleList;
    }

    function getUnredeemableModuleList() external view returns (address[] memory) {
        return unredeemableModuleList;
    }

    function getCollateralRatio() external view returns (uint64 collatRatio) {
        (collatRatio, ) = _getCollateralRatio();
    }

    function getIssuedByCollateral(address collateral) external view returns (uint256, uint256) {
        uint256 _accumulator = accumulator;
        return ((collaterals[collateral].r * _accumulator) / _BASE_27, (reserves * _accumulator) / _BASE_27);
    }

    function getModuleBorrowed(address module) external view returns (uint256) {
        return (modules[module].r * accumulator) / _BASE_27;
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
        address[] memory list = collateralList;
        uint256 length = list.length;
        for (uint256 i; i < length; ++i) {
            tokens[i] = list[i];
        }
        address[] memory depositModuleList = redeemableModuleList;
        uint256 depositModuleLength = depositModuleList.length;
        for (uint256 i; i < depositModuleLength; ++i) {
            tokens[i + length] = modules[depositModuleList[i]].token;
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
            address toProtocolAddress = collatInfo.manager != address(0) ? collatInfo.manager : address(this);
            uint256 changeAmount = (amountOut * _BASE_27) / accumulator;
            collaterals[tokenOut].r += changeAmount;
            reserves += changeAmount;
            IERC20(tokenIn).safeTransferFrom(msg.sender, toProtocolAddress, amountIn);
            IAgToken(tokenOut).mint(to, amountOut);
        } else {
            uint256 changeAmount = (amountIn * _BASE_27) / accumulator;
            collaterals[tokenOut].r -= changeAmount;
            reserves -= changeAmount;
            IAgToken(tokenIn).burnSelf(amountIn, msg.sender);
            if (collatInfo.manager != address(0)) {
                IManager(collatInfo.manager).transfer(to, amountOut, true);
            } else {
                IERC20(tokenOut).safeTransfer(to, amountOut);
            }
        }
        if (collatInfo.hasOracleFallback > 0)
            IOracleFallback(collatInfo.oracle).updateInternalData(amountIn, amountOut, mint);
    }

    function _redeemWithForfeit(
        uint256 amount,
        address to,
        uint deadline,
        uint256[] memory minAmountOuts,
        address[] memory forfeitTokens
    ) internal returns (address[] memory tokens, uint256[] memory amounts) {
        if (block.timestamp < deadline) revert TooLate();
        amounts = _quoteRedemptionCurve(amount);
        _updateAccumulator(amount, false);
        address[] memory _collateralList = collateralList;
        address[] memory depositModuleList = redeemableModuleList;
        uint256 collateralListLength = _collateralList.length;
        for (uint256 i; i < amounts.length; ++i) {
            if (amounts[i] < minAmountOuts[i]) revert TooSmallAmountOut();
            if (i < collateralListLength) tokens[i] = _collateralList[i];
            else tokens[i] = modules[depositModuleList[i - collateralListLength]].token;
            if (!_checkForfeit(tokens[i], forfeitTokens)) {
                if (i < collateralListLength) {
                    address manager = collaterals[_collateralList[i]].manager;
                    if (manager != address(0)) {
                        IManager(manager).transfer(to, amounts[i], false);
                    } else {
                        IERC20(tokens[i]).safeTransfer(to, amounts[i]);
                    }
                } else {
                    IModule(depositModuleList[i - collateralListLength]).transfer(to, amounts[i]);
                }
            } else amounts[i] = 0;
        }
    }

    function updateAccumulator(uint256 amount, bool increase) external returns (uint256) {
        // Trusted addresses can call the function (like a savings contract in the case of a LSD)
        if (!accessControlManager.isGovernor(msg.sender) && isTrusted[msg.sender] == 0) revert NotTrusted();
        return _updateAccumulator(amount, increase);
    }

    function _updateAccumulator(uint256 amount, bool increase) internal returns (uint256 newAccumulatorValue) {
        uint256 _accumulator = accumulator;
        uint256 _reserves = (reserves * _accumulator) / _BASE_27;
        if (_reserves == 0) newAccumulatorValue = _BASE_27;
        else if (increase) {
            newAccumulatorValue = (_accumulator * (_reserves + amount)) / _reserves;
        } else {
            newAccumulatorValue = (_accumulator * (_reserves - amount)) / _reserves;
            // TODO check if it remains consistent when it gets too small
            if (newAccumulatorValue == 0) {
                address[] memory _collateralList = collateralList;
                address[] memory depositModuleList = redeemableModuleList;
                uint256 collateralListLength = _collateralList.length;
                uint256 depositModuleListLength = depositModuleList.length;
                for (uint256 i; i < collateralListLength; ++i) {
                    collaterals[_collateralList[i]].r = 0;
                }
                for (uint256 i; i < depositModuleListLength; ++i) {
                    modules[depositModuleList[i]].r = 0;
                }
                reserves = 0;
                newAccumulatorValue = _BASE_27;
            }
        }
        accumulator = newAccumulatorValue;
    }

    function _quoteMintExact(Collateral memory collatInfo, uint256 amountIn) internal view returns (uint256 amountOut) {
        uint256 oracleValue = _BASE_18;
        if (collatInfo.oracle != address(0)) oracleValue = IOracle(collatInfo.oracle).readMint();
        uint256 amountInCorrected = _convertDecimalTo(amountIn, collatInfo.decimals, 18);
        // Overestimating the amount of stablecoin we'll get to compute the exposure
        uint256 estimatedStablecoinAmount = (_applyFeeOut(amountInCorrected, oracleValue, collatInfo.yFeeMint[0]) *
            _BASE_27) / accumulator;
        uint256 _reserves = reserves;
        uint64 newExposure = uint64(
            ((collatInfo.r + estimatedStablecoinAmount) * _BASE_9) / (_reserves + estimatedStablecoinAmount)
        );
        uint64 currentExposure = uint64((collatInfo.r * _BASE_9) / _reserves);
        int64 fees = _piecewiseMean(currentExposure, newExposure, collatInfo.xFeeMint, collatInfo.yFeeMint);
        amountOut = _applyFeeOut(amountInCorrected, oracleValue, fees);
    }

    function _quoteMintForExact(
        Collateral memory collatInfo,
        uint256 amountOut
    ) internal view returns (uint256 amountIn) {
        uint256 oracleValue = _BASE_18;
        if (collatInfo.oracle != address(0)) oracleValue = IOracle(collatInfo.oracle).readMint();
        uint256 _reserves = reserves;
        uint256 amountOutCorrected = (amountOut * _BASE_27) / accumulator;
        uint64 newExposure = uint64(((collatInfo.r + amountOutCorrected) * _BASE_9) / (_reserves + amountOutCorrected));
        uint64 currentExposure = uint64((collatInfo.r * _BASE_9) / _reserves);
        int64 fees = _piecewiseMean(currentExposure, newExposure, collatInfo.xFeeMint, collatInfo.yFeeMint);
        amountIn = _convertDecimalTo(_applyFeeIn(amountOut, oracleValue, fees), 18, collatInfo.decimals);
    }

    function _quoteBurnExact(Collateral memory collatInfo, uint256 amountIn) internal view returns (uint256 amountOut) {
        uint256 oracleValue = _getBurnOracle(collatInfo.oracle);
        uint64 newExposure;
        uint256 _reserves = reserves;
        uint256 amountInCorrected = (amountIn * _BASE_27) / accumulator;
        if (amountInCorrected == reserves) newExposure = 0;
        else newExposure = uint64(((collatInfo.r - amountInCorrected) * _BASE_9) / (_reserves - amountInCorrected));
        uint64 currentExposure = uint64((collatInfo.r * _BASE_9) / _reserves);
        int64 fees = _piecewiseMean(newExposure, currentExposure, collatInfo.xFeeBurn, collatInfo.yFeeBurn);
        amountOut = _convertDecimalTo(_applyFeeOut(amountIn, oracleValue, fees), 18, collatInfo.decimals);
    }

    function _quoteBurnForExact(
        Collateral memory collatInfo,
        uint256 amountOut
    ) internal view returns (uint256 amountIn) {
        uint256 oracleValue = _getBurnOracle(collatInfo.oracle);
        // Underestimating the amount that needs to be burnt
        uint256 estimatedStablecoinAmount = (_applyFeeIn(
            _convertDecimalTo(amountOut, collatInfo.decimals, 18),
            oracleValue,
            collatInfo.yFeeBurn[collatInfo.yFeeBurn.length - 1]
        ) * _BASE_27) / accumulator;
        uint256 _reserves = reserves;
        uint64 newExposure;
        if (estimatedStablecoinAmount >= reserves) newExposure = 0;
        else
            newExposure = uint64(
                ((collatInfo.r - estimatedStablecoinAmount) * _BASE_9) / (_reserves - estimatedStablecoinAmount)
            );
        uint64 currentExposure = uint64((collatInfo.r * _BASE_9) / _reserves);
        int64 fees = _piecewiseMean(newExposure, currentExposure, collatInfo.xFeeBurn, collatInfo.yFeeBurn);
        amountIn = _applyFeeIn(amountOut, oracleValue, fees);
    }

    function _quoteRedemptionCurve(uint256 amountBurnt) internal view returns (uint256[] memory amounts) {
        (uint64 collatRatio, uint256[] memory balances) = _getCollateralRatio();
        uint64[] memory _xRedemptionCurve = xRedemptionCurve;
        int64[] memory _yRedemptionCurve = yRedemptionCurve;
        uint64 penalty;
        if (collatRatio >= _BASE_9) {
            // TODO check conversions whether it works well
            penalty = (uint64(_yRedemptionCurve[_yRedemptionCurve.length - 1]) * uint64(_BASE_9)) / collatRatio;
        } else {
            penalty = uint64(_piecewiseMean(collatRatio, collatRatio, _xRedemptionCurve, _yRedemptionCurve));
        }
        uint256 balancesLength = balances.length;
        for (uint256 i; i < balancesLength; ++i) {
            amounts[i] = (amountBurnt * balances[i] * penalty * _BASE_18) / (reserves * accumulator);
        }
    }

    function _getBurnOracle(address collatOracle) internal view returns (uint256) {
        uint256 oracleValue = _BASE_18;
        address[] memory list = collateralList;
        uint256 length = list.length;
        uint256 deviation = _BASE_9;
        for (uint256 i; i < length; ++i) {
            address oracle = collaterals[list[i]].oracle;
            uint256 deviationValue = _BASE_9;
            if (oracle != address(0) && oracle != collatOracle) {
                deviationValue = IOracle(oracle).getDeviation();
            } else if (oracle != address(0)) {
                (oracleValue, deviationValue) = IOracle(oracle).readBurn();
            }
            if (deviationValue < deviation) deviation = deviationValue;
        }
        // Renormalizing by an overestimated value of the oracle
        return (deviation * _BASE_27) / oracleValue;
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
        if (collatInfo.manager != address(0) && IManager(collatInfo.manager).maxAvailable() < amountOut)
            revert InvalidSwap();
    }

    function _getCollateralRatio() internal view returns (uint64 collatRatio, uint256[] memory balances) {
        uint256 totalCollateralization;
        // TODO check whether an oracleList could be smart -> with just list of addresses or stuff
        address[] memory list = collateralList;
        uint256 listLength = list.length;
        address[] memory depositModuleList = redeemableModuleList;
        uint256 depositModuleLength = depositModuleList.length;
        balances = new uint256[](listLength + depositModuleLength);

        for (uint256 i; i < listLength; ++i) {
            uint256 balance;
            address manager = collaterals[list[i]].manager;
            if (manager != address(0)) balance = IManager(manager).getUnderlyingBalance();
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
        uint256 _reserves = reserves;
        uint256 _accumulator = accumulator;
        if (_reserves > 0 && _accumulator > 0)
            collatRatio = uint64((totalCollateralization * _BASE_36) / (_reserves * _accumulator));
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
        } else if (tokenOut == _agToken) {
            collatInfo = collaterals[tokenIn];
            mint = true;
        } else revert InvalidTokens();
        if (collatInfo.unpaused == 0) revert InvalidTokens();
    }

    function borrow(uint256 amount) external returns (uint256) {
        Module storage module = modules[msg.sender];
        if (module.unpaused == 0) revert NotModule();
        // Getting borrowing power from the module
        uint256 _reserves = reserves;
        uint256 _accumulator = accumulator;
        uint256 borrowingPower;
        if (module.r * _BASE_9 < module.maxExposure * _reserves) {
            if (module.redeemable > 0) {
                borrowingPower =
                    ((module.maxExposure * _reserves - module.r * _BASE_9) * _accumulator) /
                    ((_BASE_9 - module.maxExposure) * _BASE_27);
            } else borrowingPower = (((module.maxExposure * _reserves) / _BASE_9 - module.r) * _accumulator) / _BASE_27;
        }
        amount = amount > borrowingPower ? borrowingPower : amount;
        uint256 amountCorrected = (amount * _BASE_27) / _accumulator;
        module.r += amountCorrected;
        reserves += amountCorrected;
        IAgToken(agToken).mint(msg.sender, amount);
        return amount;
    }

    function repay(uint256 amount) external returns (uint256) {
        Module storage module = modules[msg.sender];
        if (module.unpaused == 0) revert NotModule();
        uint256 currentR = module.r;
        amount = amount > currentR ? currentR : amount;
        uint256 amountCorrected = (amount * _BASE_27) / accumulator;
        module.r -= amountCorrected;
        reserves -= amountCorrected;
        IAgToken(agToken).burnSelf(amount, msg.sender);
        return amount;
    }

    /// @dev amount is an absolute amount (like not normalized) -> need to pay attention to this
    function adjustReserve(address collateral, uint256 amount, bool addOrRemove) external onlyGovernor {
        Collateral storage collatInfo = collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        if (addOrRemove) {
            collatInfo.r += amount;
            reserves += amount;
        } else {
            collatInfo.r -= amount;
            reserves -= amount;
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
        if (manager == address(0)) {
            IManager(collatInfo.manager).pullAll();
        } else {
            IERC20(collateral).safeTransfer(manager, IERC20(collateral).balanceOf(address(this)));
        }
        collatInfo.manager = manager;
    }

    function togglePause(address collateral, bool collateralOrModule) external onlyGuardian {
        if (collateralOrModule) {
            Collateral storage collatInfo = collaterals[collateral];
            if (collatInfo.decimals == 0) revert NotCollateral();
            uint8 pausedStatus = collatInfo.unpaused;
            collatInfo.unpaused = 1 - pausedStatus;
        } else {
            Module storage module = modules[collateral];
            if (module.initialized == 0) revert NotModule();
            uint8 pausedStatus = module.unpaused;
            module.unpaused = 1 - pausedStatus;
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
        collateralList.push(collateral);
    }

    function addModule(address moduleAddress, address token, uint8 redeemable) external onlyGovernor {
        Module storage module = modules[moduleAddress];
        if (module.initialized != 0) revert AlreadyAdded();
        module.token = token;
        module.redeemable = redeemable;
        module.initialized = 1;
        if (redeemable > 0) redeemableModuleList.push(moduleAddress);
        else unredeemableModuleList.push(moduleAddress);
    }

    function revokeCollateral(address collateral) external onlyGovernor {
        Collateral memory collatInfo = collaterals[collateral];
        if (collatInfo.decimals == 0 || collatInfo.r > 0) revert NotCollateral();
        delete collaterals[collateral];
        address[] memory _collateralList = collateralList;
        uint256 length = _collateralList.length;
        // We already know that it is in the list
        for (uint256 i; i < length - 1; ++i) {
            if (_collateralList[i] == collateral) {
                collateralList[i] = _collateralList[length - 1];
                break;
            }
        }
        collateralList.pop();
    }

    function revokeModule(address moduleAddress) external onlyGovernor {
        Module storage module = modules[moduleAddress];
        if (module.initialized == 0 || module.r > 0) revert NotModule();
        if (module.redeemable > 0) {
            address[] memory _redeemableModuleList = redeemableModuleList;
            uint256 length = _redeemableModuleList.length;
            // We already know that it is in the list
            for (uint256 i; i < length - 1; ++i) {
                if (_redeemableModuleList[i] == moduleAddress) {
                    redeemableModuleList[i] = _redeemableModuleList[length - 1];
                    break;
                }
            }
            redeemableModuleList.pop();
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
        xRedemptionCurve = xFee;
        yRedemptionCurve = yFee;
    }

    function setModuleMaxExposure(address moduleAddress, uint64 maxExposure) external onlyGuardian {
        Module storage module = modules[moduleAddress];
        if (module.initialized == 0) revert NotModule();
        if (maxExposure > _BASE_9) revert InvalidParam();
        module.maxExposure = maxExposure;
    }

    // Future unpredicted use cases, so we're not messing up with storage
    function setExtraData(bytes memory extraData, address collateral, bool collateralOrModule) external onlyGuardian {
        if (collateralOrModule) {
            Collateral storage collatInfo = collaterals[collateral];
            if (collatInfo.decimals == 0) revert NotCollateral();
            collatInfo.extraData = extraData;
        } else {
            Module storage module = modules[collateral];
            if (module.initialized == 0) revert NotModule();
            module.extraData = extraData;
        }
    }

    function setOracle(address collateral, address oracle, uint8 hasOracleFallback) external onlyGovernor {
        Collateral storage collatInfo = collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        if (hasOracleFallback > 0) IOracleFallback(oracle).updateInternalData(0, 0, true);
        else if (oracle != address(0)) IOracle(oracle).readMint();
        collatInfo.oracle = oracle;
        collatInfo.hasOracleFallback = hasOracleFallback;
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

        if (setter == 0 && yFee[0] < 0) {
            // Checking that the mint fee is still bigger than the smallest burn fee everywhere
            address[] memory _collateralList = collateralList;
            uint256 length = _collateralList.length;
            for (uint256 i; i < length; ++i) {
                // TODO: do we perform other checks on the fact that sum of target exposures and stuff must be well respected
                int64[] memory burnFees = collaterals[_collateralList[i]].yFeeBurn;
                if (burnFees[burnFees.length - 1] + yFee[0] < 0) revert InvalidParams();
            }
        }
        if (setter == 1 && yFee[n - 1] < 0) {
            // Checking that the burn fee is still bigger than the smallest mint fee everywhere
            address[] memory _collateralList = collateralList;
            uint256 length = _collateralList.length;
            for (uint256 i; i < length; ++i) {
                int64[] memory mintFees = collaterals[_collateralList[i]].yFeeMint;
                if (mintFees[0] + yFee[n - 1] < 0) revert InvalidParams();
            }
        }
    }
}
