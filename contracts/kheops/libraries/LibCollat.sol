// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.12;

import "oz/token/ERC20/IERC20.sol";
import "oz/token/ERC20/utils/SafeERC20.sol";
import "oz/utils/math/Math.sol";

import { IAgToken } from "interfaces/IAgToken.sol";

import { LibHelpers } from "./LibHelpers.sol";
import { LibManager } from "./LibManager.sol";
import { LibOracle } from "./LibOracle.sol";
import { LibStorage as s } from "./LibStorage.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import "../Storage.sol";

/// @title LibRedeemer
/// @author Angle Labs, Inc.
library LibCollat {
    using SafeERC20 for IERC20;

    function libgetCollateralRatio()
        internal
        view
        returns (
            uint64 collatRatio,
            uint256 reservesValue,
            address[] memory tokens,
            uint256[] memory balances,
            uint256[] memory subCollateralsTracker
        )
    {
        KheopsStorage storage ks = s.kheopsStorage();
        uint256 totalCollateralization;
        address[] memory collateralList = ks.collateralList;
        uint256 collateralListLength = collateralList.length;
        uint256 subCollateralsAmount;
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
                if (ks.collaterals[collateralList[i]].isManaged > 0) {
                    (uint256[] memory subCollateralsBalances, uint256 totalValue) = LibManager.getUnderlyingBalances(
                        ks.collaterals[collateralList[i]].managerData
                    );
                    uint256 curNbrSubCollat = subCollateralsBalances.length;
                    for (uint256 k; k < curNbrSubCollat; ++k) {
                        tokens[countCollat + k] = address(
                            ks.collaterals[collateralList[i]].managerData.subCollaterals[k]
                        );
                        balances[countCollat + k] = subCollateralsBalances[k];
                    }
                    countCollat += curNbrSubCollat;
                    totalCollateralization += totalValue;
                } else {
                    uint256 balance = IERC20(collateralList[i]).balanceOf(address(this));
                    tokens[countCollat] = collateralList[i];
                    balances[countCollat++] = balance;
                    uint256 oracleValue = LibOracle.readRedemption(ks.collaterals[collateralList[i]].oracleConfig);
                    totalCollateralization +=
                        (oracleValue *
                            LibHelpers.convertDecimalTo(balance, ks.collaterals[collateralList[i]].decimals, 18)) /
                        BASE_18;
                }
            }
        }
        reservesValue = Math.mulDiv(ks.normalizedStables, ks.normalizer, BASE_27, Math.Rounding.Up);
        if (reservesValue > 0)
            collatRatio = uint64(Math.mulDiv(totalCollateralization, BASE_9, reservesValue, Math.Rounding.Up));
        else collatRatio = type(uint64).max;
    }
}
