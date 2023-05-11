// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import { LibRedeemer as Lib } from "../libraries/LibRedeemer.sol";
import { LibStorage as s } from "../libraries/LibStorage.sol";
import "../Storage.sol";

import { IRedeemer } from "../interfaces/IRedeemer.sol";

/// @title Redeemer
/// @author Angle Labs, Inc.
contract Redeemer is IRedeemer {
    /// @inheritdoc IRedeemer
    function redeem(
        uint256 amount,
        address receiver,
        uint256 deadline,
        uint256[] memory minAmountOuts
    ) external returns (address[] memory tokens, uint256[] memory amounts) {
        address[] memory forfeitTokens;
        return Lib.redeem(amount, receiver, deadline, minAmountOuts, forfeitTokens);
    }

    /// @inheritdoc IRedeemer
    function redeemWithForfeit(
        uint256 amount,
        address receiver,
        uint256 deadline,
        uint256[] memory minAmountOuts,
        address[] memory forfeitTokens
    ) external returns (address[] memory tokens, uint256[] memory amounts) {
        return Lib.redeem(amount, receiver, deadline, minAmountOuts, forfeitTokens);
    }

    /// @inheritdoc IRedeemer
    function quoteRedemptionCurve(
        uint256 amountBurnt
    ) external view returns (address[] memory tokens, uint256[] memory amounts) {
        (tokens, amounts, ) = Lib.quoteRedemptionCurve(amountBurnt);
    }
}
