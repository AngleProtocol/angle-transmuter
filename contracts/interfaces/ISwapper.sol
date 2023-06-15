// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.5.0;

/// @title ISwapper
/// @author Angle Labs, Inc.
interface ISwapper {
    /// @notice Swaps (that is to say mints or burns) an exact amount of `tokenIn` for an amount of `tokenOut`
    /// @param amountIn Amount of `tokenIn` to bring
    /// @param amountOutMin Minimum amount of `tokenOut` to get: if `amountOut` is inferior to this amount, the
    /// function will revert
    /// @param tokenIn Token to bring for the swap
    /// @param tokenOut Token to get out of the swap
    /// @param to Address to which `tokenOut` must be sent
    /// @param deadline Timestamp before which the transaction must be executed
    /// @return amountOut Amount of `tokenOut` obtained through the swap
    function swapExactInput(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut);

    /// @notice Same as `swapExactInput`, but using Permit2 signatures for `tokenIn`
    /// @dev Can only be used to mint, hence `tokenOut` is not needed
    function swapExactInputWithPermit(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        address to,
        uint256 deadline,
        bytes calldata permitData
    ) external returns (uint256 amountOut);

    /// @notice Swaps (that is to say mints or burns) an amount of `tokenIn` for an exact amount of `tokenOut`
    /// @param amountOut Amount of `tokenOut` to obtain from the swap
    /// @param amountInMax Maximum amount of `tokenIn` to bring in order to get `amountOut` of `tokenOut`
    /// @param tokenIn Token to bring for the swap
    /// @param tokenOut Token to get out of the swap
    /// @param to Address to which `tokenOut` must be sent
    /// @param deadline Timestamp before which the transaction must be executed
    /// @return amountIn Amount of `tokenIn` used to perform the swap
    function swapExactOutput(
        uint256 amountOut,
        uint256 amountInMax,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external returns (uint256 amountIn);

    /// @notice Same as `swapExactOutput`, but using Permit2 signatures for `tokenIn`
    /// @dev Can only be used to mint, hence `tokenOut` is not needed
    function swapExactOutputWithPermit(
        uint256 amountOut,
        uint256 amountInMax,
        address tokenIn,
        address to,
        uint256 deadline,
        bytes calldata permitData
    ) external returns (uint256 amountIn);

    /// @notice Simulates what a call to `swapExactInput` with `amountIn` of `tokenIn` for `tokenOut` would give.
    /// If called right before and at the same block, the `amountOut` outputted by this function is exactly the
    /// amount that will be obtained with `swapExactInput`
    function quoteIn(uint256 amountIn, address tokenIn, address tokenOut) external view returns (uint256 amountOut);

    /// @notice Simulates what a call to `swapExactOutput` for `amountOut` of `tokenOut` with `tokenIn` would give.
    /// If called right before and at the same block, the `amountIn` outputted by this function is exactly the
    /// amount that will be obtained with `swapExactOutput`
    function quoteOut(uint256 amountOut, address tokenIn, address tokenOut) external view returns (uint256 amountIn);
}
