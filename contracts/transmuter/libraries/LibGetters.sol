// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import { IERC20 } from "oz/token/ERC20/IERC20.sol";
import { Math } from "oz/utils/math/Math.sol";

import { LibHelpers } from "./LibHelpers.sol";
import { LibManager } from "./LibManager.sol";
import { LibOracle } from "./LibOracle.sol";
import { LibStorage as s } from "./LibStorage.sol";

import "../../utils/Constants.sol";
import "../Storage.sol";

/// @title LibGetters
/// @author Angle Labs, Inc.
library LibGetters {
    using Math for uint256;

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
        TransmuterStorage storage ts = s.transmuterStorage();
        uint256 totalCollateralization;
        address[] memory collateralList = ts.collateralList;
        uint256 collateralListLength = collateralList.length;
        uint256 subCollateralsAmount;
        // Building the `subCollateralsTracker` array which is useful when later sending the tokens as part of the
        // redemption
        subCollateralsTracker = new uint256[](collateralListLength);
        for (uint256 i; i < collateralListLength; ++i) {
            if (ts.collaterals[collateralList[i]].isManaged == 0) ++subCollateralsAmount;
            else
                subCollateralsAmount =
                    subCollateralsAmount +
                    ts.collaterals[collateralList[i]].managerData.subCollaterals.length;
            subCollateralsTracker[i] = subCollateralsAmount;
        }
        balances = new uint256[](subCollateralsAmount);
        tokens = new address[](subCollateralsAmount);

        {
            uint256 countCollat;
            for (uint256 i; i < collateralListLength; ++i) {
                Collateral storage collateral = ts.collaterals[collateralList[i]];
                uint256 collateralBalance; // Will be either the balance or the value of assets managed
                if (collateral.isManaged > 0) {
                    // If a collateral is managed, the balances of the sub-collaterals cannot be directly obtained by
                    // calling `balanceOf` of the sub-collaterals
                    uint256[] memory subCollateralsBalances;
                    (subCollateralsBalances, collateralBalance) = LibManager.totalAssets(collateral.managerData.config);
                    uint256 numSubCollats = subCollateralsBalances.length;
                    for (uint256 k; k < numSubCollats; ++k) {
                        tokens[countCollat + k] = address(collateral.managerData.subCollaterals[k]);
                        balances[countCollat + k] = subCollateralsBalances[k];
                    }
                    countCollat = countCollat + numSubCollats;
                } else {
                    collateralBalance = IERC20(collateralList[i]).balanceOf(address(this));
                    tokens[countCollat] = collateralList[i];
                    balances[countCollat++] = collateralBalance;
                }
                uint256 oracleValue = LibOracle.readRedemption(collateral.oracleConfig);
                totalCollateralization =
                    totalCollateralization +
                    (oracleValue * LibHelpers.convertDecimalTo(collateralBalance, collateral.decimals, 18)) /
                    BASE_18;
            }
        }
        // The `stablecoinsIssued` value need to be rounded up because it is then used as a divizer when computing
        // the `collatRatio`
        stablecoinsIssued = uint256(ts.normalizedStables).mulDiv(ts.normalizer, BASE_27, Math.Rounding.Up);
        if (stablecoinsIssued > 0)
            collatRatio = uint64(totalCollateralization.mulDiv(BASE_9, stablecoinsIssued, Math.Rounding.Up));
        else collatRatio = type(uint64).max;
    }
}
