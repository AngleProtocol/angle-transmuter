// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import { LibStorage as s } from "./LibStorage.sol";
import { LibHelper } from "./LibHelper.sol";
import { LibOracle } from "./LibOracle.sol";
import "../utils/Utils.sol";
import "../Storage.sol";
import { LibManager } from "./LibManager.sol";

import { IAgToken } from "../../interfaces/IAgToken.sol";

struct LocalVariables {
    bool isMint;
    bool isInput;
    uint256 lowerExposure;
    uint256 upperExposure;
    int256 lowerFees;
    int256 upperFees;
    uint256 amountToNextBreakPoint;
}

/// @title LibSwapper
/// @author Angle Labs, Inc.
library LibSwapper {
    using SafeERC20 for IERC20;

    // TODO put comment on setter to showcase this feature
    // Should always be xFeeMint[0] = 0 and xFeeBurn[0] = 1. This is for Arrays.findLowerBound(...)>0, the index exclusive upper bound is never 0
    function quoteMintExactInput(
        Collateral memory collatInfo,
        uint256 amountIn
    ) internal view returns (uint256 amountOut) {
        uint256 oracleValue = LibOracle.readMint(collatInfo.oracleConfig);
        amountOut = (oracleValue * Utils.convertDecimalTo(amountIn, collatInfo.decimals, 18)) / BASE_18;
        amountOut = quoteFees(collatInfo, QuoteType.MintExactInput, amountOut);
    }

    function quoteMintExactOutput(
        Collateral memory collatInfo,
        uint256 amountOut
    ) internal view returns (uint256 amountIn) {
        uint256 oracleValue = LibOracle.readMint(collatInfo.oracleConfig);
        amountIn = quoteFees(collatInfo, QuoteType.MintExactOutput, amountOut);
        amountIn = (Utils.convertDecimalTo(amountIn, 18, collatInfo.decimals) * BASE_18) / oracleValue;
    }

    // TODO put comment on setter to showcase this feature
    // xFeeBurn and yFeeBurn should be set in reverse, ie xFeeBurn = [1,0.9,0.5,0.2] and yFeeBurn = [0.01,0.01,0.1,1]
    function quoteBurnExactOutput(
        Collateral memory collatInfo,
        uint256 amountOut
    ) internal view returns (uint256 amountIn) {
        uint256 oracleValue = getBurnOracle(collatInfo.oracleConfig);
        amountIn = (oracleValue * Utils.convertDecimalTo(amountOut, collatInfo.decimals, 18)) / BASE_18;
        amountIn = quoteFees(collatInfo, QuoteType.BurnExactInput, amountIn);
    }

    function quoteBurnExactInput(
        Collateral memory collatInfo,
        uint256 amountIn
    ) internal view returns (uint256 amountOut) {
        uint256 oracleValue = getBurnOracle(collatInfo.oracleConfig);
        amountOut = quoteFees(collatInfo, QuoteType.BurnExactOutput, amountIn);
        amountOut = (Utils.convertDecimalTo(amountOut, 18, collatInfo.decimals) * BASE_18) / oracleValue;
    }

    // @dev Assumption: collatInfo.xFeeMint.length > 0
    function quoteFees(
        Collateral memory collatInfo,
        QuoteType quoteType,
        uint256 amountStable
    ) internal view returns (uint256) {
        LocalVariables memory v;
        KheopsStorage storage ks = s.kheopsStorage();

        uint256 normalizedStablesMem = ks.normalizedStables;
        uint256 normalizerMem = ks.normalizer;
        v.isMint = _isMint(quoteType);
        v.isInput = _isInput(quoteType);

        // Handling the initialisation
        if (normalizedStablesMem == 0) {
            // In case the operation is a burn it will revert later on TODO Confirm with a test
            return
                _isInput(quoteType)
                    ? applyFee(amountStable, collatInfo.yFeeMint[0])
                    : invertFee(amountStable, collatInfo.yFeeMint[0]);
        }

        uint256 currentExposure = uint64((collatInfo.normalizedStables * BASE_9) / normalizedStablesMem);
        uint256 n = v.isMint ? collatInfo.xFeeMint.length : collatInfo.xFeeBurn.length;

        if (n == 1) {
            // First case: constant fees
            if (v.isMint) {
                return
                    v.isInput
                        ? applyFee(amountStable, collatInfo.yFeeMint[0])
                        : invertFee(amountStable, collatInfo.yFeeMint[0]);
            } else {
                return
                    v.isInput
                        ? applyFee(amountStable, collatInfo.yFeeBurn[0])
                        : invertFee(amountStable, collatInfo.yFeeBurn[0]);
            }
        } else {
            uint256 amount;
            uint256 i = Utils.findLowerBound(
                v.isMint,
                v.isMint ? collatInfo.xFeeMint : collatInfo.xFeeBurn,
                uint64(currentExposure)
            );

            while (i <= n - 2) {
                // We transform the linear function on exposure to a linear function depending on the amount swapped
                if (v.isMint) {
                    v.lowerExposure = collatInfo.xFeeMint[i];
                    v.upperExposure = collatInfo.xFeeMint[i + 1];
                    v.lowerFees = collatInfo.yFeeMint[i];
                    v.upperFees = collatInfo.yFeeMint[i + 1];

                    v.amountToNextBreakPoint = ((normalizerMem *
                        (normalizedStablesMem * v.upperExposure - collatInfo.normalizedStables)) /
                        ((BASE_9 - v.upperExposure) * BASE_27));
                } else {
                    v.lowerExposure = collatInfo.xFeeBurn[i];
                    v.upperExposure = collatInfo.xFeeBurn[i + 1];
                    v.lowerFees = collatInfo.yFeeBurn[i];
                    v.upperFees = collatInfo.yFeeBurn[i + 1];
                    v.amountToNextBreakPoint = ((normalizerMem *
                        (collatInfo.normalizedStables - normalizedStablesMem * v.upperExposure)) /
                        ((BASE_9 - v.upperExposure) * BASE_27));
                }

                // TODO Safe casts
                int256 currentFees;
                if (v.lowerExposure == currentExposure) currentFees = v.lowerFees;
                else {
                    uint256 amountFromPrevBreakPoint = ((normalizerMem *
                        (
                            v.isMint
                                ? (collatInfo.normalizedStables - normalizedStablesMem * v.lowerExposure)
                                : (normalizedStablesMem * v.lowerExposure - collatInfo.normalizedStables)
                        )) / ((BASE_9 - v.lowerExposure) * BASE_27));
                    uint256 slope = ((uint256(v.upperFees - v.lowerFees) * BASE_18) /
                        (v.amountToNextBreakPoint + amountFromPrevBreakPoint));
                    currentFees = v.lowerFees + int256((slope * amountFromPrevBreakPoint) / BASE_18);
                }

                {
                    uint256 amountToNextBreakPointWithFees = !v.isMint && v.isInput
                        ? applyFee(v.amountToNextBreakPoint, int64(v.upperFees + currentFees) / 2)
                        : invertFee(v.amountToNextBreakPoint, int64(v.upperFees + currentFees) / 2);

                    uint256 amountToNextBreakPointNormalizer = (v.isMint && v.isInput) || (!v.isMint && !v.isInput)
                        ? amountToNextBreakPointWithFees
                        : v.amountToNextBreakPoint;
                    if (amountToNextBreakPointNormalizer >= amountStable) {
                        int64 midFee = int64(
                            (v.upperFees *
                                int256(amountStable) +
                                currentFees *
                                int256(2 * amountToNextBreakPointNormalizer - amountStable)) /
                                int256(2 * amountToNextBreakPointNormalizer)
                        );
                        return
                            amount + ((!v.isInput) ? invertFee(amountStable, midFee) : applyFee(amountStable, midFee));
                    } else {
                        amountStable -= amountToNextBreakPointNormalizer;
                        amount += (_isInput(quoteType) ? v.amountToNextBreakPoint : amountToNextBreakPointWithFees);
                        currentExposure = v.upperExposure;
                        ++i;
                    }
                }
            }
            // Now i == n-1 so we are in an area where fees are constant
            return
                amount +
                (
                    (quoteType == QuoteType.MintExactOutput || quoteType == QuoteType.BurnExactOutput)
                        ? invertFee(amountStable, collatInfo.yFeeMint[n - 1])
                        : applyFee(amountStable, collatInfo.yFeeMint[n - 1])
                );
        }
    }

    function _isMint(QuoteType quoteType) private pure returns (bool) {
        return quoteType == QuoteType.MintExactInput || quoteType == QuoteType.MintExactOutput;
    }

    function _isInput(QuoteType quoteType) private pure returns (bool) {
        return quoteType == QuoteType.MintExactInput || quoteType == QuoteType.BurnExactInput;
    }

    function applyFee(uint256 amountIn, int64 fees) internal pure returns (uint256 amountOut) {
        if (fees >= 0) amountOut = ((BASE_9 - uint256(int256(fees))) * amountIn) / BASE_9;
        else amountOut = ((BASE_9 + uint256(int256(-fees))) * amountIn) / BASE_9;
    }

    function invertFee(uint256 amountOut, int64 fees) internal pure returns (uint256 amountIn) {
        if (fees >= 0) {
            if (uint256(int256(fees)) == BASE_9) {
                revert InvalidSwap();
            }
            amountIn = (BASE_9 * amountOut) / (BASE_9 - uint256(int256(fees)));
        } else amountIn = (BASE_9 * amountOut) / (BASE_9 + uint256(int256(-fees)));
    }

    function getBurnOracle(bytes memory oracleConfig) internal view returns (uint256) {
        KheopsStorage storage ks = s.kheopsStorage();
        uint256 oracleValue;
        uint256 deviation = BASE_18;
        address[] memory collateralList = ks.collateralList;
        uint256 length = collateralList.length;
        for (uint256 i; i < length; ++i) {
            bytes memory oracleConfigOther = ks.collaterals[collateralList[i]].oracleConfig;
            uint256 deviationObserved = BASE_18;
            // low chances of collision - but this can be check from governance when setting
            // a new oracle that it doesn't collude with no other hash of an active oracle
            if (keccak256(oracleConfigOther) != keccak256(oracleConfig)) {
                (, deviationObserved) = LibOracle.readBurn(oracleConfigOther);
            } else (oracleValue, deviationObserved) = LibOracle.readBurn(oracleConfig);
            if (deviationObserved < deviation) deviation = deviationObserved;
        }
        return (deviation * BASE_18) / oracleValue;
    }

    function checkAmounts(address collateral, Collateral memory collatInfo, uint256 amountOut) internal view {
        // Checking if enough is available for collateral assets that involve manager addresses
        if (collatInfo.hasManager > 0 && LibManager.maxAvailable(collateral) < amountOut) revert InvalidSwap();
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
