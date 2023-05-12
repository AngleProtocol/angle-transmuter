// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import { IAgToken } from "../../interfaces/IAgToken.sol";

import { LibStorage as s } from "./LibStorage.sol";
import { LibOracle } from "./LibOracle.sol";
import { LibHelper } from "./LibHelper.sol";
import { LibManager } from "./LibManager.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import "../utils/Utils.sol";
import "../Storage.sol";

/// @title LibRedeemer
/// @author Angle Labs, Inc.
library LibRedeemer {
    using SafeERC20 for IERC20;

    event NormalizerUpdated(uint256 newNormalizerValue);
    event Redeemed(
        uint256 amount,
        address[] tokens,
        uint256[] amounts,
        address[] forfeitTokens,
        address indexed from,
        address indexed to
    );

    function redeem(
        uint256 amount,
        address to,
        uint256 deadline,
        uint256[] memory minAmountOuts,
        address[] memory forfeitTokens
    ) internal returns (address[] memory tokens, uint256[] memory amounts) {
        KheopsStorage storage ks = s.kheopsStorage();
        if (block.timestamp > deadline) revert TooLate();
        uint256[] memory subCollateralsTracker;
        (tokens, amounts, subCollateralsTracker) = quoteRedemptionCurve(amount);
        updateNormalizer(amount, false);

        IAgToken(ks.agToken).burnSelf(amount, msg.sender);

        address[] memory collateralListMem = ks.collateralList;
        uint256 indexCollateral;
        for (uint256 i; i < amounts.length; ++i) {
            if (amounts[i] < minAmountOuts[i]) revert TooSmallAmountOut();
            if (Utils.checkForfeit(tokens[i], forfeitTokens) < 0) {
                ManagerStorage memory emptyManagerData;
                LibHelper.transferCollateral(
                    tokens[i],
                    to,
                    amounts[i],
                    true,
                    ks.collaterals[collateralListMem[indexCollateral]].isManaged > 0
                        ? ks.collaterals[collateralListMem[indexCollateral]].managerData
                        : emptyManagerData
                );
            }
            if (subCollateralsTracker[indexCollateral] - 1 <= i) ++indexCollateral;
        }
        emit Redeemed(amount, tokens, amounts, forfeitTokens, msg.sender, to);
    }

    ///@dev If 'normalizedStablesValue==0' it will revert but calling this function is useless in this case as there aren't
    /// any stable
    function quoteRedemptionCurve(
        uint256 amountBurnt
    )
        internal
        view
        returns (address[] memory tokens, uint256[] memory balances, uint256[] memory subCollateralsTracker)
    {
        KheopsStorage storage ks = s.kheopsStorage();
        uint64 collatRatio;
        uint256 normalizedStablesValue;
        (collatRatio, normalizedStablesValue, tokens, balances, subCollateralsTracker) = getCollateralRatio();
        int64[] memory yRedemptionCurveMem = ks.yRedemptionCurve;
        uint64 penalty;
        if (collatRatio < BASE_9) {
            uint64[] memory xRedemptionCurveMem = ks.xRedemptionCurve;
            penalty = uint64(Utils.piecewiseLinear(collatRatio, true, xRedemptionCurveMem, yRedemptionCurveMem));
        }

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
                            Utils.convertDecimalTo(balance, ks.collaterals[collateralList[i]].decimals, 18)) /
                        BASE_18;
                }
            }
        }
        reservesValue = Math.mulDiv(ks.normalizedStables, ks.normalizer, BASE_27, Math.Rounding.Up);
        if (reservesValue > 0)
            collatRatio = uint64(Math.mulDiv(totalCollateralization, BASE_9, reservesValue, Math.Rounding.Up));
        else collatRatio = type(uint64).max;
    }

    function updateNormalizer(uint256 amount, bool increase) internal returns (uint256 newNormalizerValue) {
        KheopsStorage storage ks = s.kheopsStorage();
        uint256 _normalizer = ks.normalizer;
        uint256 _normalizedStables = ks.normalizedStables;
        if (_normalizedStables == 0) newNormalizerValue = BASE_27;
        else if (increase) newNormalizerValue = _normalizer + (amount * BASE_27) / _normalizedStables;
        else newNormalizerValue = _normalizer - (amount * BASE_27) / _normalizedStables;

        if (newNormalizerValue <= BASE_18 || newNormalizerValue >= BASE_36) {
            address[] memory collateralListMem = ks.collateralList;
            uint256 collateralListLength = collateralListMem.length;
            for (uint256 i; i < collateralListLength; ++i) {
                ks.collaterals[collateralListMem[i]].normalizedStables = uint224(
                    (ks.collaterals[collateralListMem[i]].normalizedStables * newNormalizerValue) / BASE_27
                );
            }
            ks.normalizedStables = uint128((_normalizedStables * newNormalizerValue) / BASE_27);
            newNormalizerValue = BASE_27;
        }
        ks.normalizer = uint128(newNormalizerValue);
        emit NormalizerUpdated(newNormalizerValue);
    }
}
