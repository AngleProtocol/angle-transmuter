// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import { Storage as s } from "./Storage.sol";
import { Helper as LibHelper } from "./Helper.sol";
import "./Oracle.sol";
import "../utils/Utils.sol";
import "../Storage.sol";
import "./LibManager.sol";

import "../../interfaces/IAgToken.sol";

struct LocalVariables {
    uint256 lowerExposure;
    uint256 upperExposure;
    int256 lowerFees;
    int256 upperFees;
    uint256 amountToNextBreakPoint;
}

library LibSwapper {
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
            uint256 changeAmount = (amountOut * BASE_27) / ks.normalizer;
            ks.collaterals[tokenOut].normalizedStables += changeAmount;
            ks.normalizedStables += changeAmount;
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
            IAgToken(tokenOut).mint(to, amountOut);
        } else {
            uint256 changeAmount = (amountIn * BASE_27) / ks.normalizer;
            ks.collaterals[tokenOut].normalizedStables -= changeAmount;
            ks.normalizedStables -= changeAmount;
            IAgToken(tokenIn).burnSelf(amountIn, msg.sender);
            LibHelper.transferCollateral(tokenOut, collatInfo.hasManager > 0 ? tokenOut : address(0), to, amount, true);
        }
    }

    // TODO put comment on setter to showcase this feature
    // Should always be xFeeMint[0] = 0 and xFeeBurn[0] = 1. This is for Arrays.findUpperBound(...)>0, the index exclusive upper bound is never 0
    function quoteMintExactInput(
        Collateral memory collatInfo,
        uint256 amountIn
    ) internal view returns (uint256 amountOut) {
        uint256 oracleValue = Oracle.readMint(collatInfo.oracleConfig, collatInfo.oracleStorage);
        amountOut = (oracleValue * Utils.convertDecimalTo(amountIn, collatInfo.decimals, 18)) / BASE_18;
        amountOut = quoteFees(collatInfo, QuoteType.MintExactInput, amountOut);
    }

    function quoteMintExactOutput(
        Collateral memory collatInfo,
        uint256 amountOut
    ) internal view returns (uint256 amountIn) {
        uint256 oracleValue = Oracle.readMint(collatInfo.oracleConfig, collatInfo.oracleStorage);
        amountIn = quoteFees(collatInfo, QuoteType.MintExactOutput, amountOut);
        amountIn = (Utils.convertDecimalTo(amountIn, 18, collatInfo.decimals) * BASE_18) / oracleValue;
    }

    // TODO put comment on setter to showcase this feature
    // xFeeBurn and yFeeBurn should be set in reverse, ie xFeeBurn = [1, 0.9,0.5,0.2] and yFeeBurn = [0.01,0.01,0.1,1]
    function quoteBurnExactOutput(
        Collateral memory collatInfo,
        uint256 amountOut
    ) internal view returns (uint256 amountIn) {
        uint256 oracleValue = getBurnOracle(collatInfo.oracleConfig, collatInfo.oracleStorage);
        amountIn = (oracleValue * Utils.convertDecimalTo(amountOut, collatInfo.decimals, 18)) / BASE_18;
        amountIn = quoteFees(collatInfo, QuoteType.BurnExactInput, amountIn);
    }

    function quoteBurnExactInput(
        Collateral memory collatInfo,
        uint256 amountIn
    ) internal view returns (uint256 amountOut) {
        uint256 oracleValue = getBurnOracle(collatInfo.oracleConfig, collatInfo.oracleStorage);
        amountOut = quoteFees(collatInfo, QuoteType.BurnExactOutput, amountIn);
        amountOut = (Utils.convertDecimalTo(amountOut, 18, collatInfo.decimals) * BASE_18) / oracleValue;
    }

    // @dev Assumption: collatInfo.xFeeMint.length > 0
    function quoteFees(
        Collateral memory collatInfo,
        QuoteType quoteType,
        uint256 amountStable
    ) internal view returns (uint256) {
        KheopsStorage storage ks = s.kheopsStorage();
        uint256 normalizedStablesMem = ks.normalizedStables;
        uint256 normalizerMem = ks.normalizer;
        uint256 currentExposure = normalizedStablesMem == 0
            ? 0
            : uint64((collatInfo.normalizedStables * BASE_9) / normalizedStablesMem);

        // Compute amount out

        uint256 n = collatInfo.xFeeMint.length;
        if (n == 1) {
            // First case: constant fees
            return
                _isInput(quoteType)
                    ? applyFee(amountStable, collatInfo.yFeeMint[0])
                    : invertFee(amountStable, collatInfo.yFeeMint[0]);
        } else {
            uint256 amount;
            uint256 i = Utils.findUpperBound(
                _isMint(quoteType),
                _isMint(quoteType) ? collatInfo.xFeeMint : collatInfo.xFeeBurn,
                uint64(currentExposure)
            );

            LocalVariables memory l;
            while (i < n) {
                // We transform the linear function on exposure to a linear function depending on the amount swapped
                if (_isMint(quoteType)) {
                    l.lowerExposure = collatInfo.xFeeMint[i];
                    l.upperExposure = collatInfo.xFeeMint[i + 1];
                    l.lowerFees = collatInfo.yFeeMint[i];
                    l.upperFees = collatInfo.yFeeMint[i + 1];
                    l.amountToNextBreakPoint = ((normalizerMem *
                        (normalizedStablesMem * l.upperExposure - collatInfo.normalizedStables)) /
                        ((BASE_9 - l.upperExposure) * BASE_27));
                } else {
                    l.lowerExposure = collatInfo.xFeeBurn[i];
                    l.upperExposure = collatInfo.xFeeBurn[i + 1];
                    l.lowerFees = collatInfo.yFeeBurn[i];
                    l.upperFees = collatInfo.yFeeBurn[i + 1];
                    l.amountToNextBreakPoint = ((normalizerMem *
                        (collatInfo.normalizedStables - normalizedStablesMem * l.upperExposure)) /
                        ((BASE_9 - l.upperExposure) * BASE_27));
                }

                // TODO Safe casts
                int256 currentFees;
                if (l.lowerExposure == currentExposure) currentFees = l.lowerFees;
                else {
                    uint256 amountFromPrevBreakPoint = ((normalizerMem *
                        (
                            _isMint(quoteType)
                                ? (collatInfo.normalizedStables - normalizedStablesMem * l.lowerExposure)
                                : (normalizedStablesMem * l.lowerExposure - collatInfo.normalizedStables)
                        )) / ((BASE_9 - l.lowerExposure) * BASE_27));
                    // upperFees - lowerFees > 0 because fees are an increasing function of exposure (for mint) and 1-exposure (for burn)
                    uint256 slope = (uint256(l.upperFees - l.lowerFees) /
                        (l.amountToNextBreakPoint + amountFromPrevBreakPoint));
                    currentFees = l.lowerFees + int256(slope * amountFromPrevBreakPoint);
                }

                {
                    uint256 amountToNextBreakPointWithFees = _isMint(quoteType)
                        ? applyFee(l.amountToNextBreakPoint, int64(l.upperFees + currentFees) / 2)
                        : invertFee(l.amountToNextBreakPoint, int64(l.upperFees + currentFees) / 2);

                    uint256 amountToNextBreakPointNormalizer = _isInput(quoteType)
                        ? amountToNextBreakPointWithFees
                        : l.amountToNextBreakPoint;
                    if (amountToNextBreakPointNormalizer >= amountStable) {
                        int64 midFee = int64(
                            (l.upperFees *
                                int256(amountStable) +
                                currentFees *
                                int256(2 * amountToNextBreakPointNormalizer - amountStable)) /
                                int256(2 * amountToNextBreakPointNormalizer)
                        );
                        return
                            amount +
                            (
                                (quoteType == QuoteType.MintExactOutput || quoteType == QuoteType.BurnExactOutput)
                                    ? invertFee(amountStable, midFee)
                                    : applyFee(amountStable, midFee)
                            );
                    } else {
                        amountStable -= amountToNextBreakPointNormalizer;
                        amount += (_isInput(quoteType) ? l.amountToNextBreakPoint : amountToNextBreakPointWithFees);
                        currentExposure = l.upperExposure;
                        ++i;
                    }
                }
            }
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
        if (fees >= 0) amountIn = (BASE_9 * amountOut) / (BASE_9 - uint256(int256(fees)));
        else amountIn = (BASE_9 * amountOut) / (BASE_9 + uint256(int256(-fees)));
    }

    // To call this function the collateral must be whitelisted and therefore the oracleData must be set
    function getBurnOracle(bytes memory oracleConfig, bytes memory oracleStorage) internal view returns (uint256) {
        KheopsStorage storage ks = s.kheopsStorage();
        uint256 oracleValue;
        uint256 deviation;
        address[] memory collateralList = ks.collateralList;
        uint256 length = collateralList.length;
        for (uint256 i; i < length; ++i) {
            bytes memory oracleConfigOther = ks.collaterals[collateralList[i]].oracleConfig;
            uint256 deviationValue = BASE_18;
            // low chances of collision - but this can be check from governance when setting
            // a new oracle that it doesn't collude with no other hash of an active oracle
            if (keccak256(oracleConfigOther) != keccak256(oracleConfig)) {
                (, deviationValue) = Oracle.readBurn(oracleConfigOther, oracleStorage);
            } else (oracleValue, deviationValue) = Oracle.readBurn(oracleConfig, oracleStorage);
            if (deviationValue < deviation) deviation = deviationValue;
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
