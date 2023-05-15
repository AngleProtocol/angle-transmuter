// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { IRewardHandler } from "../interfaces/IRewardHandler.sol";

import { LibRewardHandler } from "../libraries/LibRewardHandler.sol";

/// @title RewardHandler
/// @author Angle Labs, Inc.
contract RewardHandler is IRewardHandler {
    /// @inheritdoc IRewardHandler
    /// @dev It is impossible to sell a token that is a collateral through this function
    /// @dev Trusted sellers and governance only may call this function
    function sellRewards(uint256 minAmountOut, bytes memory payload) external returns (uint256 amountOut) {
        return LibRewardHandler.sellRewards(minAmountOut, payload);
    }
}
