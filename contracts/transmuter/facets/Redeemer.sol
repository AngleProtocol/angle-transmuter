// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import { IRedeemer } from "interfaces/IRedeemer.sol";

import { LibRedeemer } from "../libraries/LibRedeemer.sol";
import { LibStorage as s } from "../libraries/LibStorage.sol";
import { LibManager } from "../libraries/LibManager.sol";

import "../../utils/Constants.sol";
import "../Storage.sol";

/// @title Redeemer
/// @author Angle Labs, Inc.
contract Redeemer is IRedeemer {
    /// @inheritdoc IRedeemer
    /// @dev The `minAmountOuts` list must reflect or be longer than the amount of `tokens` returned
    /// @dev In normal conditions, the amount of tokens outputted by this function should be the amount
    /// of collateral assets supported by the system, following their order in the `collateralList`.
    /// @dev If one collateral has its liquidity managed through strategies, then it's possible that this asset
    /// has sub-collaterals with it. In this situation, these sub-collaterals may be sent during the redemption
    /// process and the `minAmountOuts` will be bigger than the `collateralList` length. If there are 3 collateral
    /// assets and the 2nd collateral asset in the list (at index 1) consists of 3 sub-collaterals, then the ordering
    /// of the token list will be as follows:
    /// `[collat 1, sub-collat 1 of collat 2, sub-collat 2 of collat 2, sub-collat 3 of collat 2, collat 3]`
    /// @dev The list of tokens outputted (and hence the minimum length of the `minAmountOuts` list) can be obtained
    /// by calling the `quoteRedemptionCurve` function
    /// @dev Tokens requiring a whitelist must be forfeited if the redemption is to an address that is not in the
    /// whitelist, otherwise this function reverts
    function redeem(
        uint256 amount,
        address receiver,
        uint256 deadline,
        uint256[] memory minAmountOuts
    ) external returns (address[] memory tokens, uint256[] memory amounts) {
        return LibRedeemer.redeem(amount, receiver, deadline, minAmountOuts, new address[](0));
    }

    /// @inheritdoc IRedeemer
    /// @dev Beware that if a token is given in the `forfeitTokens` list, the redemption will not try to send token
    /// even if it has enough immediately available to send the amount
    function redeemWithForfeit(
        uint256 amount,
        address receiver,
        uint256 deadline,
        uint256[] memory minAmountOuts,
        address[] memory forfeitTokens
    ) external returns (address[] memory tokens, uint256[] memory amounts) {
        return LibRedeemer.redeem(amount, receiver, deadline, minAmountOuts, forfeitTokens);
    }

    /// @inheritdoc IRedeemer
    function quoteRedemptionCurve(
        uint256 amount
    ) external view returns (address[] memory tokens, uint256[] memory amounts) {
        uint256 proportion = LibRedeemer.quoteProportion(amount);

        TransmuterStorage storage ks = s.transmuterStorage();
        address[] memory collateralListMem = ks.collateralList;
        uint256 collateralListLength = collateralListMem.length;
        tokens = new address[](5 * collateralListLength);
        amounts = new uint256[](5 * collateralListLength);
        uint256 index = 0;
        for (uint256 i; i < collateralListLength; ++i) {
            Collateral storage collateral = ks.collaterals[collateralListMem[i]];
            if (collateral.isManaged > 0) {
                (address[] memory managerTokens, uint256[] memory managerBalances) = LibManager.quoteRedeem(
                    proportion,
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
                ++index;
            }
        }
        ++index; // index is now the length of the `tokens` and `amounts` arrays
        assembly {
            mstore(tokens, index)
            mstore(amounts, index)
        }
    }
}
