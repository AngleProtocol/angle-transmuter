// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import { Storage as s } from "./Storage.sol";
import "./Oracle.sol";
import "../utils/Utils.sol";
import "../Storage.sol";

import "../../interfaces/IAgToken.sol";
import "../../interfaces/IModule.sol";
import "../../interfaces/IManager.sol";

library Swapper {
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
            otherAmount = mint ? quoteMintIn(collatInfo, amount) : quoteBurnIn(collatInfo, amount);
            if (otherAmount < slippage) revert TooSmallAmountOut();
            (amountIn, amountOut) = (amount, otherAmount);
        } else {
            otherAmount = mint ? quoteMintOut(collatInfo, amount) : quoteBurnOut(collatInfo, amount);
            if (otherAmount > slippage) revert TooBigAmountIn();
            (amountIn, amountOut) = (otherAmount, amount);
        }
        if (mint) {
            address toProtocolAddress = collatInfo.manager != address(0) ? collatInfo.manager : address(this);
            uint256 changeAmount = (amountOut * BASE_27) / ks.accumulator;
            ks.collaterals[tokenOut].r += changeAmount;
            ks.reserves += changeAmount;
            IERC20(tokenIn).safeTransferFrom(msg.sender, toProtocolAddress, amountIn);
            IAgToken(tokenOut).mint(to, amountOut);
        } else {
            uint256 changeAmount = (amountIn * BASE_27) / ks.accumulator;
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
        if (_reserves == 0) newAccumulatorValue = BASE_27;
        else if (increase) {
            newAccumulatorValue = _accumulator + (amount * BASE_27) / _reserves;
        } else {
            newAccumulatorValue = _accumulator - (amount * BASE_27) / _reserves;
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
                newAccumulatorValue = BASE_27;
            }
        }
        ks.accumulator = newAccumulatorValue;
    }

    function quoteMintIn(Collateral memory collatInfo, uint256 amountIn) internal view returns (uint256 amountOut) {
        uint256 oracleValue = OracleLib.readMint(collatInfo.oracle);
        amountOut = (oracleValue * Utils.convertDecimalTo(amountIn, collatInfo.decimals, 18)) / c._BASE_18;
        amountOut = quoteFees(collatInfo, collatInfo.xFeeMint, collatInfo.yFeeMint, amountOut);
    }

    function quoteMintOut(Collateral memory collatInfo, uint256 amountOut) internal view returns (uint256 amountIn) {
        uint256 oracleValue = OracleLib.readMint(collatInfo.oracle);
        amountIn = quoteFees(collatInfo, collatInfo.xFeeMint, collatInfo.yFeeMint, amountOut);
        amountIn = (Utils.convertDecimalTo(amountIn, 18, collatInfo.decimals) * c._BASE_18) / oracleValue;
    }

    function quoteFees(
        Collateral memory collatInfo,
        uint64[] xFee,
        int64[] yFee,
        uint256 amountWithFees
    ) internal view returns (uint256) {
        KheopsStorage storage ks = s.kheopsStorage();
        uint256 _reserves = ks.reserves;
        uint256 _accumulator = ks.accumulator;
        uint256 currentExposure = uint64((collatInfo.r * c._BASE_9) / _reserves);

        // Compute amount out.
        uint256 n = xFee.length;
        if (n == 1) {
            // First case: constant fees
            return applyFee(amountInWithFees, collatInfo.yFeeBurn[0]);
        } else {
            uint256 amount;

            uint256 i = Utils.findIndexThres(uint64(currentExposure), xFee);
            while (i < n - 1) {
                uint256 lowerExposure = collatInfo.xFeeBurn[i];
                uint256 upperExposure = collatInfo.xFeeBurn[i + 1];
                int256 lowerFees = collatInfo.yFeeBurn[i];
                int256 upperFees = collatInfo.yFeeBurn[i + 1];

                // We transform the linear function on exposure to a linear function depending on the amount swapped
                uint256 amountToNextBreakPoint = ((_accumulator * (_reserves * upperExposure - collatInfo.r)) /
                    ((c._BASE_9 - upperExposure) * c._BASE_27));
                uint256 amountFromPrevBreakPoint = ((_accumulator * (collatInfo.r - _reserves * lowerExposure)) /
                    ((c._BASE_9 - lowerExposure) * c._BASE_27));
                // upperFees - lowerFees > 0 because fees are an increasing function of exposure (for mint) and 1-exposure (for burn)
                uint256 slope = (uint256(upperFees - lowerFees) / (amountToNextBreakPoint + amountFromPrevBreakPoint));

                // TODO Safe casts
                int256 currentFees;
                if (lowerExposure == currentExposure) currentFees = lowerFees;
                else currentFees = lowerFees + int256(slope * amountFromPrevBreakPoint);

                uint256 amountToNextBreakPointWithFees = invertFee(
                    amountToNextBreakPoint,
                    int64(upperFees + currentFees) / 2
                );

                if (amountFromPrevBreakPointWithFees >= amountWithFees) {
                    return
                        amountIn +
                        applyFee(
                            amountWithFees,
                            int64(
                                (upperFees *
                                    int256(amountWithFees) +
                                    currentFees *
                                    int256(2 * amountFromPrevBreakPointWithFees - amountWithFees)) /
                                    int256(2 * amountFromPrevBreakPointWithFees)
                            )
                        );
                } else {
                    amountWithFees -= amountFromPrevBreakPointWithFees;
                    amount += amountFromPrevBreakPoint;
                    currentExposure = upperExposure;
                    i++;
                }
            }
            return amount + applyFee(amountWithFees, yFee[n - 1]);
        }
    }

    function applyFee(uint256 amountIn, int64 fees) internal pure returns (uint256 amountOut) {
        if (fees >= 0) amountOut = ((BASE_9 - uint256(int256(fees))) * amountIn) / BASE_9;
        else amountOut = ((BASE_9 + uint256(int256(-fees))) * amountIn) / BASE_9;
    }

    function invertFee(uint256 amountIn, int64 fees) internal pure returns (uint256 amountOut) {
        if (fees >= 0) amountOut = (BASE_9 * amountIn) / (BASE_9 - uint256(int256(fees)));
        else amountOut = (BASE_9 * amountIn) / (BASE_9 + uint256(int256(-fees)));
    }

    function quoteBurnIn(Collateral memory collatInfo, uint256 amountIn) internal view returns (uint256 amountOut) {
        (uint64[] xFee, int64[] yFee) = _symmetricPiecewise(collatInfo.xFeeBurn, collatInfo.yFeeBurn);
        uint256 oracleValue = getBurnOracle(collatInfo.oracle);
        amountOut = quoteFees(collatInfo, xFee, yFee, amountIn);
        amountOut = (Utils.convertDecimalTo(amountOut, 18, collatInfo.decimals) * c._BASE_18) / oracleValue;
    }

    function quoteBurnOut(Collateral memory collatInfo, uint256 amountOut) internal view returns (uint256 amountIn) {
        (uint64[] xFee, int64[] yFee) = _symmetricPiecewise(collatInfo.xFeeBurn, collatInfo.yFeeBurn);
        uint256 oracleValue = getBurnOracle(collatInfo.oracle);
        amountIn = (oracleValue * Utils.convertDecimalTo(amountOut, collatInfo.decimals, 18)) / c._BASE_18;
        amountIn = quoteFees(collatInfo, xFee, yFee, amountIn);
    }

    function symmetricPiecewise(uint64[] xFee, int64[] yFee) internal returns (uint64[] xSymFee, int64[] ySimFee) {
        uint256 listLengt = xFee.length;
        xSymFee = new uint64[](listLengt);
        ySymFee = new int64[](listLengt);
        for (uint256 i; i < listLengt; ++i) {
            xSimFee[i] = xFee[listLengt - 1 - i];
            ySymFee[i] = yFee[listLengt - 1 - i];
        }
    }

    function getBurnOracle(bytes memory oracleData) internal view returns (uint256) {
        KheopsStorage storage ks = s.kheopsStorage();
        uint256 oracleValue = BASE_18;
        address[] memory list = ks.collateralList;
        uint256 length = list.length;
        uint256 deviation = BASE_18;
        for (uint256 i; i < length; ++i) {
            bytes memory oracle = ks.collaterals[list[i]].oracle;
            uint256 deviationValue = BASE_18;

            // TODO Change the comparison mechanism
            if (keccak256(oracle) != keccak256("0x") && keccak256(oracle) != keccak256(oracleData)) {
                (, deviationValue) = Oracle.readBurn(oracleData);
            } else if (keccak256(oracle) != keccak256("0x")) {
                (oracleValue, deviationValue) = Oracle.readBurn(oracleData);
            }
            if (deviationValue < deviation) deviation = deviationValue;
        }
        // Renormalizing by an overestimated value of the oracle
        return (deviation * BASE_18) / oracleValue;
    }

    function applyFeeOut(uint256 amountIn, uint256 oracleValue, int64 fees) internal pure returns (uint256 amountOut) {
        if (fees >= 0) amountOut = (oracleValue * (BASE_9 - uint256(int256(fees))) * amountIn) / BASE_27;
        else amountOut = (oracleValue * (BASE_9 + uint256(int256(-fees))) * amountIn) / BASE_27;
    }

    function applyFeeIn(uint256 amountOut, uint256 oracleValue, int64 fees) internal pure returns (uint256 amountIn) {
        if (fees >= 0) {
            uint256 feesDenom = (BASE_9 - uint256(int256(fees)));
            if (feesDenom == 0) amountIn = type(uint256).max;
            else amountIn = (amountOut * BASE_27) / (feesDenom * oracleValue);
        } else amountIn = (amountOut * BASE_27) / ((BASE_9 + uint256(int256(-fees))) * oracleValue);
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
