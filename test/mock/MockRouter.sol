// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.19;

import { SafeERC20, IERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";

contract MockRouter {
    using SafeERC20 for IERC20;

    function swap(uint256 amountIn, address tokenIn, uint256 amountOut, address tokenOut) external {
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
    }
}
