// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import { Storage as s } from "./Storage.sol";
import "./OracleLib.sol";
import "./SwapperLib.sol";
import "../utils/Utils.sol";
import "../Structs.sol";

import "../../interfaces/IAgToken.sol";
import "../../interfaces/IModule.sol";
import "../../interfaces/IManager.sol";

library RedeemerLib {
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
        SwapperLib.updateAccumulator(amount, false);

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
        uint256 reservesValue;
        (collatRatio, reservesValue, balances) = getCollateralRatio();
        uint64[] memory _xRedemptionCurve = ks.xRedemptionCurve;
        int64[] memory _yRedemptionCurve = ks.yRedemptionCurve;
        uint64 penalty;
        if (collatRatio >= BASE_9) {
            // TODO check conversions whether it works well
            // it works fine as long as _yRedemptionCurve[_yRedemptionCurve.length - 1]>=0
            penalty = (uint64(_yRedemptionCurve[_yRedemptionCurve.length - 1]) * uint64(BASE_9)) / collatRatio;
        } else {
            penalty = uint64(Utils.piecewiseMean(collatRatio, collatRatio, _xRedemptionCurve, _yRedemptionCurve));
        }
        uint256 balancesLength = balances.length;
        for (uint256 i; i < balancesLength; ++i) {
            balances[i] = (amountBurnt * balances[i] * penalty) / (reservesValue * BASE_9);
        }
    }

    function getCollateralRatio()
        internal
        view
        returns (uint64 collatRatio, uint256 reservesValue, uint256[] memory balances)
    {
        KheopsStorage storage ks = s.kheopsStorage();

        uint256 totalCollateralization;
        // TODO check whether an oracleList could be smart -> with just list of addresses or stuff
        address[] memory list = ks.collateralList;
        uint256 listLength = list.length;
        address[] memory depositModuleList = ks.redeemableModuleList;
        uint256 depositModuleLength = depositModuleList.length;
        balances = new uint256[](listLength + depositModuleLength);

        for (uint256 i; i < listLength; ++i) {
            uint256 balance;
            address manager = ks.collaterals[list[i]].manager;
            if (manager != address(0)) balance = IManager(manager).getUnderlyingBalance();
            else balance = IERC20(list[i]).balanceOf(address(this));
            balances[i] = balance;
            bytes memory oracle = ks.collaterals[list[i]].oracle;
            uint256 oracleValue = BASE_18;
            // Using an underestimated oracle value for the collateral ratio
            if (keccak256(oracle) != keccak256("0x")) oracleValue = OracleLib.readMint(oracle);
            totalCollateralization +=
                oracleValue *
                Utils.convertDecimalTo(balance, ks.collaterals[list[i]].decimals, 18);
        }
        for (uint256 i; i < depositModuleLength; ++i) {
            (uint256 balance, uint256 value) = IModule(depositModuleList[i]).getBalanceAndValue();
            balances[i + listLength] = balance;
            totalCollateralization += value;
        }
        reservesValue = (ks.reserves * ks.accumulator) / BASE_27;
        if (reservesValue > 0) collatRatio = uint64((totalCollateralization * BASE_9) / reservesValue);
        else collatRatio = type(uint64).max;
    }
}
