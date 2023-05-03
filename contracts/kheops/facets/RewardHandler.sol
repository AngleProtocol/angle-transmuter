// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import { AccessControl } from "../utils/AccessControl.sol";
import "../libraries/LibRewardHandler.sol";

contract RewardHandler is AccessControl {
    function sellRewards(
        uint256 minAmountOut,
        bytes memory payload,
        address tokenToSwapFor
    ) external returns (uint256 amountOut) {
        return LibRewardHandler.sellRewards(minAmountOut, payload, tokenToSwapFor);
    }
}
