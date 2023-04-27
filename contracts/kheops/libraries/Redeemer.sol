// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import { Storage as s } from "./Storage.sol";
import "./Oracle.sol";
import "./Swapper.sol";
import "../utils/Utils.sol";
import "../Storage.sol";

import "../../interfaces/IAgToken.sol";
import "../../interfaces/IModule.sol";
import "../../interfaces/IManager.sol";

library Redeemer {
    using SafeERC20 for IERC20;

    function redeem(
        uint256 amount,
        address to,
        uint deadline,
        uint256[] memory minAmountOuts,
        address[] memory forfeitTokens
    ) internal returns (address[] memory tokens, uint256[] memory amounts) {
        KheopsStorage storage ks = s.kheopsStorage();
        if (block.timestamp < deadline) revert TooLate();
        amounts = quoteRedemptionCurve(amount);
        Swapper.updateAccumulator(amount, false);

        // Settlement - burn the stable and send the redeemable tokens
        IAgToken(ks.agToken).burnSelf(amount, msg.sender);

        address[] memory _collateralList = ks.collateralList;
        address[] memory depositModuleList = ks.redeemableModuleList;
        uint256 collateralListLength = _collateralList.length;
        uint256 amountsLength = amounts.length;
        tokens = new address[](amountsLength);
        uint256 startTokenForfeit;
        for (uint256 i; i < amountsLength; ++i) {
            if (amounts[i] < minAmountOuts[i]) revert TooSmallAmountOut();
            if (i < collateralListLength) tokens[i] = _collateralList[i];
            else tokens[i] = ks.modules[depositModuleList[i - collateralListLength]].token;
            int256 indexFound = Utils.checkForfeit(tokens[i], startTokenForfeit, forfeitTokens);
            if (indexFound < 0) {
                if (i < collateralListLength)
                    Utils.transferCollateral(
                        _collateralList[i],
                        ks.collaterals[_collateralList[i]].manager,
                        to,
                        amounts[i]
                    );
                else IModule(depositModuleList[i - collateralListLength]).transfer(to, amounts[i]);
            } else {
                // we force the user to give addresses in the order of collateralList and redeemableModuleList
                // to save on going through array too many times/
                // Not sure empirically worth it, it depends on many tokens will be supported + how many will be
                // open to forfeit
                startTokenForfeit = uint256(indexFound);
                amounts[i] = 0;
            }
        }
    }

    function quoteRedemptionCurve(uint256 amountBurnt) internal view returns (uint256[] memory balances) {
        KheopsStorage storage ks = s.kheopsStorage();
        uint64 collatRatio;
        uint256 normalizedStablesValue;
        (collatRatio, normalizedStablesValue, balances) = getCollateralRatio();
        uint64[] memory xRedemptionCurveMem = ks.xRedemptionCurve;
        uint64[] memory yRedemptionCurveMem = ks.yRedemptionCurve;
        uint64 penalty;
        if (collatRatio >= BASE_9) {
            penalty = (uint64(yRedemptionCurveMem[yRedemptionCurveMem.length - 1]) * uint64(BASE_9)) / collatRatio;
        } else {
            penalty = uint64(Utils.piecewiseMean(collatRatio, collatRatio, xRedemptionCurveMem, yRedemptionCurveMem));
        }
        uint256 balancesLength = balances.length;
        for (uint256 i; i < balancesLength; i++) {
            balances[i] = (amountBurnt * balances[i] * penalty) / (normalizedStablesValue * BASE_9);
        }
    }

    function getCollateralRatio()
        internal
        view
        returns (uint64 collatRatio, uint256 reservesValue, uint256[] memory balances)
    {
        KheopsStorage storage ks = s.kheopsStorage();

        uint256 totalCollateralization;
        address[] memory collateralList = ks.collateralList;
        uint256 collateralListLength = collateralList.length;
        address[] memory depositModuleList = ks.redeemableModuleList;
        uint256 depositModuleLength = depositModuleList.length;
        balances = new uint256[](collateralListLength + depositModuleLength);

        for (uint256 i; i < collateralListLength; ++i) {
            uint256 balance;
            if (ks.collaterals[list[i]].hasManager > 0)
                balance = IManager(ks.collaterals[list[i]].manager).getUnderlyingBalance();
            else balance = IERC20(list[i]).balanceOf(address(this));
            balances[i] = balance;
            bytes memory oracle = ks.collaterals[collateralList[i]].oracle;
            uint256 oracleValue = Oracle.readRedemption(oracle);
            totalCollateralization +=
                (oracleValue * Utils.convertDecimalTo(balance, ks.collaterals[collateralList[i]].decimals, 18)) /
                BASE_18;
        }
        for (uint256 i; i < depositModuleLength; ++i) {
            (uint256 balance, uint256 value) = IModule(depositModuleList[i]).getBalanceAndValue();
            balances[i + collateralListLength] = balance;
            totalCollateralization += value;
        }
        reservesValue = (ks.normalizedStables * ks.normalizer) / BASE_27;
        if (reservesValue > 0) collatRatio = uint64((totalCollateralization * BASE_9) / reservesValue);
        else collatRatio = type(uint64).max;
    }
}
