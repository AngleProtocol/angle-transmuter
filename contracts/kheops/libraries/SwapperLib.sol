// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Constants as c } from "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import { Storage as s } from "./Storage.sol";
import "./OracleLib.sol";
import "../utils/Utils.sol";
import "../Structs.sol";

import "../../interfaces/IAgToken.sol";
import "../../interfaces/IModule.sol";
import "../../interfaces/IManager.sol";

library SwapperLib {
    using SafeERC20 for IERC20;

    function swap(
        uint256 amount,
        uint256 slippage,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline,
        bool exactIn
    ) internal returns (uint256 otherAmount) {
        KheopsStorage storage ks = s.kheopsStorage();
        if (block.timestamp < deadline) revert TooLate();
        (bool mint, Collateral memory collatInfo) = getMintBurn(tokenIn, tokenOut);
        uint256 amountIn;
        uint256 amountOut;
        if (exactIn) {
            otherAmount = mint ? quoteMintExact(collatInfo, amount) : quoteBurnExact(collatInfo, amount);
            if (otherAmount < slippage) revert TooSmallAmountOut();
            (amountIn, amountOut) = (amount, otherAmount);
        } else {
            otherAmount = mint ? quoteMintForExact(collatInfo, amount) : quoteBurnForExact(collatInfo, amount);
            if (otherAmount > slippage) revert TooBigAmountIn();
            (amountIn, amountOut) = (otherAmount, amount);
        }
        if (mint) {
            address toProtocolAddress = collatInfo.manager != address(0) ? collatInfo.manager : address(this);
            uint256 changeAmount = (amountOut * c._BASE_27) / ks.accumulator;
            ks.collaterals[tokenOut].r += changeAmount;
            ks.reserves += changeAmount;
            IERC20(tokenIn).safeTransferFrom(msg.sender, toProtocolAddress, amountIn);
            IAgToken(tokenOut).mint(to, amountOut);
        } else {
            uint256 changeAmount = (amountIn * c._BASE_27) / ks.accumulator;
            ks.collaterals[tokenOut].r -= changeAmount;
            ks.reserves -= changeAmount;
            IAgToken(tokenIn).burnSelf(amountIn, msg.sender);
            Utils.transferCollateral(tokenOut, collatInfo.manager, to, amountOut);
        }
        // if (collatInfo.hasOracleFallback > 0)
        //     IOracleFallback(collatInfo.oracle).updateInternalData(amountIn, amountOut, mint);
    }

    function updateAccumulator(uint256 amount, bool increase) internal returns (uint256 newAccumulatorValue) {
        KheopsStorage storage ks = s.kheopsStorage();
        uint256 _accumulator = ks.accumulator;
        uint256 _reserves = ks.reserves;
        if (_reserves == 0) newAccumulatorValue = c._BASE_27;
        else if (increase) {
            newAccumulatorValue = _accumulator + (amount * c._BASE_27) / _reserves;
        } else {
            newAccumulatorValue = _accumulator - (amount * c._BASE_27) / _reserves;
            // TODO check if it remains consistent when it gets too small
            if (newAccumulatorValue == 0) {
                address[] memory _collateralList = ks.collateralList;
                address[] memory depositModuleList = ks.redeemableModuleList;
                uint256 collateralListLength = _collateralList.length;
                uint256 depositModuleListLength = depositModuleList.length;
                for (uint256 i; i < collateralListLength; ++i) {
                    ks.collaterals[_collateralList[i]].r = 0;
                }
                for (uint256 i; i < depositModuleListLength; ++i) {
                    ks.modules[depositModuleList[i]].r = 0;
                }
                ks.reserves = 0;
                newAccumulatorValue = c._BASE_27;
            }
        }
        ks.accumulator = newAccumulatorValue;
    }

    function quoteMintExact(Collateral memory collatInfo, uint256 amountIn) internal view returns (uint256 amountOut) {
        KheopsStorage storage ks = s.kheopsStorage();
        uint256 oracleValue = OracleLib.readMint(collatInfo.oracle);
        uint256 _reserves = ks.reserves;
        uint256 _accumulator = ks.accumulator;
        uint256 amountInCorrected = Utils.convertDecimalTo(amountIn, collatInfo.decimals, 18);
        uint64 currentExposure = uint64((collatInfo.r * c._BASE_9) / _reserves);
        // Over-estimating the amount of stablecoins we'd get, to get an idea of the exposure after the swap
        // TODO: do we need to interate like that -> here doing two iterations but could be less
        // 1. We compute current fees
        int64 fees = Utils.piecewiseMean(currentExposure, currentExposure, collatInfo.xFeeMint, collatInfo.yFeeMint);
        // 2. We estimate the amount of stablecoins we'd get from these current fees
        uint256 estimatedStablecoinAmount = (applyFeeOut(amountInCorrected, oracleValue, fees) * c._BASE_27) /
            _accumulator;
        // 3. We compute the exposure we'd get with the current fees
        uint64 newExposure = uint64(
            ((collatInfo.r + estimatedStablecoinAmount) * c._BASE_9) / (_reserves + estimatedStablecoinAmount)
        );
        // 4. We deduce the amount of fees we would face with this exposure
        fees = Utils.piecewiseMean(newExposure, newExposure, collatInfo.xFeeMint, collatInfo.yFeeMint);
        // 5. We compute the amount of stablecoins it'd give us
        estimatedStablecoinAmount = (applyFeeOut(amountInCorrected, oracleValue, fees) * c._BASE_27) / _accumulator;
        // 6. We get the exposure with these estimated fees
        newExposure = uint64(
            ((collatInfo.r + estimatedStablecoinAmount) * c._BASE_9) / (_reserves + estimatedStablecoinAmount)
        );
        // 7. We deduce a current value of the fees
        fees = Utils.piecewiseMean(currentExposure, newExposure, collatInfo.xFeeMint, collatInfo.yFeeMint);
        // 8. We get the current fee value
        amountOut = applyFeeOut(amountInCorrected, oracleValue, fees);
    }

    function quoteMintForExact(
        Collateral memory collatInfo,
        uint256 amountOut
    ) internal view returns (uint256 amountIn) {
        KheopsStorage storage ks = s.kheopsStorage();
        uint256 oracleValue = OracleLib.readMint(collatInfo.oracle);
        uint256 _reserves = ks.reserves;
        uint256 amountOutCorrected = (amountOut * c._BASE_27) / ks.accumulator;
        uint64 newExposure = uint64(
            ((collatInfo.r + amountOutCorrected) * c._BASE_9) / (_reserves + amountOutCorrected)
        );
        uint64 currentExposure = uint64((collatInfo.r * c._BASE_9) / _reserves);
        int64 fees = Utils.piecewiseMean(currentExposure, newExposure, collatInfo.xFeeMint, collatInfo.yFeeMint);
        amountIn = Utils.convertDecimalTo(applyFeeIn(amountOut, oracleValue, fees), 18, collatInfo.decimals);
    }

    function quoteBurnExact(Collateral memory collatInfo, uint256 amountIn) internal view returns (uint256 amountOut) {
        KheopsStorage storage ks = s.kheopsStorage();
        uint256 oracleValue = getBurnOracle(collatInfo.oracle);
        uint64 newExposure;
        uint256 _reserves = ks.reserves;
        uint256 amountInCorrected = (amountIn * c._BASE_27) / ks.accumulator;
        if (amountInCorrected == ks.reserves) newExposure = 0;
        else newExposure = uint64(((collatInfo.r - amountInCorrected) * c._BASE_9) / (_reserves - amountInCorrected));
        uint64 currentExposure = uint64((collatInfo.r * c._BASE_9) / _reserves);
        int64 fees = Utils.piecewiseMean(newExposure, currentExposure, collatInfo.xFeeBurn, collatInfo.yFeeBurn);
        amountOut = Utils.convertDecimalTo(applyFeeOut(amountIn, oracleValue, fees), 18, collatInfo.decimals);
    }

    function quoteBurnForExact(
        Collateral memory collatInfo,
        uint256 amountOut
    ) internal view returns (uint256 amountIn) {
        KheopsStorage storage ks = s.kheopsStorage();
        uint256 oracleValue = getBurnOracle(collatInfo.oracle);
        uint256 _reserves = ks.reserves;
        uint256 _accumulator = ks.accumulator;
        uint64 currentExposure = uint64((collatInfo.r * c._BASE_9) / _reserves);
        // Over estimating the amount of stablecoins that will need to be burnt to overestimate the fees down the line
        // 1. Getting current fee
        int64 fees = Utils.piecewiseMean(currentExposure, currentExposure, collatInfo.xFeeBurn, collatInfo.yFeeBurn);
        // 2. Getting stablecoin amount to burn for these current fees
        uint256 estimatedStablecoinAmount = (applyFeeIn(amountOut, oracleValue, fees) * c._BASE_27) / _accumulator;
        // 3. Getting max exposure with this stablecoin amount
        uint64 newExposure = uint64(
            ((collatInfo.r - estimatedStablecoinAmount) * c._BASE_9) / (_reserves - estimatedStablecoinAmount)
        );
        // 4. Computing the max fee with this exposure
        fees = Utils.piecewiseMean(newExposure, newExposure, collatInfo.xFeeBurn, collatInfo.yFeeBurn);
        // 5. Underestimating the amount that needs to be burnt
        estimatedStablecoinAmount =
            (applyFeeIn(Utils.convertDecimalTo(amountOut, collatInfo.decimals, 18), oracleValue, fees) * c._BASE_27) /
            _accumulator;
        // 6. Getting exposure from this
        if (estimatedStablecoinAmount >= ks.reserves) newExposure = 0;
        else
            newExposure = uint64(
                ((collatInfo.r - estimatedStablecoinAmount) * c._BASE_9) / (_reserves - estimatedStablecoinAmount)
            );
        // 7. Deducing fees
        fees = Utils.piecewiseMean(newExposure, currentExposure, collatInfo.xFeeBurn, collatInfo.yFeeBurn);
        amountIn = applyFeeIn(amountOut, oracleValue, fees);
    }

    function getBurnOracle(bytes memory oracleData) internal view returns (uint256) {
        KheopsStorage storage ks = s.kheopsStorage();
        uint256 oracleValue = c._BASE_18;
        address[] memory list = ks.collateralList;
        uint256 length = list.length;
        uint256 deviation = c._BASE_18;
        for (uint256 i; i < length; ++i) {
            bytes memory oracle = ks.collaterals[list[i]].oracle;
            uint256 deviationValue = c._BASE_18;

            // TODO Change the comparison mechanism
            if (keccak256(oracle) != keccak256("0x") && keccak256(oracle) != keccak256(oracleData)) {
                (, deviationValue) = OracleLib.readBurn(oracleData);
            } else if (keccak256(oracle) != keccak256("0x")) {
                (oracleValue, deviationValue) = OracleLib.readBurn(oracleData);
            }
            if (deviationValue < deviation) deviation = deviationValue;
        }
        // Renormalizing by an overestimated value of the oracle
        return (deviation * c._BASE_18) / oracleValue;
    }

    function applyFeeOut(uint256 amountIn, uint256 oracleValue, int64 fees) internal pure returns (uint256 amountOut) {
        if (fees >= 0) amountOut = (oracleValue * (c._BASE_9 - uint256(int256(fees))) * amountIn) / c._BASE_27;
        else amountOut = (oracleValue * (c._BASE_9 + uint256(int256(-fees))) * amountIn) / c._BASE_27;
    }

    function applyFeeIn(uint256 amountOut, uint256 oracleValue, int64 fees) internal pure returns (uint256 amountIn) {
        if (fees >= 0) {
            uint256 feesDenom = (c._BASE_9 - uint256(int256(fees)));
            if (feesDenom == 0) amountIn = type(uint256).max;
            else amountIn = (amountOut * c._BASE_27) / (feesDenom * oracleValue);
        } else amountIn = (amountOut * c._BASE_27) / ((c._BASE_9 + uint256(int256(-fees))) * oracleValue);
    }

    function checkAmounts(Collateral memory collatInfo, uint256 amountOut) internal view {
        // Checking if enough is available for collateral assets that involve manager addresses
        if (collatInfo.manager != address(0) && IManager(collatInfo.manager).maxAvailable() < amountOut)
            revert InvalidSwap();
    }

    function getMintBurn(
        address tokenIn,
        address tokenOut
    ) internal view returns (bool mint, Collateral memory collatInfo) {
        KheopsStorage storage ks = s.kheopsStorage();
        address _agToken = address(ks.agToken);
        if (tokenIn == _agToken) {
            collatInfo = ks.collaterals[tokenOut];
            mint = false;
        } else if (tokenOut == _agToken) {
            collatInfo = ks.collaterals[tokenIn];
            mint = true;
        } else revert InvalidTokens();
        if (collatInfo.unpaused == 0) revert InvalidTokens();
    }
}
