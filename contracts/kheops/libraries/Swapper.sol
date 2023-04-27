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
            otherAmount = mint ? quoteMintExactInput(collatInfo, amount) : quoteBurnExactInput(collatInfo, amount);
            if (otherAmount < slippage) revert TooSmallAmountOut();
            (amountIn, amountOut) = (amount, otherAmount);
        } else {
            otherAmount = mint ? quoteMintExactOutput(collatInfo, amount) : quoteBurnExactOutput(collatInfo, amount);
            if (otherAmount > slippage) revert TooBigAmountIn();
            (amountIn, amountOut) = (otherAmount, amount);
        }
        if (mint) {
            address toProtocolAddress = collatInfo.hasManager > 0 ? collatInfo.manager : address(this);
            uint256 changeAmount = (amountOut * BASE_27) / ks.normalizer;
            ks.collaterals[tokenOut].normalizedStables += changeAmount;
            ks.normalizedStables += changeAmount;
            IERC20(tokenIn).safeTransferFrom(msg.sender, toProtocolAddress, amountIn);
            IAgToken(tokenOut).mint(to, amountOut);
        } else {
            uint256 changeAmount = (amountIn * BASE_27) / ks.normalizer;
            ks.collaterals[tokenOut].normalizedStables -= changeAmount;
            ks.normalizedStables -= changeAmount;
            IAgToken(tokenIn).burnSelf(amountIn, msg.sender);
            if (collatInfo.hasManager > 0) IManager(collatInfo.manager).transfer(to, amountOut, false);
            else IERC20(tokenOut).safeTransfer(to, amountOut);
        }
        // if (collatInfo.hasOracleFallback > 0) {
        //     Oracle.updateInternalData(
        //         mint ? tokenIn : tokenOut,
        //         collatInfo.oracle,
        //         collatInfo.oracleStorage,
        //         amountIn,
        //         amountOut,
        //         mint
        //     );
        // }
    }

    function updateAccumulator(uint256 amount, bool increase) internal returns (uint256 newAccumulatorValue) {
        KheopsStorage storage ks = s.kheopsStorage();
        uint256 _normalizer = ks.normalizer;
        uint256 _reserves = ks.normalizedStables;
        if (_reserves == 0) newAccumulatorValue = BASE_27;
        else if (increase) {
            newAccumulatorValue = _normalizer + (amount * BASE_27) / _reserves;
        } else {
            newAccumulatorValue = _normalizer - (amount * BASE_27) / _reserves;
            // TODO check if it remains consistent when it gets too small
            if (newAccumulatorValue == 0) {
                address[] memory _collateralList = ks.collateralList;
                address[] memory depositModuleList = ks.redeemableModuleList;
                uint256 collateralListLength = _collateralList.length;
                uint256 depositModuleListLength = depositModuleList.length;
                for (uint256 i; i < collateralListLength; ++i) {
                    ks.collaterals[_collateralList[i]].normalizedStables = 0;
                }
                for (uint256 i; i < depositModuleListLength; ++i) {
                    ks.modules[depositModuleList[i]].normalizedStables = 0;
                }
                ks.normalizedStables = 0;
                newAccumulatorValue = BASE_27;
            }
        }
        ks.normalizer = newAccumulatorValue;
    }

    // TODO put comment on setter to showcase this feature
    // Should always be xFeeMint[0] = 0 and xFeeBurn[0] = 1. This is for Arrays.findUpperBound(...)>0, the index exclusive upper bound is never 0
    function quoteMintExactInput(
        Collateral memory collatInfo,
        uint256 amountIn
    ) internal view returns (uint256 amountOut) {
        uint256 oracleValue = Oracle.readMint(collatInfo.oracle, collatInfo.oracleStorage);
        amountIn = (oracleValue * Utils.convertDecimalTo(amountIn, collatInfo.decimals, 18)) / BASE_18;
        amountOut = quoteFees(collatInfo, 0, amountIn);
    }

    function quoteMintExactOutput(
        Collateral memory collatInfo,
        uint256 amountOut
    ) internal view returns (uint256 amountIn) {
        uint256 oracleValue = Oracle.readMint(collatInfo.oracle, collatInfo.oracleStorage);
        amountIn = quoteFees(collatInfo, 1, amountOut);
        amountIn = (Utils.convertDecimalTo(amountIn, 18, collatInfo.decimals) * BASE_18) / oracleValue;
    }

    // TODO put comment on setter to showcase this feature
    // xFeeBurn and yFeeBurn should be set in reverse, ie xFeeBurn = [1, 0.9,0.5,0.2] and yFeeBurn = [0.01,0.01,0.1,1]
    function quoteBurnExactOutput(
        Collateral memory collatInfo,
        uint256 amountOut
    ) internal view returns (uint256 amountIn) {
        uint256 oracleValue = getBurnOracle(collatInfo.oracle, collatInfo.oracleStorage);
        amountIn = (oracleValue * Utils.convertDecimalTo(amountOut, collatInfo.decimals, 18)) / BASE_18;
        amountIn = quoteFees(collatInfo, 3, amountIn);
    }

    function quoteBurnExactInput(
        Collateral memory collatInfo,
        uint256 amountIn
    ) internal view returns (uint256 amountOut) {
        uint256 oracleValue = getBurnOracle(collatInfo.oracle, collatInfo.oracleStorage);
        amountOut = quoteFees(collatInfo, 2, amountIn);
        amountOut = (Utils.convertDecimalTo(amountOut, 18, collatInfo.decimals) * BASE_18) / oracleValue;
    }

    // quoteType can be {1,2,3,4}
    // 1 - represent a mint with a given number for stables,
    // in this case amountStable represent the net stable that should be minted
    // 2 - represent a mint with a colateral equivalent amount of stables,
    // in this case amountStable represent the brut stable (not accounting for fees) that should be minted
    // 3 - represent a burn with a colateral equivalent amount of stables
    // in this case amountStable represent the brut stable (not accounting for fees) that should be burnt
    // 4 - represent a burn with a given number for stables
    // in this case amountStable represent the net stable that should be burnt
    function quoteFees(
        Collateral memory collatInfo,
        uint8 quoteType,
        uint256 amountStable
    ) internal view returns (uint256) {
        KheopsStorage storage ks = s.kheopsStorage();
        uint256 _reserves = ks.normalizedStables;
        uint256 _normalizer = ks.normalizer;
        uint256 currentExposure = uint64((collatInfo.normalizedStables * BASE_9) / _reserves);

        // Compute amount out.
        uint256 n = collatInfo.xFeeMint.length;
        if (n == 1) {
            // First case: constant fees
            return
                quoteType % 2 == 0
                    ? invertFee(amountStable, collatInfo.yFeeMint[0])
                    : applyFee(amountStable, collatInfo.yFeeMint[0]);
        } else {
            uint256 amount;
            uint256 i = Utils.findUpperBound(
                quoteType < 2,
                quoteType < 2 ? collatInfo.xFeeMint : collatInfo.xFeeBurn,
                uint64(currentExposure)
            );
            uint256 lowerExposure;
            uint256 upperExposure;
            int256 lowerFees;
            int256 upperFees;
            while (i < n) {
                // We transform the linear function on exposure to a linear function depending on the amount swapped
                uint256 amountToNextBreakPoint;
                if (quoteType < 2) {
                    lowerExposure = collatInfo.xFeeMint[i];
                    upperExposure = collatInfo.xFeeMint[i + 1];
                    lowerFees = collatInfo.yFeeMint[i];
                    upperFees = collatInfo.yFeeMint[i + 1];
                    amountToNextBreakPoint = ((_normalizer *
                        (_reserves * upperExposure - collatInfo.normalizedStables)) /
                        ((BASE_9 - upperExposure) * BASE_27));
                } else {
                    lowerExposure = collatInfo.xFeeBurn[i];
                    upperExposure = collatInfo.xFeeBurn[i + 1];
                    lowerFees = collatInfo.yFeeBurn[i];
                    upperFees = collatInfo.yFeeBurn[i + 1];
                    amountToNextBreakPoint = ((_normalizer *
                        (collatInfo.normalizedStables - _reserves * upperExposure)) /
                        ((BASE_9 - upperExposure) * BASE_27));
                }

                // TODO Safe casts
                int256 currentFees;
                if (lowerExposure == currentExposure) currentFees = lowerFees;
                else {
                    uint256 amountFromPrevBreakPoint = ((_normalizer *
                        (
                            quoteType < 2
                                ? (collatInfo.normalizedStables - _reserves * lowerExposure)
                                : (_reserves * lowerExposure - collatInfo.normalizedStables)
                        )) / ((BASE_9 - lowerExposure) * BASE_27));
                    // upperFees - lowerFees > 0 because fees are an increasing function of exposure (for mint) and 1-exposure (for burn)
                    uint256 slope = (uint256(upperFees - lowerFees) /
                        (amountToNextBreakPoint + amountFromPrevBreakPoint));
                    currentFees = lowerFees + int256(slope * amountFromPrevBreakPoint);
                }

                uint256 amountToNextBreakPointWithFees = quoteType == 3
                    ? applyFee(amountToNextBreakPoint, int64(upperFees + currentFees) / 2)
                    : invertFee(amountToNextBreakPoint, int64(upperFees + currentFees) / 2);

                uint256 amountToNextBreakPointNormalizer = (quoteType == 0 || quoteType == 3)
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
                    return
                        amount +
                        ((quoteType % 2 == 0) ? invertFee(amountStable, midFee) : applyFee(amountStable, midFee));
                } else {
                    amountStable -= amountToNextBreakPointNormalizer;
                    amount += (quoteType == 0 || quoteType == 3)
                        ? amountToNextBreakPointWithFees
                        : amountToNextBreakPoint;
                    currentExposure = upperExposure;
                    ++i;
                }
            }
            return
                amount +
                (
                    (quoteType % 2 == 0)
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

    // To call this function the collateral must be whitelisted and therefore the oracleData must be set
    function getBurnOracle(bytes memory oracleData, bytes memory oracleStorage) internal view returns (uint256) {
        KheopsStorage storage ks = s.kheopsStorage();
        uint256 oracleValue;
        uint256 deviation;
        address[] memory collateralList = ks.collateralList;
        uint256 length = collateralList.length;
        for (uint256 i; i < length; ++i) {
            bytes memory oracle = ks.collaterals[collateralList[i]].oracle;
            uint256 deviationValue = BASE_18;
            // low chances of collision - but this can be check from governance when setting
            // a new oracle that it doesn't collude with no other hash of an active oracle
            if (keccak256(oracle) != keccak256(oracleData)) {
                (, deviationValue) = Oracle.readBurn(oracleData, oracleStorage);
            } else (oracleValue, deviationValue) = Oracle.readBurn(oracleData, oracleStorage);
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
            if (collatInfo.unpausedMint == 0) revert Paused();
        } else if (tokenOut == _agToken) {
            collatInfo = ks.collaterals[tokenIn];
            mint = true;
            if (collatInfo.unpausedBurn == 0) revert Paused();
        } else revert InvalidTokens();
    }
}
