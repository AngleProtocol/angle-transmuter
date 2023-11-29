// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.5.0;

struct Order {
    // Total agToken budget allocated to subsidize the swaps between the tokens associated to the order
    uint112 subsidyBudget;
    // Decimals of the `tokenIn` associated to the order
    uint8 decimalsIn;
    // Decimals of the `tokenOut` associated to the order
    uint8 decimalsOut;
    // Guaranteed exchange rate in `BASE_18` for the swaps between the `tokenIn` and `tokenOut` associated to
    // the order. This rate is a minimum rate guaranteed up to when the `subsidyBudget` is fully consumed
    uint128 guaranteedRate;
}

/// @title IRebalancer
/// @author Angle Labs, Inc.
interface IRebalancer {
    /// @notice Swaps `tokenIn` for `tokenOut` through an intermediary agToken mint from `tokenIn` and
    /// burn to `tokenOut`. Eventually, this transaction may be sponsored and yield an amount of `tokenOut`
    /// higher than what would be obtained through a mint and burn directly on the `transmuter`
    /// @param amountIn Amount of `tokenIn` to bring for the rebalancing
    /// @param amountOutMin Minimum amount of `tokenOut` that must be obtained from the swap
    /// @param to Address to which `tokenOut` must be sent
    /// @param deadline Timestamp before which this transaction must be included
    /// @return amountOut Amount of outToken obtained
    function swapExactInput(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut);

    /// @notice Approximates how much a call to `swapExactInput` with the same parameters would yield in terms
    /// of `amountOut`
    function quoteIn(uint256 amountIn, address tokenIn, address tokenOut) external view returns (uint256 amountOut);

    /// @notice Helper to compute the minimum guaranteed amount out that would be obtained from a swap of `amountIn`
    /// of `tokenIn` to `tokenOut`
    function getGuaranteedAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256);

    /// @notice Lets governance set an order to subsidize rebalances between `tokenIn` and `tokenOut`
    function setOrder(address tokenIn, address tokenOut, uint256 subsidyBudget, uint256 guaranteedRate) external;

    /// @notice Recovers `amount` of `token` to the `to` address
    /// @dev This function checks if too much is not being recovered with respect to currently available budgets
    function recover(address token, uint256 amount, address to) external;
}
