// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.0;

import { SwapperLib } from "../libraries/SwapperLib.sol";

contract SwapperFacet {
    function swapExact(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external returns (uint amountOut) {
        return SwapperLib.swap(amountIn, amountOutMin, tokenIn, tokenOut, to, deadline, true);
    }

    function swapForExact(
        uint256 amountOut,
        uint256 amountInMax,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external returns (uint amountIn) {
        return SwapperLib.swap(amountOut, amountInMax, tokenIn, tokenOut, to, deadline, false);
    }
}
