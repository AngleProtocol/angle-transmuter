// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.0;

import { RedeemerLib } from "../libraries/RedeemerLib.sol";

contract RedeemerFacet {
    function redeem(
        uint256 amount,
        address receiver,
        uint256 deadline,
        uint256[] memory minAmountOuts
    ) external returns (address[] memory tokens, uint256[] memory amounts) {
        address[] memory forfeitTokens;
        return RedeemerLib.redeem(amount, receiver, deadline, minAmountOuts, forfeitTokens);
    }

    function redeemWithForfeit(
        uint256 amount,
        address receiver,
        uint256 deadline,
        uint256[] memory minAmountOuts,
        address[] memory forfeitTokens
    ) external returns (address[] memory tokens, uint256[] memory amounts) {
        return RedeemerLib.redeem(amount, receiver, deadline, minAmountOuts, forfeitTokens);
    }
}
