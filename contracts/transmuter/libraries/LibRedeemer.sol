// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "oz/token/ERC20/IERC20.sol";
import "oz/token/ERC20/utils/SafeERC20.sol";
import "oz/utils/math/Math.sol";

import { IAgToken } from "interfaces/IAgToken.sol";

import { LibHelpers } from "./LibHelpers.sol";
import { LibManager } from "./LibManager.sol";
import { LibOracle } from "./LibOracle.sol";
import { LibStorage as s } from "./LibStorage.sol";
import { LibWhitelist } from "./LibWhitelist.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import "../Storage.sol";

/// @title LibRedeemer
/// @author Angle Labs, Inc.
library LibRedeemer {
    using SafeERC20 for IERC20;
    using Math for uint256;

    event Redeemed(
        uint256 amount,
        address[] tokens,
        uint256[] amounts,
        address[] forfeitTokens,
        address indexed from,
        address indexed to
    );
    event NormalizerUpdated(uint256 newNormalizerValue);

    /// @notice Internal function of the `redeem` function in the `Redeemer` contract
    function redeem(
        uint256 amount,
        address to,
        uint256 deadline,
        uint256[] memory minAmountOuts,
        address[] memory forfeitTokens
    ) internal returns (address[] memory tokens, uint256[] memory amounts) {
        TransmuterStorage storage ks = s.transmuterStorage();
        if (ks.isRedemptionLive == 0) revert Paused();
        if (block.timestamp > deadline) revert TooLate();
        uint256[] memory subCollateralsTracker;
        (tokens, amounts, subCollateralsTracker) = quoteRedemptionCurve(amount);
        // Updating the normalizer enables to simultaneously and proportionally reduce the amount
        // of stablecoins issued from each collateral without having to loop through each of them
        updateNormalizer(amount, false);

        IAgToken(ks.agToken).burnSelf(amount, msg.sender);

        address[] memory collateralListMem = ks.collateralList;
        uint256 indexCollateral;
        for (uint256 i; i < amounts.length; ++i) {
            if (amounts[i] < minAmountOuts[i]) revert TooSmallAmountOut();
            // If a token is in the `forfeitTokens` list, then it is not sent as part of the redemption process
            if (amounts[i] > 0 && LibHelpers.checkList(tokens[i], forfeitTokens) < 0) {
                Collateral storage collatInfo = ks.collaterals[collateralListMem[indexCollateral]];
                if (collatInfo.onlyWhitelisted > 0 && !LibWhitelist.checkWhitelist(collatInfo.whitelistData, to))
                    revert NotWhitelisted();
                if (collatInfo.isManaged > 0) {
                    LibManager.transferTo(tokens[i], to, amounts[i], collatInfo.managerData);
                } else IERC20(tokens[i]).safeTransfer(to, amounts[i]);
            }
            if (subCollateralsTracker[indexCollateral] - 1 <= i) ++indexCollateral;
        }
        emit Redeemed(amount, tokens, amounts, forfeitTokens, msg.sender, to);
    }

    /// @dev This function reverts if `stablecoinsIssued==0`, which is expected behavior as there is nothing to redeem
    /// anyway in this case
    function quoteRedemptionCurve(
        uint256 amountBurnt
    )
        internal
        view
        returns (address[] memory tokens, uint256[] memory balances, uint256[] memory subCollateralsTracker)
    {
        TransmuterStorage storage ks = s.transmuterStorage();
        uint64 collatRatio;
        uint256 stablecoinsIssued;
        (collatRatio, stablecoinsIssued, tokens, balances, subCollateralsTracker) = getCollateralRatio();
        int64[] memory yRedemptionCurveMem = ks.yRedemptionCurve;
        uint64 penaltyFactor;
        // If the protocol is under-collateralized, a penalty factor is applied to the returned amount of each asset
        if (collatRatio < BASE_9) {
            uint64[] memory xRedemptionCurveMem = ks.xRedemptionCurve;
            penaltyFactor = uint64(
                LibHelpers.piecewiseLinear(collatRatio, true, xRedemptionCurveMem, yRedemptionCurveMem)
            );
        }

        uint256 balancesLength = balances.length;
        for (uint256 i; i < balancesLength; ++i) {
            // The amount given for each token in reserves does not depend on the price of the tokens in reserve:
            // it is a proportion of the balance for each token computed as the ratio between the stablecoins
            // burnt relative to the amount of stablecoins issued.
            // If the protocol is over-collateralized, the amount of each token given is inversely proportional
            // to the collateral ratio.
            balances[i] = collatRatio >= BASE_9
                ? (amountBurnt * balances[i] * (uint64(yRedemptionCurveMem[yRedemptionCurveMem.length - 1]))) /
                    (stablecoinsIssued * collatRatio)
                : (amountBurnt * balances[i] * penaltyFactor) / (stablecoinsIssued * BASE_9);
        }
    }

    /// @notice Internal version of the `getCollateralRatio` function with additional return values like `tokens` that
    /// is the list of tokens supported by the system, or `balances` which is the amount of each token in `tokens`
    /// controlled by the protocol
    /// @dev In case some collaterals support external strategies (`isManaged>0`), this list may be bigger
    /// than the `collateralList`
    /// @dev `subCollateralsTracker` is an array which gives for each collateral asset in the collateral list an
    /// accumulator helping to recompute the amount of sub-collateral for each collateral. If the array is:
    /// [1,4,5], this means that the collateral with index 1 in the `collateralsList` has 4-1=3 sub-collaterals.
    function getCollateralRatio()
        internal
        view
        returns (
            uint64 collatRatio,
            uint256 stablecoinsIssued,
            address[] memory tokens,
            uint256[] memory balances,
            uint256[] memory subCollateralsTracker
        )
    {
        TransmuterStorage storage ks = s.transmuterStorage();
        uint256 totalCollateralization;
        address[] memory collateralList = ks.collateralList;
        uint256 collateralListLength = collateralList.length;
        uint256 subCollateralsAmount;
        // Building the `subCollateralsTracker` array which is useful when later sending the tokens as part of the
        // redemption
        subCollateralsTracker = new uint256[](collateralListLength);
        for (uint256 i; i < collateralListLength; ++i) {
            if (ks.collaterals[collateralList[i]].isManaged == 0) ++subCollateralsAmount;
            else subCollateralsAmount += ks.collaterals[collateralList[i]].managerData.subCollaterals.length;
            subCollateralsTracker[i] = subCollateralsAmount;
        }
        balances = new uint256[](subCollateralsAmount);
        tokens = new address[](subCollateralsAmount);

        {
            uint256 countCollat;
            for (uint256 i; i < collateralListLength; ++i) {
                Collateral memory collateral = ks.collaterals[collateralList[i]];
                uint256 collateralBalance;
                if (collateral.isManaged > 0) {
                    // If a collateral is managed, the balances of the sub-collaterals cannot be directly obtained by
                    // calling `balanceOf` of the sub-collaterals.
                    // Managed assets must support ways to value their sub-collaterals in a non manipulable way
                    (uint256[] memory subCollateralsBalances, uint256 subCollateralsValue) = LibManager
                        .getUnderlyingBalances(collateral.managerData);
                    // `subCollateralsBalances` length is not cached here to avoid stack too deep
                    for (uint256 k; k < subCollateralsBalances.length; ++k) {
                        tokens[countCollat + k] = address(collateral.managerData.subCollaterals[k]);
                        balances[countCollat + k] = subCollateralsBalances[k];
                    }
                    collateralBalance = subCollateralsBalances[0];
                    countCollat += subCollateralsBalances.length;
                    totalCollateralization += subCollateralsValue;
                } else {
                    collateralBalance = IERC20(collateralList[i]).balanceOf(address(this));
                    tokens[countCollat] = collateralList[i];
                    balances[countCollat++] = collateralBalance;
                }
                uint256 oracleValue = LibOracle.readRedemption(collateral.oracleConfig);
                totalCollateralization +=
                    (oracleValue * LibHelpers.convertDecimalTo(collateralBalance, collateral.decimals, 18)) /
                    BASE_18;
            }
        }
        // The `stablecoinsIssued` value need to be rounded up because it is then use to as a divizer when computing
        // the amount of stablecoins issued
        stablecoinsIssued = uint256(ks.normalizedStables).mulDiv(ks.normalizer, BASE_27, Math.Rounding.Up);
        if (stablecoinsIssued > 0)
            collatRatio = uint64(totalCollateralization.mulDiv(BASE_9, stablecoinsIssued, Math.Rounding.Up));
        else collatRatio = type(uint64).max;
    }

    /// @notice Updates the `normalizer` variable used to track stablecoins issued from each asset and globally
    function updateNormalizer(uint256 amount, bool increase) internal returns (uint256 newNormalizerValue) {
        TransmuterStorage storage ks = s.transmuterStorage();
        uint256 _normalizer = ks.normalizer;
        uint256 _normalizedStables = ks.normalizedStables;
        // In case of an increase, the update formula used is the simplified version of the formula below:
        /*
            _normalizer * (BASE_27 + BASE_27 * amount / stablecoinsIssued) / BASE_27
             = _normalizer + (_normalizer * BASE_27 * amount * (BASE_27 / (_normalizedStables * normalizer))) / BASE_27
             = _normalizer + BASE_27 * amount / _normalizedStables
        */
        if (increase) {
            newNormalizerValue = _normalizer + (amount * BASE_27) / _normalizedStables;
        } else {
            newNormalizerValue = _normalizer - (amount * BASE_27) / _normalizedStables;
        }
        // If the `normalizer` gets too small or too big, it must be renormalized to later avoid the propagation of
        // rounding errors, as well as overflows. In this case, the function has to iterate through all the
        // supported collateral assets
        if (newNormalizerValue <= BASE_18 || newNormalizerValue >= BASE_36) {
            address[] memory collateralListMem = ks.collateralList;
            uint256 collateralListLength = collateralListMem.length;
            // For each asset, we store the actual amount of stablecoins issued based on the newNormalizerValue
            // (and not a normalized value)
            // To preserve the invariant sum(collateralNewNormalizedStables) = normalizedStables
            uint256 newNormalizedStables = 0;
            for (uint256 i; i < collateralListLength; ++i) {
                uint216 newCollateralNormalizedStable = uint216(
                    (ks.collaterals[collateralListMem[i]].normalizedStables * newNormalizerValue) / BASE_27
                );
                newNormalizedStables += newCollateralNormalizedStable;
                ks.collaterals[collateralListMem[i]].normalizedStables = newCollateralNormalizedStable;
            }
            ks.normalizedStables = uint128(newNormalizedStables); // TODO Safe cast
            newNormalizerValue = BASE_27;
        }
        ks.normalizer = uint128(newNormalizerValue);
        emit NormalizerUpdated(newNormalizerValue);
    }
}
