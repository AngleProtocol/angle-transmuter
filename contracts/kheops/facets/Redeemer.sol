// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.0;

import { LibRedeemer as Lib } from "../libraries/LibRedeemer.sol";
import { Storage as s } from "../libraries/Storage.sol";
import "../Storage.sol";

contract Redeemer {
    function redeem(
        uint256 amount,
        address receiver,
        uint256 deadline,
        uint256[] memory minAmountOuts
    ) external returns (address[] memory tokens, uint256[] memory amounts) {
        address[] memory forfeitTokens;
        return Lib.redeem(amount, receiver, deadline, minAmountOuts, forfeitTokens);
    }

    function redeemWithForfeit(
        uint256 amount,
        address receiver,
        uint256 deadline,
        uint256[] memory minAmountOuts,
        address[] memory forfeitTokens
    ) external returns (address[] memory tokens, uint256[] memory amounts) {
        return Lib.redeem(amount, receiver, deadline, minAmountOuts, forfeitTokens);
    }

    function quoteRedemptionCurve(
        uint256 amountBurnt
    ) external view returns (address[] memory tokens, uint256[] memory amounts) {
        KheopsStorage storage ks = s.kheopsStorage();
        amounts = Lib.quoteRedemptionCurve(amountBurnt);
        address[] memory list = ks.collateralList;
        uint256 collateralLength = list.length;
        address[] memory depositModuleList = ks.redeemableModuleList;
        uint256 depositModuleLength = depositModuleList.length;

        tokens = new address[](collateralLength + depositModuleLength);
        for (uint256 i; i < collateralLength; ++i) {
            tokens[i] = list[i];
        }
        for (uint256 i; i < depositModuleLength; ++i) {
            tokens[i + collateralLength] = ks.modules[depositModuleList[i]].token;
        }
    }
}
