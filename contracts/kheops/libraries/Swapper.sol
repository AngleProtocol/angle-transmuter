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
        amountIn = (oracleValue * Utils.convertDecimalTo(amountIn, collatInfo.decimals, 18)) / BASE_18;
        amountOut = quoteMintFees(collatInfo, 0, amountIn);
    }

    function quoteMintOut(Collateral memory collatInfo, uint256 amountOut) internal view returns (uint256 amountIn) {
        uint256 oracleValue = OracleLib.readMint(collatInfo.oracle);
        amountIn = quoteMintFees(collatInfo, 1, amountOut);
        amountIn = (Utils.convertDecimalTo(amountIn, 18, collatInfo.decimals) * BASE_18) / oracleValue;
    }

    // // xFeeBurn and yFeeBurn should be set in reverse, ie xFeeBurn = [0.9,0.5,0.2] and yFeeBurn = [0.01,0.1,1]
    // function quoteBurnIn(Collateral memory collatInfo, uint256 amountIn) internal view returns (uint256 amountOut) {
    //     uint256 oracleValue = getBurnOracle(collatInfo.oracle);
    //     amountOut = quoteFees(collatInfo, 2, amountIn);
    //     amountOut = (Utils.convertDecimalTo(amountOut, 18, collatInfo.decimals) * BASE_18) / oracleValue;
    // }

    // function quoteBurnOut(Collateral memory collatInfo, uint256 amountOut) internal view returns (uint256 amountIn) {
    //     uint256 oracleValue = getBurnOracle(collatInfo.oracle);
    //     amountIn = (oracleValue * Utils.convertDecimalTo(amountOut, collatInfo.decimals, 18)) / BASE_18;
    //     amountIn = quoteFees(collatInfo, 3, amountIn);
    // }

    // function quoteFees(
    //     Collateral memory collatInfo,
    //     uint8 interactType,
    //     uint256 amountWithoutFees
    // ) internal view returns (uint256) {
    //     KheopsStorage storage ks = s.kheopsStorage();
    //     uint256 _reserves = ks.reserves;
    //     uint256 _accumulator = ks.accumulator;
    //     uint256 currentExposure = uint64((collatInfo.r * BASE_9) / _reserves);

    //     // Compute amount out.
    //     uint256 n = interactType < 2 ? collatInfo.xFeeMint.length : collatInfo.xFeeBurn.length;
    //     if (n == 1) {
    //         // First case: constant fees
    //         return
    //             interactType % 2 == 0
    //                 ? applyFee(amountWithoutFees, interactType < 2 ? collatInfo.yFeeMint[0] : collatInfo.yFeeBurn[0])
    //                 : 0;
    //     } else {
    //         uint256 amount;
    //         uint256 i = Utils.findIndexThres(
    //             uint64(currentExposure),
    //             interactType < 2 ? collatInfo.xFeeMint : collatInfo.xFeeBurn
    //         );
    //         uint256 lowerExposure;
    //         uint256 upperExposure;
    //         int256 lowerFees;
    //         int256 upperFees;
    //         while (i < n - 1) {
    //             if (interactType < 2) {
    //                 lowerExposure = collatInfo.xFeeMint[i];
    //                 upperExposure = collatInfo.xFeeMint[i + 1];
    //                 lowerFees = collatInfo.yFeeMint[i];
    //                 upperFees = collatInfo.yFeeMint[i + 1];
    //             } else {
    //                 lowerExposure = collatInfo.xFeeBurn[i];
    //                 upperExposure = collatInfo.xFeeBurn[i + 1];
    //                 lowerFees = collatInfo.yFeeBurn[i];
    //                 upperFees = collatInfo.yFeeBurn[i + 1];
    //             }

    //             // We transform the linear function on exposure to a linear function depending on the amount swapped
    //             uint256 amountToNextBreakPoint = ((_accumulator * (_reserves * upperExposure - collatInfo.r)) /
    //                 ((BASE_9 - upperExposure) * BASE_27));

    //             // TODO Safe casts
    //             int256 currentFees;
    //             if (lowerExposure == currentExposure) currentFees = lowerFees;
    //             else {
    //                 uint256 amountFromPrevBreakPoint = ((_accumulator * (collatInfo.r - _reserves * lowerExposure)) /
    //                     ((BASE_9 - lowerExposure) * BASE_27));
    //                 // upperFees - lowerFees > 0 because fees are an increasing function of exposure (for mint) and 1-exposure (for burn)
    //                 uint256 slope = (uint256(upperFees - lowerFees) /
    //                     (amountToNextBreakPoint + amountFromPrevBreakPoint));
    //                 currentFees = lowerFees + int256(slope * amountFromPrevBreakPoint);
    //             }

    //             uint256 amountToNextBreakPointWithoutFees = invertFee(
    //                 amountToNextBreakPoint,
    //                 int64(upperFees + currentFees) / 2
    //             );

    //             if (amountToNextBreakPointWithoutFees >= amountWithoutFees) {
    //                 return
    //                     amount +
    //                     applyFee(
    //                         amountWithoutFees,
    //                         int64(
    //                             (upperFees *
    //                                 int256(amountWithoutFees) +
    //                                 currentFees *
    //                                 int256(2 * amountToNextBreakPointWithoutFees - amountWithoutFees)) /
    //                                 int256(2 * amountToNextBreakPointWithoutFees)
    //                         )
    //                     );
    //             } else {
    //                 amountWithoutFees -= amountToNextBreakPointWithoutFees;
    //                 amount += amountToNextBreakPoint;
    //                 currentExposure = upperExposure;
    //                 ++i;
    //             }
    //         }
    //         return
    //             amount +
    //             applyFee(amountWithoutFees, interactType < 2 ? collatInfo.yFeeMint[n - 1] : collatInfo.yFeeBurn[n - 1]);
    //     }
    // }

    function quoteMintFees(
        Collateral memory collatInfo,
        bool exact,
        uint256 amountStable
    ) internal view returns (uint256) {
        KheopsStorage storage ks = s.kheopsStorage();
        uint256 _reserves = ks.reserves;
        uint256 _accumulator = ks.accumulator;
        uint256 currentExposure = uint64((collatInfo.r * BASE_9) / _reserves);

        // Compute amount out.
        uint256 n = collatInfo.xFeeMint.length;
        if (n == 1) {
            // First case: constant fees
            return
                exact
                    ? invertFee(amountStable, collatInfo.yFeeMint[0])
                    : applyFee(amountStable, collatInfo.yFeeMint[0]);
        } else {
            uint256 amount;
            uint256 i = Utils.findIndexThres(uint64(currentExposure), collatInfo.xFeeMint);
            uint256 lowerExposure;
            uint256 upperExposure;
            int256 lowerFees;
            int256 upperFees;
            while (i < n - 1) {
                lowerExposure = collatInfo.xFeeMint[i];
                upperExposure = collatInfo.xFeeMint[i + 1];
                lowerFees = collatInfo.yFeeMint[i];
                upperFees = collatInfo.yFeeMint[i + 1];

                // We transform the linear function on exposure to a linear function depending on the amount swapped
                uint256 amountToNextBreakPoint = ((_accumulator * (_reserves * upperExposure - collatInfo.r)) /
                    ((BASE_9 - upperExposure) * BASE_27));

                // TODO Safe casts
                int256 currentFees;
                if (lowerExposure == currentExposure) currentFees = lowerFees;
                else {
                    uint256 amountFromPrevBreakPoint = ((_accumulator * (collatInfo.r - _reserves * lowerExposure)) /
                        ((BASE_9 - lowerExposure) * BASE_27));
                    // upperFees - lowerFees > 0 because fees are an increasing function of exposure (for mint) and 1-exposure (for burn)
                    uint256 slope = (uint256(upperFees - lowerFees) /
                        (amountToNextBreakPoint + amountFromPrevBreakPoint));
                    currentFees = lowerFees + int256(slope * amountFromPrevBreakPoint);
                }

                uint256 amountToNextBreakPointWithFees = invertFee(
                    amountToNextBreakPoint,
                    int64(upperFees + currentFees) / 2
                );

                uint256 amountToNextBreakPointNormalizer = exact
                    ? amountToNextBreakPoint
                    : amountToNextBreakPointWithFees;
                if (amountToNextBreakPointNormalizer >= amountStable) {
                    int64 midFee = int64(
                        (upperFees *
                            int256(amountStable) +
                            currentFees *
                            int256(2 * amountToNextBreakPointNormalizer - amountStable)) /
                            int256(2 * amountToNextBreakPointNormalizer)
                    );
                    return amount + (exact ? invertFee(amountStable, midFee) : applyFee(amountStable, midFee));
                } else {
                    amountStable -= amountToNextBreakPointNormalizer;
                    amount += exact ? amountToNextBreakPointWithFees : amountToNextBreakPoint;
                    currentExposure = upperExposure;
                    ++i;
                }
            }
            return
                amount +
                (
                    exact
                        ? invertFee(amountStable, collatInfo.yFeeMint[n - 1])
                        : applyFee(amountStable, collatInfo.yFeeMint[n - 1])
                );
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
