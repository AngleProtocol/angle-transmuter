// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import { LibStorage as s } from "./LibStorage.sol";
import { LibOracle } from "./LibOracle.sol";
import { LibHelper } from "./LibHelper.sol";
import { LibManager } from "./LibManager.sol";
import "../utils/Utils.sol";
import "../Storage.sol";

import { IAgToken } from "../../interfaces/IAgToken.sol";

/// @title LibRedeemer
/// @author Angle Labs, Inc.
library LibRedeemer {
    using SafeERC20 for IERC20;

    function redeem(
        uint256 amount,
        address to,
        uint deadline,
        uint256[] memory minAmountOuts,
        address[] memory forfeitTokens
    ) internal returns (address[] memory tokens, uint256[] memory amounts) {
        KheopsStorage storage ks = s.kheopsStorage();
        if (block.timestamp > deadline) revert TooLate();
        uint256[] memory nbrSubCollaterals;
        (tokens, amounts, nbrSubCollaterals) = quoteRedemptionCurve(amount);
        updateNormalizer(amount, false);

        // Settlement - burn the stable and send the redeemable tokens
        IAgToken(ks.agToken).burnSelf(amount, msg.sender);

        address[] memory collateralListMem = ks.collateralList;
        uint256 indexCollateral;
        for (uint256 i; i < amounts.length; ++i) {
            console.log("indexCollateral ", indexCollateral);
            if (amounts[i] < minAmountOuts[i]) revert TooSmallAmountOut();

            int256 indexFound = Utils.checkForfeit(tokens[i], forfeitTokens);
            if (indexFound < 0) {
                if (i < collateralListMem.length)
                    LibHelper.transferCollateral(
                        collateralListMem[indexCollateral],
                        (ks.collaterals[collateralListMem[indexCollateral]].hasManager > 0) ? tokens[i] : address(0),
                        to,
                        amounts[i],
                        true
                    );
            }
            if (nbrSubCollaterals[indexCollateral] - 1 >= i) ++indexCollateral;
        }
    }

    ///@dev If 'normalizedStablesValue==0' it will revert but calling this function is useless in this case as there aren't
    /// any stable
    function quoteRedemptionCurve(
        uint256 amountBurnt
    ) internal view returns (address[] memory tokens, uint256[] memory balances, uint256[] memory nbrSubCollaterals) {
        KheopsStorage storage ks = s.kheopsStorage();
        uint64 collatRatio;
        uint256 normalizedStablesValue;
        (collatRatio, normalizedStablesValue, tokens, balances, nbrSubCollaterals) = getCollateralRatio();
        uint64[] memory xRedemptionCurveMem = ks.xRedemptionCurve;
        int64[] memory yRedemptionCurveMem = ks.yRedemptionCurve;
        uint64 penalty;
        if (collatRatio < BASE_9)
            penalty = uint64(Utils.piecewiseLinear(collatRatio, true, xRedemptionCurveMem, yRedemptionCurveMem));

        uint256 balancesLength = balances.length;
        for (uint256 i; i < balancesLength; i++) {
            balances[i] = collatRatio >= BASE_9
                ? (amountBurnt * balances[i] * (uint64(yRedemptionCurveMem[yRedemptionCurveMem.length - 1]))) /
                    (normalizedStablesValue * collatRatio)
                : (amountBurnt * balances[i] * penalty) / (normalizedStablesValue * BASE_9);
        }
    }

    function getCollateralRatio()
        internal
        view
        returns (
            uint64 collatRatio,
            uint256 reservesValue,
            address[] memory tokens,
            uint256[] memory balances,
            uint256[] memory nbrSubCollaterals
        )
    {
        KheopsStorage storage ks = s.kheopsStorage();

        uint256 totalCollateralization;
        address[] memory collateralList = ks.collateralList;
        uint256 collateralListLength = collateralList.length;
        uint256 subCollateralsLength;
        nbrSubCollaterals = new uint256[](collateralListLength);
        for (uint256 i; i < collateralListLength; ++i) {
            if (ks.collaterals[collateralList[i]].hasManager == 0) ++subCollateralsLength;
            else subCollateralsLength += ks.collaterals[collateralList[i]].managerStorage.subCollaterals.length;
            nbrSubCollaterals[i] = subCollateralsLength;
        }
        balances = new uint256[](subCollateralsLength);
        tokens = new address[](subCollateralsLength);

        for (uint256 i; i < collateralListLength; ++i) {
            if (ks.collaterals[collateralList[i]].hasManager > 0) {
                (uint256[] memory subCollateralsBalances, uint256 totalValue) = LibManager.getUnderlyingBalances(
                    ks.collaterals[collateralList[i]].managerStorage
                );
                uint256 curNbrSubCollat = subCollateralsBalances.length;
                for (uint256 k; k < curNbrSubCollat; ++k) {
                    tokens[i + k] = address(ks.collaterals[collateralList[i]].managerStorage.subCollaterals[k]);
                    balances[i + k] = subCollateralsBalances[k];
                }
                totalCollateralization += totalValue;
            } else {
                uint256 balance = IERC20(collateralList[i]).balanceOf(address(this));
                tokens[i] = collateralList[i];
                balances[i] = balance;
                bytes memory oracleConfig = ks.collaterals[collateralList[i]].oracleConfig;
                uint256 oracleValue = LibOracle.readRedemption(oracleConfig);
                totalCollateralization +=
                    (oracleValue * Utils.convertDecimalTo(balance, ks.collaterals[collateralList[i]].decimals, 18)) /
                    BASE_18;
            }
        }
        reservesValue = Math.mulDiv(ks.normalizedStables, ks.normalizer, BASE_27, Math.Rounding.Up);
        if (reservesValue > 0)
            collatRatio = uint64(Math.mulDiv(totalCollateralization, BASE_9, reservesValue, Math.Rounding.Up));
        else collatRatio = type(uint64).max;
    }

    function updateNormalizer(uint256 amount, bool increase) internal returns (uint256 newAccumulatorValue) {
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
                uint256 collateralListLength = _collateralList.length;
                for (uint256 i; i < collateralListLength; ++i) {
                    ks.collaterals[_collateralList[i]].normalizedStables = 0;
                }
                ks.normalizedStables = 0;
                newAccumulatorValue = BASE_27;
            }
        }
        ks.normalizer = newAccumulatorValue;
    }
}
