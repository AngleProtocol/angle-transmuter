// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.12;

import { LibRewardHandler } from "../libraries/LibRewardHandler.sol";

/// @title RewardHandler
/// @author Angle Labs, Inc.
contract RewardHandler {
    function sellRewards(uint256 minAmountOut, bytes memory payload) external returns (uint256 amountOut) {
        return LibRewardHandler.sellRewards(minAmountOut, payload);
    }
}
