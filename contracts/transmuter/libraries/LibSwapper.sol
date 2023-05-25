// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "oz/utils/math/Math.sol";
import "oz/token/ERC20/IERC20.sol";
import "oz/token/ERC20/utils/SafeERC20.sol";

import { IAgToken } from "interfaces/IAgToken.sol";

import { LibHelpers } from "./LibHelpers.sol";
import { LibManager } from "./LibManager.sol";
import { LibOracle } from "./LibOracle.sol";
import { LibStorage as s } from "./LibStorage.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import "../Storage.sol";

// Struct to help storing local variables to avoid stack too deep issues
struct LocalVariables {
    bool isMint;
    bool isExact;
    uint256 lowerExposure;
    uint256 upperExposure;
    int256 lowerFees;
    int256 upperFees;
    uint256 amountToNextBreakPoint;
    uint256 otherStablecoinSupply;
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
        TransmuterStorage storage ks = s.transmuterStorage();
        if (block.timestamp > deadline) revert TooLate();
        if (mint) {
            uint128 changeAmount = uint128((amountOut * BASE_27) / ks.normalizer);
            // The amount of stablecoins issued from a collateral are not stored as absolute variables, but
            // as variables normalized by a `normalizer`
            ks.collaterals[tokenIn].normalizedStables += uint224(changeAmount);
            ks.normalizedStables += changeAmount;
            {
                ManagerStorage memory emptyManagerData;
                LibHelpers.transferCollateralFrom(
                    tokenIn,
                    amountIn,
                    collatInfo.isManaged > 0 ? collatInfo.managerData : emptyManagerData
                );
            }
            IAgToken(tokenOut).mint(to, amountOut);
        } else {
            {
                uint128 changeAmount = uint128((amountIn * BASE_27) / ks.normalizer);
                // This will underflow when the system is trying to burn more stablecoins than what has been issued
                // from this collateral
                ks.collaterals[tokenOut].normalizedStables -= uint224(changeAmount);
                ks.normalizedStables -= changeAmount;
            }
            IAgToken(tokenIn).burnSelf(amountIn, msg.sender);
            {
                ManagerStorage memory emptyManagerData;
                LibHelpers.transferCollateralTo(
                    tokenOut,
                    to,
                    amountOut,
                    false,
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
        amountOut = LibHelpers.convertDecimalTo(oracleValue * amountIn, 18 + collatInfo.decimals, 18);
        amountOut = quoteFees(collatInfo, QuoteType.MintExactInput, amountOut);
    }

    /// @notice Computes the `amountIn` of collateral to get during a mint of `amountOut` of stablecoins
    function quoteMintExactOutput(
        Collateral memory collatInfo,
        uint256 amountOut
    ) internal view returns (uint256 amountIn) {
        uint256 oracleValue = LibOracle.readMint(collatInfo.oracleConfig);
        amountIn = quoteFees(collatInfo, QuoteType.MintExactOutput, amountOut);
        amountIn = LibHelpers.convertDecimalTo((amountIn * BASE_18) / oracleValue, 18, collatInfo.decimals);
    }

    /// @notice Computes the `amountIn` of stablecoins to burn to release `amountOut` of `collateral`
    function quoteBurnExactOutput(
        address collateral,
        Collateral memory collatInfo,
        uint256 amountOut
    ) internal view returns (uint256 amountIn) {
        (uint256 deviation, uint256 oracleValue) = getBurnOracle(collateral, collatInfo.oracleConfig);
        amountIn = Math.mulDiv(LibHelpers.convertDecimalTo(amountOut, collatInfo.decimals, 18), oracleValue, deviation);
        amountIn = quoteFees(collatInfo, QuoteType.BurnExactOutput, amountIn);
    }

    /// @notice Computes the `amountOut` of `collateral` to give during a burn operation of `amountIn` of stablecoins
    function quoteBurnExactInput(
        address collateral,
        Collateral memory collatInfo,
        uint256 amountIn
    ) internal view returns (uint256 amountOut) {
        (uint256 deviation, uint256 oracleValue) = getBurnOracle(collateral, collatInfo.oracleConfig);
        amountOut = quoteFees(collatInfo, QuoteType.BurnExactInput, amountIn);
        amountOut = LibHelpers.convertDecimalTo((amountOut * deviation) / oracleValue, 18, collatInfo.decimals);
    }

    /// @notice Computes the fees to apply during a mint or burn operation
    /// @dev This function leverages the mathematical computations of the appendix of the whitepaper
    function quoteFees(
        Collateral memory collatInfo,
        QuoteType quoteType,
        uint256 amountStable
    ) internal view returns (uint256) {
        LocalVariables memory v;
        TransmuterStorage storage ks = s.transmuterStorage();

        v.isMint = _isMint(quoteType);
        v.isExact = _isExact(quoteType);
        uint256 n = v.isMint ? collatInfo.xFeeMint.length : collatInfo.xFeeBurn.length;

        uint256 currentExposure;
        {
            uint256 normalizedStablesMem = ks.normalizedStables;
            uint256 normalizerMem = ks.normalizer;

            // Handling the initialisation and constant fees
            if (normalizedStablesMem == 0 || n == 1)
                return _computeFee(quoteType, amountStable, v.isMint ? collatInfo.yFeeMint[0] : collatInfo.yFeeBurn[0]);

            // Increase precision because if there is a factor 1e9 betwen total stablecoin supply and
            // one specific collateral it will return a null current exposure
            currentExposure = uint64((collatInfo.normalizedStables * BASE_18) / normalizedStablesMem);

            // store the current stablecoin supply for this collateral
            collatInfo.normalizedStables = uint224((uint256(collatInfo.normalizedStables) * normalizerMem) / BASE_27);
            v.otherStablecoinSupply = (normalizerMem * normalizedStablesMem) / BASE_27 - collatInfo.normalizedStables;
        }

        uint256 amount;
        uint256 i = LibHelpers.findLowerBound(
            v.isMint,
            v.isMint ? collatInfo.xFeeMint : collatInfo.xFeeBurn,
            uint64(BASE_9),
            uint64(currentExposure)
        );

        while (i < n - 1) {
            // We transform the linear function on exposure to a linear function depending on the amount swapped
            if (v.isMint) {
                v.lowerExposure = collatInfo.xFeeMint[i];
                v.upperExposure = collatInfo.xFeeMint[i + 1];
                v.lowerFees = collatInfo.yFeeMint[i];
                v.upperFees = collatInfo.yFeeMint[i + 1];
                v.amountToNextBreakPoint =
                    (v.otherStablecoinSupply * v.upperExposure) /
                    (BASE_9 - v.upperExposure) -
                    collatInfo.normalizedStables;
            } else {
                v.lowerExposure = collatInfo.xFeeBurn[i];
                v.upperExposure = collatInfo.xFeeBurn[i + 1];
                v.lowerFees = collatInfo.yFeeBurn[i];
                v.upperFees = collatInfo.yFeeBurn[i + 1];
                v.amountToNextBreakPoint =
                    collatInfo.normalizedStables -
                    (v.otherStablecoinSupply * v.upperExposure) /
                    (BASE_9 - v.upperExposure);
            }

            int256 currentFees;
            // We can only enter the else in the first iteration of the loop as otherwise we will
            // always be at the beginning of the new segment
            if (v.lowerExposure * BASE_9 == currentExposure) currentFees = v.lowerFees;
            else if (v.lowerFees == v.upperFees) currentFees = v.lowerFees;
            else {
                uint256 amountFromPrevBreakPoint = v.isMint
                    ? collatInfo.normalizedStables -
                        (v.otherStablecoinSupply * v.lowerExposure) /
                        (BASE_9 - v.lowerExposure)
                    : (v.otherStablecoinSupply * v.lowerExposure) /
                        (BASE_9 - v.lowerExposure) -
                        collatInfo.normalizedStables;

                // precision breaks, the protocol takes less risks and charge the highest fee
                if (v.amountToNextBreakPoint + amountFromPrevBreakPoint == 0) {
                    currentFees = v.upperFees;
                } else {
                    // slope is in base 18
                    uint256 slope = ((uint256(v.upperFees - v.lowerFees) * BASE_36) /
                        (v.amountToNextBreakPoint + amountFromPrevBreakPoint));
                    currentFees = v.lowerFees + int256((slope * amountFromPrevBreakPoint) / BASE_36);
                }
                // Safeguard for the protocol to not issue free money if quoteType == BurnExactOutput
                // --> amountToNextBreakPointNormalizer = 0 --> amountToNextBreakPointNormalizer < amountStable
                // Then amountStable is never decrease while amount increase
                if (!v.isMint && currentFees == int256(BASE_9)) revert InvalidSwap();
            }

            {
                uint256 amountToNextBreakPointNormalizer = v.isExact ? v.amountToNextBreakPoint : v.isMint
                    ? invertFeeMint(v.amountToNextBreakPoint, int64(v.upperFees + currentFees) / 2)
                    : applyFeeBurn(v.amountToNextBreakPoint, int64(v.upperFees + currentFees) / 2);

                if (amountToNextBreakPointNormalizer >= amountStable) {
                    int64 midFee;
                    if (v.isExact) {
                        midFee = int64(
                            currentFees +
                                int256(
                                    Math.mulDiv(
                                        uint256(v.upperFees - currentFees),
                                        amountStable,
                                        2 * amountToNextBreakPointNormalizer,
                                        Math.Rounding.Up
                                    )
                                )
                        );
                    } else if (v.isMint) {
                        // v.upperFees - currentFees >=0 because mint fee are increasing
                        uint256 ac4 = Math.mulDiv(
                            2 * amountStable * uint256(v.upperFees - currentFees),
                            BASE_9,
                            v.amountToNextBreakPoint,
                            Math.Rounding.Up
                        );
                        midFee = int64(
                            (int256(
                                Math.sqrt(
                                    // BASE_9 + currentFees >= 0
                                    (uint256(int256(BASE_9) + currentFees)) ** 2 + ac4,
                                    Math.Rounding.Up
                                )
                            ) +
                                currentFees -
                                int256(BASE_9)) / 2
                        );
                    } else {
                        // v.upperFees - currentFees >=0 because burn fee are increasing
                        uint256 ac4 = Math.mulDiv(
                            2 * amountStable * uint256(v.upperFees - currentFees),
                            BASE_9,
                            v.amountToNextBreakPoint,
                            Math.Rounding.Up
                        );
                        // rounding error on ac4: it can be larger than expected and makes the
                        // the mathematical invariant breaks
                        if ((uint256(int256(BASE_9) - currentFees)) ** 2 < ac4)
                            midFee = int64((currentFees + int256(BASE_9)) / 2);
                        else {
                            midFee = int64(
                                int256(
                                    Math.mulDiv(
                                        uint256(
                                            currentFees +
                                                int256(BASE_9) -
                                                int256(
                                                    Math.sqrt(
                                                        // BASE_9 - currentFees >= 0
                                                        (uint256(int256(BASE_9) - currentFees)) ** 2 - ac4,
                                                        Math.Rounding.Down
                                                    )
                                                )
                                        ),
                                        1,
                                        2,
                                        Math.Rounding.Up
                                    )
                                )
                            );
                        }
                    }
                    return amount + _computeFee(quoteType, amountStable, midFee);
                } else {
                    amountStable -= amountToNextBreakPointNormalizer;
                    amount += !v.isExact ? v.amountToNextBreakPoint : v.isMint
                        ? invertFeeMint(v.amountToNextBreakPoint, int64(v.upperFees + currentFees) / 2)
                        : applyFeeBurn(v.amountToNextBreakPoint, int64(v.upperFees + currentFees) / 2);
                    currentExposure = v.upperExposure * BASE_9;
                    ++i;
                    // update for the rest of the swaps the normalized stables
                    collatInfo.normalizedStables = v.isMint
                        ? collatInfo.normalizedStables + uint224(v.amountToNextBreakPoint)
                        : collatInfo.normalizedStables - uint224(v.amountToNextBreakPoint);
                }
            }
        }
        // Now i == n-1 so we are in an area where fees are constant
        return
            amount +
            _computeFee(quoteType, amountStable, v.isMint ? collatInfo.yFeeMint[n - 1] : collatInfo.yFeeBurn[n - 1]);
    }

    function _computeFee(QuoteType quoteType, uint256 amountIn, int64 fees) private pure returns (uint256) {
        return
            quoteType == QuoteType.MintExactInput
                ? applyFeeMint(amountIn, fees)
                : quoteType == QuoteType.MintExactOutput
                ? invertFeeMint(amountIn, fees)
                : quoteType == QuoteType.BurnExactInput
                ? applyFeeBurn(amountIn, fees)
                : invertFeeBurn(amountIn, fees);
    }

    function _isMint(QuoteType quoteType) private pure returns (bool) {
        return quoteType == QuoteType.MintExactInput || quoteType == QuoteType.MintExactOutput;
    }

    function _isExact(QuoteType quoteType) private pure returns (bool) {
        return quoteType == QuoteType.MintExactOutput || quoteType == QuoteType.BurnExactInput;
    }

    function applyFeeMint(uint256 amountIn, int64 fees) internal pure returns (uint256 amountOut) {
        if (fees >= 0) {
            // Consider that if fees are above `BASE_12` this is equivalent to infinite fees
            if (uint256(int256(fees)) >= BASE_12) {
                revert InvalidSwap();
            }
            amountOut = (amountIn * BASE_9) / ((BASE_9 + uint256(int256(fees))));
        } else amountOut = (amountIn * BASE_9) / (BASE_9 - uint256(int256(-fees)));
    }

    function invertFeeMint(uint256 amountOut, int64 fees) internal pure returns (uint256 amountIn) {
        if (fees >= 0) {
            // Consider that if fees are above `BASE_12` this is equivalent to infinite fees
            if (uint256(int256(fees)) >= BASE_12) {
                revert InvalidSwap();
            }
            amountIn = Math.mulDiv(amountOut, BASE_9 + uint256(int256(fees)), BASE_9, Math.Rounding.Up);
        } else amountIn = Math.mulDiv(amountOut, BASE_9 - uint256(int256(-fees)), BASE_9, Math.Rounding.Up);
    }

    function applyFeeBurn(uint256 amountIn, int64 fees) internal pure returns (uint256 amountOut) {
        if (fees >= 0) amountOut = ((BASE_9 - uint256(int256(fees))) * amountIn) / BASE_9;
        else amountOut = ((BASE_9 + uint256(int256(-fees))) * amountIn) / BASE_9;
    }

    function invertFeeBurn(uint256 amountOut, int64 fees) internal pure returns (uint256 amountIn) {
        if (fees >= 0) amountIn = Math.mulDiv(amountOut, BASE_9, BASE_9 - uint256(int256(fees)), Math.Rounding.Up);
        else amountIn = Math.mulDiv(amountOut, BASE_9, BASE_9 + uint256(int256(-fees)), Math.Rounding.Up);
    }

    function getBurnOracle(
        address collateral,
        bytes memory oracleConfig
    ) internal view returns (uint256 deviation, uint256 oracleValue) {
        TransmuterStorage storage ks = s.transmuterStorage();
        deviation = BASE_18;
        address[] memory collateralList = ks.collateralList;
        uint256 length = collateralList.length;
        for (uint256 i; i < length; ++i) {
            uint256 deviationObserved = BASE_18;
            if (collateralList[i] != collateral) {
                uint256 oracleValueTmp;
                (oracleValueTmp, deviationObserved) = LibOracle.readBurn(
                    ks.collaterals[collateralList[i]].oracleConfig
                );
            } else (oracleValue, deviationObserved) = LibOracle.readBurn(oracleConfig);
            if (deviationObserved < deviation) deviation = deviationObserved;
        }
    }

    function checkAmounts(Collateral memory collatInfo, uint256 amountOut) internal view {
        // Checking if enough is available for collateral assets that involve manager addresses
        if (collatInfo.isManaged > 0 && LibManager.maxAvailable(collatInfo.managerData) < amountOut)
            revert InvalidSwap();
    }

    /// @notice Checks whether a swap from `tokenIn` to `tokenOut` is a mint or a burn
    /// @dev The function reverts if the `tokenIn` and `tokenOut` given do not correspond to the stablecoin
    /// and to an accepted collateral asset of the system
    function getMintBurn(
        address tokenIn,
        address tokenOut
    ) internal view returns (bool mint, Collateral memory collatInfo) {
        TransmuterStorage storage ks = s.transmuterStorage();
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
<<<<<<< HEAD:contracts/kheops/libraries/LibSwapper.sol
=======

    function _applyFee(uint256 amountIn, int64 fees) private pure returns (uint256 amountOut) {
        if (fees >= 0) amountOut = ((BASE_9 - uint256(int256(fees))) * amountIn) / BASE_9;
        else amountOut = ((BASE_9 + uint256(int256(-fees))) * amountIn) / BASE_9;
    }

    function _invertFee(uint256 amountOut, int64 fees) private pure returns (uint256 amountIn) {
        // The function must (and will) revert anyway if `uint256(int256(fees))==BASE_9`
        if (fees >= 0) amountIn = (BASE_9 * amountOut) / (BASE_9 - uint256(int256(fees)));
        else amountIn = (BASE_9 * amountOut) / (BASE_9 + uint256(int256(-fees)));
    }

    /// @notice Reads the oracle value for burning stablecoins for `collateral`
    /// @dev This value depends on the oracle values for all collateral assets of the system
    function _getBurnOracle(address collateral, bytes memory oracleConfig) private view returns (uint256) {
        TransmuterStorage storage ks = s.transmuterStorage();
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
>>>>>>> b313c5d (feat: rename kheops into transmuter):contracts/transmuter/libraries/LibSwapper.sol
}
