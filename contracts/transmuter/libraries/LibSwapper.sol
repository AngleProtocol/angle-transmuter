// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import { IERC20 } from "oz/token/ERC20/IERC20.sol";
import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";
import { Address } from "oz/utils/Address.sol";
import { Math } from "oz/utils/math/Math.sol";
import { SafeCast } from "oz/utils/math/SafeCast.sol";

import { IAgToken } from "interfaces/IAgToken.sol";
import { IPermit2, PermitTransferFrom } from "interfaces/external/permit2/IPermit2.sol";
import { SignatureTransferDetails, TokenPermissions } from "interfaces/external/permit2/IPermit2.sol";

import { LibHelpers } from "./LibHelpers.sol";
import { LibManager } from "./LibManager.sol";
import { LibOracle } from "./LibOracle.sol";
import { LibStorage as s } from "./LibStorage.sol";
import { LibWhitelist } from "./LibWhitelist.sol";

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
    uint256 stablecoinsIssued;
    uint256 otherStablecoinSupply;
}

/// @title LibSwapper
/// @author Angle Labs, Inc.
library LibSwapper {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using Address for address;
    using Math for uint256;

    // The `to` address is not indexed as there cannot be 4 indexed addresses in an event.
    event Swap(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address indexed from,
        address to
    );

    /// @notice Processes the internal metric updates and the transfers following mint or burn operations
    function swap(
        uint256 amountIn,
        uint256 amountOut,
        address tokenIn,
        address tokenOut,
        address to,
        bool mint,
        Collateral storage collatInfo,
        bytes memory permitData
    ) internal {
        if (amountIn > 0 && amountOut > 0) {
            TransmuterStorage storage ks = s.transmuterStorage();
            if (mint) {
                uint128 changeAmount = (amountOut.mulDiv(BASE_27, ks.normalizer, Math.Rounding.Up)).toUint128();
                // The amount of stablecoins issued from a collateral are not stored as absolute variables, but
                // as variables normalized by a `normalizer`
                collatInfo.normalizedStables += uint216(changeAmount);
                ks.normalizedStables += changeAmount;
                if (permitData.length > 0) {
                    PERMIT_2.functionCall(permitData);
                } else if (collatInfo.isManaged > 0) {
                    IERC20(tokenIn).safeTransferFrom(
                        msg.sender,
                        LibManager.transferRecipient(collatInfo.managerData.config),
                        amountIn
                    );
                } else {
                    IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
                }

                if (collatInfo.isManaged > 0) {
                    LibManager.invest(amountIn, collatInfo.managerData.config);
                }
                IAgToken(tokenOut).mint(to, amountOut);
            } else {
                if (collatInfo.onlyWhitelisted > 0 && !LibWhitelist.checkWhitelist(collatInfo.whitelistData, to))
                    revert NotWhitelisted();
                uint128 changeAmount = ((amountIn * BASE_27) / ks.normalizer).toUint128();
                // This will underflow when the system is trying to burn more stablecoins than what has been issued
                // from this collateral
                collatInfo.normalizedStables -= uint216(changeAmount);
                ks.normalizedStables -= changeAmount;
                IAgToken(tokenIn).burnSelf(amountIn, msg.sender);
                if (collatInfo.isManaged > 0) LibManager.release(to, amountOut, collatInfo.managerData.config);
                else IERC20(tokenOut).safeTransfer(to, amountOut);
            }
        }
        emit Swap(tokenIn, tokenOut, amountIn, amountOut, msg.sender, to);
    }

    /// @notice Computes the `amountOut` of stablecoins to mint from `tokenIn` of a collateral with data `collatInfo`
    function quoteMintExactInput(
        Collateral storage collatInfo,
        uint256 amountIn
    ) internal view returns (uint256 amountOut) {
        uint256 oracleValue = LibOracle.readMint(collatInfo.oracleConfig);
        amountOut = LibHelpers.convertDecimalTo(oracleValue * amountIn, 18 + collatInfo.decimals, 18);
        amountOut = quoteFees(collatInfo, QuoteType.MintExactInput, amountOut);
    }

    /// @notice Computes the `amountIn` of collateral to get during a mint of `amountOut` of stablecoins
    function quoteMintExactOutput(
        Collateral storage collatInfo,
        uint256 amountOut
    ) internal view returns (uint256 amountIn) {
        uint256 oracleValue = LibOracle.readMint(collatInfo.oracleConfig);
        amountIn = quoteFees(collatInfo, QuoteType.MintExactOutput, amountOut);
        amountIn = LibHelpers.convertDecimalTo((amountIn * BASE_18) / oracleValue, 18, collatInfo.decimals);
    }

    /// @notice Computes the `amountIn` of stablecoins to burn to release `amountOut` of `collateral`
    function quoteBurnExactOutput(
        address collateral,
        Collateral storage collatInfo,
        uint256 amountOut
    ) internal view returns (uint256 amountIn) {
        (uint256 ratio, uint256 oracleValue) = getBurnOracle(collateral, collatInfo.oracleConfig);
        amountIn = Math.mulDiv(LibHelpers.convertDecimalTo(amountOut, collatInfo.decimals, 18), oracleValue, ratio);
        amountIn = quoteFees(collatInfo, QuoteType.BurnExactOutput, amountIn);
    }

    /// @notice Computes the `amountOut` of `collateral` to give during a burn operation of `amountIn` of stablecoins
    function quoteBurnExactInput(
        address collateral,
        Collateral storage collatInfo,
        uint256 amountIn
    ) internal view returns (uint256 amountOut) {
        (uint256 ratio, uint256 oracleValue) = getBurnOracle(collateral, collatInfo.oracleConfig);
        amountOut = quoteFees(collatInfo, QuoteType.BurnExactInput, amountIn);
        amountOut = LibHelpers.convertDecimalTo((amountOut * ratio) / oracleValue, 18, collatInfo.decimals);
    }

    /// @notice Computes the fees to apply during a mint or burn operation
    /// @dev This function leverages the mathematical computations of the appendix of the Transmuter whitepaper
    /// @dev Cost of the function is linear in the length of the `xFeeMint` or `xFeeBurn` array
    function quoteFees(
        Collateral storage collatInfo,
        QuoteType quoteType,
        uint256 amountStable
    ) internal view returns (uint256) {
        LocalVariables memory v;
        v.isMint = _isMint(quoteType);
        v.isExact = _isExact(quoteType);
        uint256 n = v.isMint ? collatInfo.xFeeMint.length : collatInfo.xFeeBurn.length;

        uint256 currentExposure;
        {
            TransmuterStorage storage ks = s.transmuterStorage();
            uint256 normalizedStablesMem = ks.normalizedStables;
            // Handling the initialisation and constant fees
            if (normalizedStablesMem == 0 || n == 1)
                return _computeFee(quoteType, amountStable, v.isMint ? collatInfo.yFeeMint[0] : collatInfo.yFeeBurn[0]);
            // Increasing precision for `currentExposure` because otherwise if there is a factor 1e9 between total
            // stablecoin supply and one specific collateral, exposure can be null
            currentExposure = uint64((collatInfo.normalizedStables * BASE_18) / normalizedStablesMem);

            uint256 normalizerMem = ks.normalizer;
            // Store the current amount of stablecoins issued from this collateral
            v.stablecoinsIssued = (uint256(collatInfo.normalizedStables) * normalizerMem) / BASE_27;
            v.otherStablecoinSupply = (normalizerMem * normalizedStablesMem) / BASE_27 - v.stablecoinsIssued;
        }

        uint256 amount;
        // Finding in which segment the current exposure to the collateral is
        uint256 i = LibHelpers.findLowerBound(
            v.isMint,
            v.isMint ? collatInfo.xFeeMint : collatInfo.xFeeBurn,
            uint64(BASE_9),
            uint64(currentExposure)
        );

        while (i < n - 1) {
            // We compute a linear by part function on the amount swapped
            // The `amountToNextBreakPoint` variable is the `b_{i+1}` value from the whitepaper
            if (v.isMint) {
                v.lowerExposure = collatInfo.xFeeMint[i];
                v.upperExposure = collatInfo.xFeeMint[i + 1];
                v.lowerFees = collatInfo.yFeeMint[i];
                v.upperFees = collatInfo.yFeeMint[i + 1];
                v.amountToNextBreakPoint =
                    (v.otherStablecoinSupply * v.upperExposure) /
                    (BASE_9 - v.upperExposure) -
                    v.stablecoinsIssued;
            } else {
                // The exposures in the burn case are decreasing
                v.lowerExposure = collatInfo.xFeeBurn[i];
                v.upperExposure = collatInfo.xFeeBurn[i + 1];
                v.lowerFees = collatInfo.yFeeBurn[i];
                v.upperFees = collatInfo.yFeeBurn[i + 1];
                // The `b_{i+1}` value in the burn case is the opposite value of the mint case
                v.amountToNextBreakPoint =
                    v.stablecoinsIssued -
                    (v.otherStablecoinSupply * v.upperExposure) /
                    (BASE_9 - v.upperExposure);
            }
            // Computing the `g_i(0)` value from the whitepaper
            int256 currentFees;
            // We can only enter the else in the first iteration of the loop as otherwise we will
            // always be at the beginning of the new segment
            if (v.lowerExposure * BASE_9 == currentExposure) currentFees = v.lowerFees;
            else if (v.lowerFees == v.upperFees) currentFees = v.lowerFees;
            else {
                // This is the opposite of the `b_i` value from the whitepaper.
                uint256 amountFromPrevBreakPoint = v.isMint
                    ? v.stablecoinsIssued - (v.otherStablecoinSupply * v.lowerExposure) / (BASE_9 - v.lowerExposure)
                    : (v.otherStablecoinSupply * v.lowerExposure) / (BASE_9 - v.lowerExposure) - v.stablecoinsIssued;

                // `slope` is in base 18
                uint256 slope = ((uint256(v.upperFees - v.lowerFees) * BASE_36) /
                    (v.amountToNextBreakPoint + amountFromPrevBreakPoint));
                // `currentFees` is the `g(0)` value from the whitepaper
                currentFees = v.lowerFees + int256((slope * amountFromPrevBreakPoint) / BASE_36);
            }
            {
                // In the mint case, when `!v.isExact`: = `b_{i+1} * (1+(g_i(0)+f_{i+1})/2)`
                uint256 amountToNextBreakPointNormalizer = v.isExact ? v.amountToNextBreakPoint : v.isMint
                    ? invertFeeMint(v.amountToNextBreakPoint, int64(v.upperFees + currentFees) / 2)
                    : applyFeeBurn(v.amountToNextBreakPoint, int64(v.upperFees + currentFees) / 2);

                if (amountToNextBreakPointNormalizer >= amountStable) {
                    int64 midFee;
                    if (v.isExact) {
                        // `(g_i(0) + g_i(M)) / 2 = g(0) + (f_{i+1} - g(0)) * M / (2 * b_{i+1})`
                        midFee = int64(
                            currentFees +
                                int256(
                                    amountStable.mulDiv(
                                        uint256((v.upperFees - currentFees)),
                                        2 * amountToNextBreakPointNormalizer,
                                        Math.Rounding.Up
                                    )
                                )
                        );
                    } else {
                        // Here instead of computing the closed form expression for `m_t` derived in the whitepaper,
                        // we are computing: `(g(0)+g_i(m_t))/2 = g(0)+(f_{i+1}-f_i)/(b_{i+1}-b_i)m_t/2

                        // ac4 is the value of `2M(f_{i+1}-f_i)/(b_{i+1}-b_i) = 2M(f_{i+1}-g(0))/b_{i+1}` used
                        // in the computation of `m_t` in both the mint and burn case
                        uint256 ac4 = BASE_9.mulDiv(
                            2 * amountStable * uint256(v.upperFees - currentFees),
                            v.amountToNextBreakPoint,
                            Math.Rounding.Up
                        );

                        if (v.isMint) {
                            // In the mint case:
                            // `m_t = (-1-g(0)+sqrt[(1+g(0))**2+2M(f_{i+1}-g(0))/b_{i+1})]/((f_{i+1}-g(0))/b_{i+1})`
                            // And so: g(0)+(f_{i+1}-f_i)/(b_{i+1}-b_i)m_t/2
                            //                      = (g(0)-1+sqrt[(1+g(0))**2+2M(f_{i+1}-g(0))/b_{i+1})])
                            midFee = int64(
                                (int256(
                                    Math.sqrt((uint256(int256(BASE_9) + currentFees)) ** 2 + ac4, Math.Rounding.Up)
                                ) +
                                    currentFees -
                                    int256(BASE_9)) / 2
                            );
                        } else {
                            // In the burn case:
                            // `m_t = (1-g(0)+sqrt[(1-g(0))**2-2M(f_{i+1}-g(0))/b_{i+1})]/((f_{i+1}-g(0))/b_{i+1})`
                            // And so: g(0)+(f_{i+1}-f_i)/(b_{i+1}-b_i)m_t/2
                            //                      = (g(0)+1-sqrt[(1-g(0))**2-2M(f_{i+1}-g(0))/b_{i+1})])

                            uint256 baseMinusCurrentSquared = (uint256(int256(BASE_9) - currentFees)) ** 2;
                            // Mathematically, this condition is always verified, but rounding errors may make this
                            // mathematical invariant break, in which case we consider that the square root is null
                            if (baseMinusCurrentSquared < ac4) midFee = int64((currentFees + int256(BASE_9)) / 2);
                            else
                                midFee = int64(
                                    int256(
                                        Math.mulDiv(
                                            uint256(
                                                currentFees +
                                                    int256(BASE_9) -
                                                    int256(Math.sqrt(baseMinusCurrentSquared - ac4, Math.Rounding.Down))
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
                    // Update for the rest of the swaps the stablecoins issued from the asset
                    v.stablecoinsIssued = v.isMint
                        ? v.stablecoinsIssued + v.amountToNextBreakPoint
                        : v.stablecoinsIssued - v.amountToNextBreakPoint;
                }
            }
        }
        // If `i == n-1`, we are in an area where fees are constant
        return
            amount +
            _computeFee(quoteType, amountStable, v.isMint ? collatInfo.yFeeMint[n - 1] : collatInfo.yFeeBurn[n - 1]);
    }

    /// @notice Applies or inverts `fees` to an `amount` based on the type of operation
    function _computeFee(QuoteType quoteType, uint256 amount, int64 fees) private pure returns (uint256) {
        return
            quoteType == QuoteType.MintExactInput ? applyFeeMint(amount, fees) : quoteType == QuoteType.MintExactOutput
                ? invertFeeMint(amount, fees)
                : quoteType == QuoteType.BurnExactInput
                ? applyFeeBurn(amount, fees)
                : invertFeeBurn(amount, fees);
    }

    /// @notice Checks whether an operation is a mint operation or not
    function _isMint(QuoteType quoteType) private pure returns (bool) {
        return quoteType == QuoteType.MintExactInput || quoteType == QuoteType.MintExactOutput;
    }

    /// @notice Checks whether a swap involves an amount of stablecoins that is known in exact in advance or not
    function _isExact(QuoteType quoteType) private pure returns (bool) {
        return quoteType == QuoteType.MintExactOutput || quoteType == QuoteType.BurnExactInput;
    }

    /// @notice Applies `fees` to an `amountIn` of assets to get an `amountOut` of stablecoins
    function applyFeeMint(uint256 amountIn, int64 fees) internal pure returns (uint256 amountOut) {
        if (fees >= 0) {
            uint256 castedFees = uint256(int256(fees));
            // Consider that if fees are above `BASE_12` this is equivalent to infinite fees
            if (castedFees >= BASE_12) revert InvalidSwap();
            amountOut = (amountIn * BASE_9) / (BASE_9 + castedFees);
        } else amountOut = (amountIn * BASE_9) / (BASE_9 - uint256(int256(-fees)));
    }

    /// @notice Gets from an `amountOut` of stablecoins and with `fees`, the `amountIn` of assets
    /// that need to be brought during a mint
    function invertFeeMint(uint256 amountOut, int64 fees) internal pure returns (uint256 amountIn) {
        if (fees >= 0) {
            uint256 castedFees = uint256(int256(fees));
            // Consider that if fees are above `BASE_12` this is equivalent to infinite fees
            if (castedFees >= BASE_12) revert InvalidSwap();
            amountIn = amountOut.mulDiv(BASE_9 + castedFees, BASE_9, Math.Rounding.Up);
        } else amountIn = amountOut.mulDiv(BASE_9 - uint256(int256(-fees)), BASE_9, Math.Rounding.Up);
    }

    /// @notice Applies `fees` to an `amountIn` of stablecoins to get an `amountOut` of assets
    function applyFeeBurn(uint256 amountIn, int64 fees) internal pure returns (uint256 amountOut) {
        if (fees >= 0) {
            uint256 castedFees = uint256(int256(fees));
            if (castedFees >= MAX_BURN_FEE) revert InvalidSwap();
            amountOut = ((BASE_9 - castedFees) * amountIn) / BASE_9;
        } else amountOut = ((BASE_9 + uint256(int256(-fees))) * amountIn) / BASE_9;
    }

    /// @notice Gets from an `amountOut` of assets and with `fees` the `amountIn` of stablecoins that need
    /// to be brought during a burn
    function invertFeeBurn(uint256 amountOut, int64 fees) internal pure returns (uint256 amountIn) {
        if (fees >= 0) {
            uint256 castedFees = uint256(int256(fees));
            if (castedFees >= MAX_BURN_FEE) revert InvalidSwap();
            amountIn = amountOut.mulDiv(BASE_9, BASE_9 - castedFees, Math.Rounding.Up);
        } else amountIn = amountOut.mulDiv(BASE_9, BASE_9 + uint256(int256(-fees)), Math.Rounding.Up);
    }

    /// @notice Gets the oracle value and the ratio with respect to the target price when it comes to
    /// burning for `collateral`
    function getBurnOracle(
        address collateral,
        bytes memory oracleConfig
    ) internal view returns (uint256 minRatio, uint256 oracleValue) {
        TransmuterStorage storage ks = s.transmuterStorage();
        minRatio = BASE_18;
        address[] memory collateralList = ks.collateralList;
        uint256 length = collateralList.length;
        for (uint256 i; i < length; ++i) {
            uint256 ratioObserved = BASE_18;
            if (collateralList[i] != collateral) {
                uint256 oracleValueTmp;
                (oracleValueTmp, ratioObserved) = LibOracle.readBurn(ks.collaterals[collateralList[i]].oracleConfig);
            } else (oracleValue, ratioObserved) = LibOracle.readBurn(oracleConfig);
            if (ratioObserved < minRatio) minRatio = ratioObserved;
        }
    }

    /// @notice Checks whether a swap from `tokenIn` to `tokenOut` is a mint or a burn, whether the
    /// collateral provided is paused or not and in case of whether the swap is not occuring too late
    /// @dev The function reverts if the `tokenIn` and `tokenOut` given do not correspond to the stablecoin
    /// and to an accepted collateral asset of the system
    function getMintBurn(
        address tokenIn,
        address tokenOut,
        uint256 deadline
    ) internal view returns (bool mint, Collateral storage collatInfo) {
        if (deadline != 0 && block.timestamp > deadline) revert TooLate();
        TransmuterStorage storage ks = s.transmuterStorage();
        address _agToken = address(ks.agToken);
        if (tokenIn == _agToken) {
            collatInfo = ks.collaterals[tokenOut];
            mint = false;
            if (collatInfo.isBurnLive == 0) revert Paused();
        } else if (tokenOut == _agToken) {
            collatInfo = ks.collaterals[tokenIn];
            mint = true;
            if (collatInfo.isMintLive == 0) revert Paused();
        } else revert InvalidTokens();
    }

    /// @notice Checks whether `tokenIn`is a valid unpaused collateral and the deadline
    function getMint(
        address tokenIn,
        uint256 deadline
    ) internal view returns (address agToken, Collateral storage collatInfo) {
        if (deadline != 0 && block.timestamp > deadline) revert TooLate();
        TransmuterStorage storage ks = s.transmuterStorage();
        agToken = address(ks.agToken);
        collatInfo = ks.collaterals[tokenIn];
        if (collatInfo.isMintLive == 0) revert Paused();
    }

    /// @notice Build a permit2 `permitTransferFrom` payload for a `tokenIn` transfer
    /// @dev The transfer should be from `msg.sender` to this contract or a manager
    function buildPermitTransferPayload(
        uint256 amount,
        uint256 approvedAmount,
        address tokenIn,
        uint256 deadline,
        bytes memory permitData,
        Collateral storage collatInfo
    ) internal view returns (bytes memory payload) {
        Permit2Details memory details;
        if (collatInfo.isManaged > 0) {
            details.to = LibManager.transferRecipient(collatInfo.managerData.config);
        } else {
            details.to = address(this);
        }
        (details.nonce, details.signature) = abi.decode(permitData, (uint256, bytes));
        payload = abi.encodeWithSelector(
            IPermit2.permitTransferFrom.selector,
            PermitTransferFrom({
                permitted: TokenPermissions({ token: tokenIn, amount: approvedAmount }),
                nonce: details.nonce,
                deadline: deadline
            }),
            SignatureTransferDetails({ to: details.to, requestedAmount: amount }),
            msg.sender,
            details.signature
        );
    }
}
