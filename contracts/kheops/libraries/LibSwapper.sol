// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IAgToken } from "../../interfaces/IAgToken.sol";

import { LibManager } from "./LibManager.sol";
import { LibStorage as s } from "./LibStorage.sol";
import { LibHelper } from "./LibHelper.sol";
import { LibOracle } from "./LibOracle.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import "../utils/Utils.sol";
import "../Storage.sol";

// Struct to help storing local variables to avoid stack too deep issues
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
    // The `to` address is not indexed as there cannot be 4 indexed addresses in an event.
    event Swap(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address indexed from,
        address to
    );
    using SafeERC20 for IERC20;

    /// @notice Processes the internal metric updates and the transfers following mint or burn operations
    function swap(
        Collateral memory collatInfo,
        uint256 amountIn,
        uint256 amountOut,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline,
        bool mint
    ) internal {
        KheopsStorage storage ks = s.kheopsStorage();
        if (block.timestamp > deadline) revert TooLate();
        if (mint) {
            uint128 changeAmount = uint128((amountOut * BASE_27) / ks.normalizer);
            // The amount of stablecoins issued from a collateral are not stored as absolute variables, but
            // as variables normalized by a `normalizer`
            ks.collaterals[tokenIn].normalizedStables += uint224(changeAmount);
            ks.normalizedStables += changeAmount;
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
            IAgToken(tokenOut).mint(to, amountOut);
        } else {
            uint128 changeAmount = uint128((amountIn * BASE_27) / ks.normalizer);
            // This will underflow: the system is trying to burn more stablecoins than what has been issued
            // from this collateral
            ks.collaterals[tokenOut].normalizedStables -= uint224(changeAmount);
            ks.normalizedStables -= changeAmount;
            IAgToken(tokenIn).burnSelf(amountIn, msg.sender);
            {
                ManagerStorage memory emptyManagerData;
                LibHelper.transferCollateral(
                    tokenOut,
                    to,
                    amountOut,
                    collatInfo.isManaged > 0 ? collatInfo.managerData : emptyManagerData
                );
            }
        }
        emit Swap(tokenIn, tokenOut, amountIn, amountOut, msg.sender, to);
    }

    /// @notice Computes the `amountOut` of stablecoins to mint from `tokenIn` of a collateral with data `collatInfo`
    function quoteMintExactInput(
        Collateral memory collatInfo,
        uint256 amountIn
    ) internal view returns (uint256 amountOut) {
        uint256 oracleValue = LibOracle.readMint(collatInfo.oracleConfig);
        amountOut = (oracleValue * Utils.convertDecimalTo(amountIn, collatInfo.decimals, 18)) / BASE_18;
        amountOut = quoteFees(collatInfo, QuoteType.MintExactInput, amountOut);
    }

    /// @notice Computes the `amountIn` of collateral to get during a mint of `amountOut` of stablecoins
    function quoteMintExactOutput(
        Collateral memory collatInfo,
        uint256 amountOut
    ) internal view returns (uint256 amountIn) {
        uint256 oracleValue = LibOracle.readMint(collatInfo.oracleConfig);
        amountIn = quoteFees(collatInfo, QuoteType.MintExactOutput, amountOut);
        amountIn = (Utils.convertDecimalTo(amountIn, 18, collatInfo.decimals) * BASE_18) / oracleValue;
    }

    /// @notice Computes the `amountOut` of `collateral` to give during a burn operation of `amountIn` of stablecoins
    function quoteBurnExactInput(
        address collateral,
        Collateral memory collatInfo,
        uint256 amountIn
    ) internal view returns (uint256 amountOut) {
        uint256 oracleValue = getBurnOracle(collateral, collatInfo.oracleConfig);
        amountOut = quoteFees(collatInfo, QuoteType.BurnExactOutput, amountIn);
        amountOut = (Utils.convertDecimalTo(amountOut, 18, collatInfo.decimals) * BASE_18) / oracleValue;
    }

    /// @notice Computes the `amountIn` of stablecoins to burn to release `amountOut` of `collateral`
    function quoteBurnExactOutput(
        address collateral,
        Collateral memory collatInfo,
        uint256 amountOut
    ) internal view returns (uint256 amountIn) {
        uint256 oracleValue = getBurnOracle(collateral, collatInfo.oracleConfig);
        amountIn = (oracleValue * Utils.convertDecimalTo(amountOut, collatInfo.decimals, 18)) / BASE_18;
        amountIn = quoteFees(collatInfo, QuoteType.BurnExactInput, amountIn);
    }

    /// @notice Computes the fees to apply during a mint or burn operation
    /// @dev This function leverages the mathematical computations of the appendix of the whitepaper
    function quoteFees(
        Collateral memory collatInfo,
        QuoteType quoteType,
        uint256 amountStable
    ) internal view returns (uint256) {
        LocalVariables memory v;
        KheopsStorage storage ks = s.kheopsStorage();

        uint256 normalizedStablesMem = ks.normalizedStables;
        uint256 normalizerMem = ks.normalizer;
        v.isMint = (quoteType == QuoteType.MintExactInput) || (quoteType == QuoteType.MintExactOutput);
        v.isInput = (quoteType == QuoteType.MintExactInput) || (quoteType == QuoteType.BurnExactInput);

        // Handling the initialisation
        if (normalizedStablesMem == 0) {
            // In case the operation is a burn it will revert later on
            return
                v.isInput
                    ? applyFee(amountStable, collatInfo.yFeeMint[0])
                    : invertFee(amountStable, collatInfo.yFeeMint[0]);
        }

        uint256 currentExposure = uint64((collatInfo.normalizedStables * BASE_9) / normalizedStablesMem);
        uint256 n = v.isMint ? collatInfo.xFeeMint.length : collatInfo.xFeeBurn.length;

        // The first case to consider is that of constant fees
        if (n == 1) {
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
                // From the fee parameters which give sets of (exposure, fee at this exposure), we derive a linear function
                // depending on the amount swapped
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
                    // The `xFeeBurn` values are decreasing values of the exposure so that the maths of the mint case
                    // can be applied to the burn case
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
                        amount += (v.isInput ? v.amountToNextBreakPoint : amountToNextBreakPointWithFees);
                        currentExposure = v.upperExposure;
                        ++i;
                    }
                }
            }
            // If we go out of the loop, then `i == n-1` so we are in an area where fees are constant
            return
                amount +
                (
                    (quoteType == QuoteType.MintExactOutput || quoteType == QuoteType.BurnExactOutput)
                        ? invertFee(amountStable, collatInfo.yFeeMint[n - 1])
                        : applyFee(amountStable, collatInfo.yFeeMint[n - 1])
                );
        }
    }

    function applyFee(uint256 amountIn, int64 fees) internal pure returns (uint256 amountOut) {
        if (fees >= 0) amountOut = ((BASE_9 - uint256(int256(fees))) * amountIn) / BASE_9;
        else amountOut = ((BASE_9 + uint256(int256(-fees))) * amountIn) / BASE_9;
    }

    function invertFee(uint256 amountOut, int64 fees) internal pure returns (uint256 amountIn) {
        // The function must (and will) revert anyway if `uint256(int256(fees))==BASE_9`
        if (fees >= 0) amountIn = (BASE_9 * amountOut) / (BASE_9 - uint256(int256(fees)));
        else amountIn = (BASE_9 * amountOut) / (BASE_9 + uint256(int256(-fees)));
    }

    /// @notice Reads the oracle value for burning stablecoins for `collateral` that has an oracle defined by an `oracleConfig`
    /// @dev This value depends on the oracle values for all collateral assets of the system
    function getBurnOracle(address collateral, bytes memory oracleConfig) internal view returns (uint256) {
        KheopsStorage storage ks = s.kheopsStorage();
        uint256 oracleValue;
        uint256 deviation = BASE_18;
        address[] memory collateralList = ks.collateralList;
        uint256 length = collateralList.length;
        for (uint256 i; i < length; ++i) {
            uint256 deviationObserved = BASE_18;
            if (collateralList[i] != collateral) {
                (, deviationObserved) = LibOracle.readBurn(ks.collaterals[collateralList[i]].oracleConfig);
            } else (oracleValue, deviationObserved) = LibOracle.readBurn(oracleConfig);
            if (deviationObserved < deviation) deviation = deviationObserved;
        }
        // This reverts if `oracleValue == 0`
        return (deviation * BASE_18) / oracleValue;
    }

    /// @notice Checks for managed collateral assets if enough funds can be pulled from their strategies
    function checkAmounts(address collateral, Collateral memory collatInfo, uint256 amountOut) internal view {
        // Checking if enough is available for collateral assets that involve manager addresses
        if (collatInfo.isManaged > 0 && LibManager.maxAvailable(collateral, collatInfo.managerData) < amountOut)
            revert InvalidSwap();
    }

    /// @notice Checks whether a swap from `tokenIn` to `tokenOut` is a mint or a burn
    /// @dev The function reverts if the `tokenIn` and `tokenOut` given to not correspond to the stablecoin
    /// and to an accepted collateral asset of the system
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
