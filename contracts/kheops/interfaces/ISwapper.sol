// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

interface ISwapper {
    function swapExactInput(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external returns (uint amountOut);

    function swapExactOutput(
        uint256 amountOut,
        uint256 amountInMax,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external returns (uint amountIn);

    function quoteIn(uint256 amountIn, address tokenIn, address tokenOut) external view returns (uint256);

    function quoteOut(uint256 amountOut, address tokenIn, address tokenOut) external view returns (uint256);
}
