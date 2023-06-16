// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import { IRewardHandler } from "interfaces/IRewardHandler.sol";

import { IERC20 } from "oz/token/ERC20/IERC20.sol";
import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";

import { LibDiamond } from "../libraries/LibDiamond.sol";
import { LibStorage as s } from "../libraries/LibStorage.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import "../Storage.sol";

/// @title RewardHandler
/// @author Angle Labs, Inc.
contract RewardHandler is IRewardHandler {
    using SafeERC20 for IERC20;

    event RewardsSoldFor(address indexed tokenObtained, uint256 balanceUpdate);

    /// @notice IRewardHandler
    /// @dev It is impossible to sell a token that is a collateral through this function
    /// @dev Trusted sellers and governance only may call this function
    /// @dev Only governance can set which tokens can be swapped through this function by passing a prior approval
    /// transaction to 1inch router for the token to be swapped
    function sellRewards(uint256 minAmountOut, bytes memory payload) external returns (uint256 amountOut) {
        TransmuterStorage storage ks = s.transmuterStorage();
        if (!LibDiamond.isGovernorOrGuardian(msg.sender) && ks.isSellerTrusted[msg.sender] == 0) revert NotTrusted();
        address[] memory list = ks.collateralList;
        uint256 listLength = list.length;
        uint256[] memory balances = new uint256[](listLength);
        // Getting the balances of all collateral assets of the protocol to see if those do not decrease during
        // the swap: this is the only way to check that collateral assets have not been sold
        // Not checking the `subCollaterals` here as swaps should try to increase the balance of one collateral
        for (uint256 i; i < listLength; ++i) {
            balances[i] = IERC20(list[i]).balanceOf(address(this));
        }
        //solhint-disable-next-line
        (bool success, bytes memory result) = ONE_INCH_ROUTER.call(payload);
        if (!success) _revertBytes(result);
        amountOut = abi.decode(result, (uint256));
        if (amountOut < minAmountOut) revert TooSmallAmountOut();
        bool hasIncreased;
        for (uint256 i; i < listLength; ++i) {
            uint256 newBalance = IERC20(list[i]).balanceOf(address(this));
            if (newBalance < balances[i]) revert InvalidSwap();
            else if (newBalance > balances[i]) {
                hasIncreased = true;
                emit RewardsSoldFor(list[i], newBalance - balances[i]);
            }
        }
        if (!hasIncreased) revert InvalidSwap();
    }

    /// @notice Processes 1Inch revert messages
    function _revertBytes(bytes memory errMsg) private pure {
        if (errMsg.length > 0) {
            //solhint-disable-next-line
            assembly {
                revert(add(32, errMsg), mload(errMsg))
            }
        }
        revert OneInchSwapFailed();
    }
}
