// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/IAgToken.sol";
import "../interfaces/IMinter.sol";

import "../utils/AccessControl.sol";

import "./KheopsStorage.sol";

/**
 * TODO:
 * function to recover surplus
 * function to acknowledge surplus and do some bookkeeping at the oracle level
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
    }

    constructor() initializer {}

    function getCollateralList() external view returns (address[] memory) {}

    function getRedeemableModuleList() external view returns (address[] memory) {}

    function getUnredeemableModuleList() external view returns (address[] memory) {}

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
        uint amountOut,
        uint amountInMax,
        address tokenIn,
        address tokenOut,
        address to,
        uint deadline
    ) external returns (uint amountIn) {
        return _swap(amountOut, amountInMax, tokenIn, tokenOut, to, deadline, false);
    }

    function redeem(
        uint256 amount,
        address receiver,
        uint deadline,
        uint256[] memory minAmountOuts
    ) external returns (address[] memory tokens, uint256[] memory amounts) {
        address[] memory forfeitTokens;
        return _redeemWithForfeit(amount, receiver, deadline, minAmountOuts, forfeitTokens);
    }

    function redeemWithForfeit(
        uint256 amount,
        address receiver,
        uint deadline,
        uint256[] memory minAmountOuts,
        address[] memory forfeitTokens
    ) external returns (address[] memory tokens, uint256[] memory amounts) {
        return _redeemWithForfeit(amount, receiver, deadline, minAmountOuts, forfeitTokens);
    }

    function quoteIn(uint256 amountIn, address tokenIn, address tokenOut) external view returns (uint256) {
        (bool mint, Collateral memory collatInfo) = _getMintBurn(tokenIn, tokenOut);
        if (mint) return _quoteMintExact(collatInfo, amountIn);
        else return _quoteBurnExact(collatInfo, amountIn);
    }

    function quoteOut(uint256 amountOut, address tokenIn, address tokenOut) external view returns (uint256) {
        (bool mint, Collateral memory collatInfo) = _getMintBurn(tokenIn, tokenOut);
        if (mint) return _quoteMintForExact(collatInfo, amountOut);
        else return _quoteBurnForExact(collatInfo, amountOut);
    }

    function quoteRedemptionCurve(
        uint256 amountBurnt
    ) external view returns (address[] memory tokens, uint256[] memory amounts) {
        amounts = _quoteRedemptionCurve(amountBurnt);
        address[] memory list = collateralList;
        uint256 length = list.length;
        for (uint256 i; i < length; ++i) {
            tokens[i] = collateralList[i];
        }
        address[] memory depositModuleList = redeemableModuleList;
        uint256 depositModuleLength = depositModuleList.length;
        for (uint256 i; i < depositModuleLength; ++i) {
            tokens[i + length] = modules[depositModuleList[i]].token;
        }
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
        if (block.timestamp < deadline) revert TooLate();
        if (mint) {
            address toProtocolAddress = collatInfo.manager != address(0) ? collatInfo.manager : address(this);
            collaterals[IERC20(tokenOut)].r += amountOut;
            reserves += amountOut;
            IERC20(tokenIn).safeTransferFrom(msg.sender, toProtocolAddress, amountIn);
            if (collatInfo.hasOracleFallback > 0)
                IOracleFallback(collatInfo.oracle).updateInternalData(amountIn, amountOut, mint);
            IAgToken(tokenOut).mint(to, amountOut);
        } else {
            collaterals[IERC20(tokenOut)].r -= amountOut;
            reserves -= amountOut;
            IAgToken(tokenIn).burnSelf(amountIn, msg.sender);
            if (collatInfo.manager != address(0)) {
                IManager(collatInfo.manager).pull(amountOut);
            }
            if (collatInfo.hasOracleFallback > 0)
                IOracleFallback(collatInfo.oracle).updateInternalData(amountIn, amountOut, mint);
            IERC20(tokenOut).safeTransfer(to, amountOut);
        }
    }

    function _redeemWithForfeit(
        uint256 amount,
        address receiver,
        uint deadline,
        uint256[] memory minAmountOuts,
        address[] memory forfeitTokens
    ) internal returns (address[] memory tokens, uint256[] memory amounts) {
        if (block.timestamp < deadline) revert TooLate();
        amounts = _quoteRedemptionCurve(amount);
        address[] memory _collateralList = collateralList;
        address[] memory depositModuleList = redeemableModuleList;
        uint256 collateralListLength = _collateralList.length;
        uint256 _reserves = reserves;
        for (uint256 i; i < amounts.length; ++i) {
            if (amounts[i] < minAmountOuts[i]) revert TooSmallAmountOut();
            uint256 reduction;
            if (i < collateralListLength) {
                tokens[i] = _collateralList[i];
                reduction = (collaterals[IERC20(tokens[i])].r * amount) / _reserves;
                collaterals[IERC20(tokens[i])].r -= reduction;
            } else {
                tokens[i] = modules[depositModuleList[i - collateralListLength]].token;
                reduction = (modules[depositModuleList[i - collateralListLength]].r * amount) / _reserves;
                modules[depositModuleList[i - collateralListLength]].r -= reduction;
            }
            _reserves -= reduction;
            if (!_checkForfeit(tokens[i], forfeitTokens)) {
                if (i < collateralListLength) {
                    IERC20(tokens[i]).safeTransfer(receiver, amounts[i]);
                } else {
                    IModule(depositModuleList[i - collateralListLength]).transfer(receiver, amount);
                }
            }
        }
        reserves = _reserves;
    }

    function _checkForfeit(address token, address[] memory tokens) internal pure returns (bool forfeit) {
        for (uint256 i; i < tokens.length; ++i) {
            if (token == tokens[i]) {
                forfeit = true;
                break;
            }
        }
    }

    function _quoteMintExact(Collateral memory collatInfo, uint256 amountIn) internal view returns (uint256 amountOut) {
        uint256 oracleValue = _BASE_18;
        if (collatInfo.oracle != address(0)) oracleValue = IOracle(collatInfo.oracle).readMint();
        uint256 amountInCorrected;
        if (collatInfo.decimals > 18) {
            amountInCorrected = amountIn / 10 ** (collatInfo.decimals - 18);
        } else if (collatInfo.decimals < 18) {
            amountInCorrected = amountIn * 10 ** (18 - collatInfo.decimals);
        }
        uint256 _reserves = reserves;
        uint256 estimatedStablecoinAmount = _applyFeeOut(amountInCorrected, oracleValue, collatInfo.yFeeMint[0]);
        uint64 newExposure = uint64(
            ((collatInfo.r + estimatedStablecoinAmount) * _BASE_9) / (_reserves + estimatedStablecoinAmount)
        );
        uint64 currentExposure = uint64((collatInfo.r * _BASE_9) / _reserves);
        int64 fees = _piecewiseMean(currentExposure, newExposure, collatInfo.xFeeMint, collatInfo.yFeeBurn);
        amountOut = _applyFeeOut(amountInCorrected, oracleValue, fees);
    }

    function _applyFeeOut(uint256 amountIn, uint256 oracleValue, int64 fees) internal pure returns (uint256 amountOut) {
        if (fees >= 0) amountOut = (oracleValue * (_BASE_9 - uint256(int256(fees))) * amountIn) / _BASE_27;
        else amountOut = (oracleValue * (_BASE_9 + uint256(int256(-fees))) * amountIn) / _BASE_27;
    }

    function _applyFeeIn(uint256 amountOut, uint256 oracleValue, int64 fees) internal pure returns (uint256 amountIn) {
        if (fees >= 0) amountIn = (amountOut * _BASE_27) / ((_BASE_9 - uint256(int256(fees))) * oracleValue);
        else amountIn = (amountOut * _BASE_27) / ((_BASE_9 + uint256(int256(-fees))) * oracleValue);
    }

    function _quoteMintForExact(
        Collateral memory collatInfo,
        uint256 amountOut
    ) internal view returns (uint256 amountIn) {
        uint256 oracleValue = _BASE_18;
        if (collatInfo.oracle != address(0)) oracleValue = IOracle(collatInfo.oracle).readMint();
        uint256 _reserves = reserves;
        uint64 newExposure = uint64(((collatInfo.r + amountOut) * _BASE_9) / (_reserves + amountOut));
        uint64 currentExposure = uint64((collatInfo.r * _BASE_9) / _reserves);
        int64 fees = _piecewiseMean(currentExposure, newExposure, collatInfo.xFeeMint, collatInfo.yFeeBurn);
        amountIn = _applyFeeIn(amountOut, oracleValue, fees);
        if (collatInfo.decimals > 18) {
            amountIn = amountIn * 10 ** (collatInfo.decimals - 18);
        } else if (collatInfo.decimals < 18) {
            amountIn = amountIn / 10 ** (18 - collatInfo.decimals);
        }
    }

    function _getBurnOracle(address collatOracle) internal view returns (uint256) {
        uint256 oracleValue = _BASE_18;
        address[] memory list = collateralList;
        uint256 length = list.length;
        uint256 deviation = _BASE_9;
        uint256 deviationValue;
        for (uint256 i; i < length; ++i) {
            address oracle = collaterals[IERC20(list[i])].oracle;
            if (oracle != address(0) && oracle != collatOracle) {
                deviationValue = IOracle(oracle).getDeviation();
                if (deviationValue < deviation) deviation = deviationValue;
            } else if (oracle != address(0)) {
                (oracleValue, deviationValue) = IOracle(oracle).readBurn();
                if (deviationValue < deviation) deviation = deviationValue;
            }
        }
        // Renormalizing by an overestimated value of the oracle
        return (deviation * _BASE_27) / oracleValue;
    }

    function _quoteBurnExact(Collateral memory collatInfo, uint256 amountIn) internal view returns (uint256 amountOut) {
        uint256 oracleValue = _getBurnOracle(collatInfo.oracle);
        uint64 newExposure;
        uint256 _reserves = reserves;
        if (amountIn == reserves) newExposure = 0;
        else newExposure = uint64(((collatInfo.r - amountIn) * _BASE_9) / (_reserves - amountIn));
        uint64 currentExposure = uint64((collatInfo.r * _BASE_9) / _reserves);
        int64 fees = _piecewiseMean(newExposure, currentExposure, collatInfo.xFeeBurn, collatInfo.yFeeBurn);
        amountOut = _applyFeeOut(amountIn, oracleValue, fees);
        if (collatInfo.decimals > 18) {
            amountOut = amountOut * 10 ** (collatInfo.decimals - 18);
        } else if (collatInfo.decimals < 18) {
            amountOut = amountOut / 10 ** (18 - collatInfo.decimals);
        }
    }

    function _quoteBurnForExact(
        Collateral memory collatInfo,
        uint256 amountOut
    ) internal view returns (uint256 amountIn) {
        uint256 oracleValue = _getBurnOracle(collatInfo.oracle);
        uint256 amountOutCorrected;
        if (collatInfo.decimals > 18) {
            amountOutCorrected = amountOut / 10 ** (collatInfo.decimals - 18);
        } else if (collatInfo.decimals < 18) {
            amountOutCorrected = amountOut * 10 ** (18 - collatInfo.decimals);
        }
        uint256 estimatedStablecoinAmount = _applyFeeIn(
            amountOutCorrected,
            oracleValue,
            collatInfo.yFeeBurn[collatInfo.yFeeBurn.length - 1]
        );
        uint256 _reserves = reserves;
        uint64 newExposure;
        if (estimatedStablecoinAmount == reserves) newExposure = 0;
        else
            newExposure = uint64(
                ((collatInfo.r - estimatedStablecoinAmount) * _BASE_9) / (_reserves - estimatedStablecoinAmount)
            );
        uint64 currentExposure = uint64((collatInfo.r * _BASE_9) / _reserves);
        int64 fees = _piecewiseMean(newExposure, currentExposure, collatInfo.xFeeBurn, collatInfo.yFeeBurn);
        if (fees >= 0) amountIn = (amountOut * _BASE_27) / ((_BASE_9 - uint256(int256(fees))) * oracleValue);
        else amountIn = (amountOut * _BASE_27) / ((_BASE_9 + uint256(int256(-fees))) * oracleValue);
    }

    function _quoteRedemptionCurve(uint256 amountBurnt) internal view returns (uint256[] memory amounts) {
        (uint64 collatRatio, uint256[] memory balances) = _getCollateralRatio();
        uint64[] memory _xRedemptionCurve = xRedemptionCurve;
        int64[] memory _yRedemptionCurve = yRedemptionCurve;
        uint256 length = _yRedemptionCurve.length;
        uint64 cap;
        if (collatRatio >= _BASE_9) {
            // TODO check conversions whether it works well
            cap = (uint64(_yRedemptionCurve[length - 1]) * uint64(_BASE_6)) / collatRatio;
        } else {
            cap = uint64(_piecewiseMean(collatRatio, collatRatio, _xRedemptionCurve, _yRedemptionCurve));
        }
        uint256 balancesLength = balances.length;
        uint256 _reserves = reserves;
        for (uint256 i; i < balancesLength; ++i) {
            amounts[i] = (amountBurnt * balances[i] * cap) / (_reserves * _BASE_9);
        }
    }

    function getCollateralRatio() external view returns (uint64 collatRatio) {
        (collatRatio, ) = _getCollateralRatio();
    }

    function _getCollateralRatio() internal view returns (uint64 collatRatio, uint256[] memory balances) {
        uint256 totalCollateralization;
        // TODO check whether an oracleList could be smart -> with just list of addresses or stuff
        address[] memory list = collateralList;
        uint256 length = list.length;
        for (uint256 i; i < length; ++i) {
            uint256 balance;
            address manager = collaterals[IERC20(list[i])].manager;
            if (manager != address(0)) balance = IManager(manager).getUnderlyingBalance();
            else balance = IERC20(list[i]).balanceOf(address(this));
            balances[i] = balance;
            address oracle = collaterals[IERC20(list[i])].oracle;
            uint256 oracleValue = _BASE_18;
            if (oracle != address(0)) (oracleValue, ) = IOracle(oracle).readBurn();
            uint8 decimals = collaterals[IERC20(list[i])].decimals;
            if (decimals > 18) {
                totalCollateralization += oracleValue * (balance / 10 ** (decimals - 18));
            } else if (decimals < 18) {
                totalCollateralization += oracleValue * (balance * 10 ** (18 - decimals));
            } else {
                totalCollateralization += oracleValue * balance;
            }
        }
        address[] memory depositModuleList = redeemableModuleList;
        uint256 depositModuleLength = depositModuleList.length;
        for (uint256 i; i < depositModuleLength; ++i) {
            (uint256 balance, uint256 oracleValue) = IModule(depositModuleList[i]).getBalanceAndValue();
            balances[i + length] = balance;
            totalCollateralization += oracleValue * balance;
        }
        uint256 _reserves = reserves;
        if (_reserves > 0) collatRatio = uint64((totalCollateralization * _BASE_6) / _reserves);
    }

    function _getMintBurn(
        address tokenIn,
        address tokenOut
    ) internal view returns (bool mint, Collateral memory collatInfo) {
        address _agToken = address(agToken);
        if (tokenIn == _agToken) {
            collatInfo = collaterals[IERC20(tokenOut)];
            if (collatInfo.unpaused == 0) revert InvalidTokens();
            mint = false;
        } else if (tokenOut == _agToken) {
            collatInfo = collaterals[IERC20(tokenOut)];
            if (collatInfo.unpaused == 0) revert InvalidTokens();
            mint = true;
        } else revert InvalidTokens();
    }

    function borrow(uint256 amount) external returns (uint256) {
        Module storage module = modules[msg.sender];
        if (module.unpaused == 0) revert NotModule();
        uint256 borrowingPower = _getModuleBorrowingPower(module);
        amount = amount > borrowingPower ? borrowingPower : amount;
        module.r += amount;
        reserves += amount;
        IAgToken(agToken).mint(msg.sender, amount);
        return amount;
    }

    function repay(uint256 amount) external returns (uint256) {
        Module storage module = modules[msg.sender];
        if (module.unpaused == 0) revert NotModule();
        uint256 currentR = module.r;
        amount = amount > currentR ? currentR : amount;
        module.r -= amount;
        reserves -= amount;
        IAgToken(agToken).burnSelf(amount, msg.sender);
        return amount;
    }

    function adjustReserve(address collateral, uint256 amount, bool addOrRemove) external onlyGovernor {
        Collateral storage collatInfo = collaterals[IERC20(collateral)];
        if (collatInfo.decimals == 0) revert NotCollateral();
        if (addOrRemove) {
            collatInfo.r += amount;
            reserves += amount;
        } else {
            collatInfo.r -= amount;
            reserves -= amount;
        }
    }

    function recoverERC20(IERC20 token, address to, uint256 amount, bool pull) external onlyGovernor {
        if (pull) {
            IManager(collaterals[token].manager).pull(amount);
            token.safeTransfer(to, amount);
        } else token.safeTransfer(to, amount);
    }

    function setCollateralManager(address collateral, address manager) external onlyGovernor {
        Collateral storage collatInfo = collaterals[IERC20(collateral)];
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
            Collateral storage collatInfo = collaterals[IERC20(collateral)];
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

    function addCollateral(
        address collateral,
        address oracle,
        uint8 hasOracleFallback,
        uint64[] memory xFeeMint,
        int64[] memory yFeeMint,
        uint64[] memory xFeeBurn,
        int64[] memory yFeeBurn
    ) external onlyGovernor {
        Collateral storage collatInfo = collaterals[IERC20(collateral)];
        if (collatInfo.decimals != 0) revert AlreadyAdded();
        _checkOracle(oracle, hasOracleFallback);
        _checkFees(xFeeMint, yFeeMint, 0);
        _checkFees(xFeeBurn, yFeeBurn, 1);
        collatInfo.oracle = oracle;
        collatInfo.decimals = uint8(IERC20Metadata(collateral).decimals());
        collatInfo.xFeeMint = xFeeMint;
        collatInfo.yFeeMint = yFeeMint;
        collatInfo.xFeeBurn = xFeeBurn;
        collatInfo.yFeeBurn = yFeeBurn;
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

    function setModuleMaxExposure(address moduleAddress, uint64 maxExposure) external onlyGuardian {
        Module storage module = modules[moduleAddress];
        if (module.initialized == 0) revert NotModule();
        if (maxExposure > _BASE_9) revert InvalidParam();
        module.maxExposure = maxExposure;
    }

    function revokeCollateral(address collateral) external onlyGovernor {
        Collateral memory collatInfo = collaterals[IERC20(collateral)];
        if (collatInfo.decimals == 0 || collatInfo.r > 0) revert NotCollateral();
        delete collaterals[IERC20(collateral)];
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
        } else {
            address[] memory _unredeemableModuleList = unredeemableModuleList;
            uint256 length = _unredeemableModuleList.length;
            // We already know that it is in the list
            for (uint256 i; i < length - 1; ++i) {
                if (_unredeemableModuleList[i] == moduleAddress) {
                    unredeemableModuleList[i] = _unredeemableModuleList[length - 1];
                    break;
                }
            }
            unredeemableModuleList.pop();
        }
        delete modules[moduleAddress];
    }

    function setFees(address collateral, uint64[] memory xFee, int64[] memory yFee, bool mint) external onlyGuardian {
        Collateral storage collatInfo = collaterals[IERC20(collateral)];
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

    // Future unpredicted use cases, so we're not messing up with storage
    function setExtraData(bytes memory extraData, address collateral, bool collateralOrModule) external onlyGuardian {
        if (collateralOrModule) {
            Collateral storage collatInfo = collaterals[IERC20(collateral)];
            if (collatInfo.decimals == 0) revert NotCollateral();
            collatInfo.extraData = extraData;
        } else {
            Module storage module = modules[collateral];
            if (module.initialized == 0) revert NotModule();
            module.extraData = extraData;
        }
    }

    function setOracle(address collateral, address oracle, uint8 hasOracleFallback) external onlyGovernor {
        Collateral storage collatInfo = collaterals[IERC20(collateral)];
        if (collatInfo.decimals == 0) revert NotCollateral();
        _checkOracle(oracle, hasOracleFallback);
        collatInfo.oracle = oracle;
    }

    function _checkOracle(address oracle, uint8 hasOracleFallback) internal {
        if (hasOracleFallback > 0) IOracleFallback(oracle).updateInternalData(0, 0, true);
        else if (oracle != address(0)) IOracle(oracle).readMint();
    }

    function _checkFees(uint64[] memory xFee, int64[] memory yFee, uint8 setter) internal view {
        uint256 n = xFee.length;
        if (n != yFee.length || n == 0) revert InvalidParams();
        for (uint256 i = 0; i < n - 1; ++i) {
            if (
                (xFee[i] >= xFee[i + 1]) ||
                (setter == 0 && (yFee[i + 1] < yFee[i])) ||
                (setter == 1 && (yFee[i + 1] > yFee[i])) ||
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
                int64[] memory burnFees = collaterals[IERC20(_collateralList[i])].yFeeBurn;
                if (burnFees[burnFees.length - 1] + yFee[0] < 0) revert InvalidParams();
            }
        }
        if (setter == 1 && yFee[n - 1] < 0) {
            // Checking that the burn fee is still bigger than the smallest mint fee everywhere
            address[] memory _collateralList = collateralList;
            uint256 length = _collateralList.length;
            for (uint256 i; i < length; ++i) {
                int64[] memory mintFees = collaterals[IERC20(_collateralList[i])].yFeeMint;
                if (mintFees[0] + yFee[n - 1] < 0) revert InvalidParams();
            }
        }
    }

    function setRedemptionCurveParams(uint64[] memory xFee, int64[] memory yFee) external onlyGuardian {
        _checkFees(xFee, yFee, 2);
        xRedemptionCurve = xFee;
        yRedemptionCurve = yFee;
    }

    function _getModuleBorrowingPower(Module memory module) internal view returns (uint256) {
        uint256 _reserves = reserves;
        if (module.maxExposure * _reserves < module.r * _BASE_9) return 0;
        if (module.redeemable > 0)
            return (module.maxExposure * _reserves - module.r * _BASE_9) / (_BASE_9 - module.maxExposure);
        else return (module.maxExposure * _reserves) / _BASE_9 - module.r;
    }
}
