// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import { SafeCast } from "oz/utils/math/SafeCast.sol";
import { IERC20 } from "oz/token/ERC20/IERC20.sol";
import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";
import { Math } from "oz/utils/math/Math.sol";

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
    using SafeCast for uint256;

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
        // Updating the normalizer enables to simultaneously and proportionally reduce the amount
        // of stablecoins issued from each collateral without having to loop through each of them
        updateNormalizer(amount, false);

        IAgToken(ks.agToken).burnSelf(amount, msg.sender);

        uint256 proportion = quoteProportion(amount);

        address[] memory collateralListMem = ks.collateralList;
        uint256 collateralListLength = collateralListMem.length;
        tokens = new address[](5 * collateralListLength);
        amounts = new uint256[](5 * collateralListLength);
        uint256 index = 0;
        for (uint256 i; i < collateralListLength; ++i) {
            Collateral storage collateral = ks.collaterals[collateralListMem[i]];
            if (collateral.isManaged > 0) {
                (address[] memory managerTokens, uint256[] memory managerBalances) = LibManager.redeem(
                    to,
                    proportion,
                    forfeitTokens,
                    collateral.managerData.config
                );
                uint256 managerTokenLength = managerTokens.length;
                for (uint256 j; j < managerTokenLength; ++j) {
                    tokens[index] = managerTokens[j];
                    amounts[index] = managerBalances[j];
                    ++index;
                }
            } else {
                uint256 balance = IERC20(collateralListMem[i]).balanceOf(address(this));
                tokens[index] = collateralListMem[i];
                amounts[index] = (balance * proportion) / BASE_18;
                IERC20(collateralListMem[i]).safeTransfer(to, amounts[index]);
                ++index;
            }
        }
        ++index; // index is now the length of the `tokens` and `amounts` arrays
        if (index != tokens.length) revert InvalidParams();
        for (uint256 i; i < index; ++i) {
            if (amounts[i] < minAmountOuts[i]) revert TooSmallAmountOut();
        }
        assembly {
            mstore(tokens, index)
            mstore(amounts, index)
        }

        emit Redeemed(amount, tokens, amounts, forfeitTokens, msg.sender, to);
    }

    /// @dev This function reverts if `stablecoinsIssued==0`, which is expected behavior as there is nothing to redeem
    /// anyway in this case, or if the `amountBurnt` is greater than `stablecoinsIssued`
    function quoteProportion(uint256 amountBurnt) internal view returns (uint256 proportion) {
        TransmuterStorage storage ks = s.transmuterStorage();
        uint64 collatRatio;
        uint256 stablecoinsIssued;
        (collatRatio, stablecoinsIssued) = getCollateralRatio();
        if (amountBurnt > stablecoinsIssued) revert TooBigAmountIn();
        int64[] memory yRedemptionCurveMem = ks.yRedemptionCurve;
        uint64 penaltyFactor;
        // If the protocol is under-collateralized, a penalty factor is applied to the returned amount of each asset
        if (collatRatio < BASE_9) {
            uint64[] memory xRedemptionCurveMem = ks.xRedemptionCurve;
            penaltyFactor = uint64(
                LibHelpers.piecewiseLinear(collatRatio, true, xRedemptionCurveMem, yRedemptionCurveMem)
            );
        }

        uint256 proportion = collatRatio >= BASE_9
            ? (amountBurnt * BASE_18 * (uint64(yRedemptionCurveMem[yRedemptionCurveMem.length - 1]))) /
                (stablecoinsIssued * collatRatio)
            : (amountBurnt * BASE_18 * penaltyFactor) / (stablecoinsIssued * BASE_9);
    }

    /// @notice Internal version of the `getCollateralRatio` function with additional return values like `tokens` that
    /// is the list of tokens supported by the system, or `balances` which is the amount of each token in `tokens`
    /// controlled by the protocol
    /// @dev In case some collaterals support external strategies (`isManaged>0`), this list may be bigger
    /// than the `collateralList`
    /// @dev `subCollateralsTracker` is an array which gives for each collateral asset in the collateral list an
    /// accumulator helping to recompute the amount of sub-collateral for each collateral. If the array is:
    /// [1,4,5], this means that the collateral with index 1 in the `collateralsList` has 4-1=3 sub-collaterals.
    function getCollateralRatio() internal view returns (uint64 collatRatio, uint256 stablecoinsIssued) {
        TransmuterStorage storage ks = s.transmuterStorage();
        uint256 totalCollateralization;
        address[] memory collateralList = ks.collateralList;
        uint256 collateralListLength = collateralList.length;

        uint256 countCollat;
        for (uint256 i; i < collateralListLength; ++i) {
            Collateral storage collateral = ks.collaterals[collateralList[i]];
            uint256 collateralBalance;
            if (collateral.isManaged > 0) {
                collateralBalance = LibManager.totalAssets(collateral.managerData.config);
            } else {
                collateralBalance = IERC20(collateralList[i]).balanceOf(address(this)); // TODO document reentrancy risk here
            }
            uint256 oracleValue = LibOracle.readRedemption(collateral.oracleConfig);
            totalCollateralization +=
                (oracleValue * LibHelpers.convertDecimalTo(collateralBalance, collateral.decimals, 18)) /
                BASE_18;
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
            // For each asset, we store the actual amount of stablecoins issued based on the `newNormalizerValue`
            // (and not a normalized value)
            // We ensure to preserve the invariant `sum(collateralNewNormalizedStables) = normalizedStables`
            uint128 newNormalizedStables = 0;
            for (uint256 i; i < collateralListLength; ++i) {
                uint128 newCollateralNormalizedStable = ((uint256(
                    ks.collaterals[collateralListMem[i]].normalizedStables
                ) * newNormalizerValue) / BASE_27).toUint128();
                newNormalizedStables += newCollateralNormalizedStable;
                ks.collaterals[collateralListMem[i]].normalizedStables = uint216(newCollateralNormalizedStable);
            }
            ks.normalizedStables = newNormalizedStables;
            newNormalizerValue = BASE_27;
        }
        ks.normalizer = newNormalizerValue.toUint128();
        emit NormalizerUpdated(newNormalizerValue);
    }
}
