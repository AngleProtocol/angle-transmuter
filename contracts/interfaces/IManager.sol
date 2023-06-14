// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.5.0;

/// @title IManager
/// @author Angle Labs, Inc.
interface IManager {
    /// @notice Transfers `amount` of `token` to the `to` address, and eventually pulls funds from strategies
    /// to achieve this
    function transferTo(address token, address to, uint256 amount) external;

    /// @notice Removes all funds from the manager and sends them back to the Transmuter contract
    function pullAll() external;

    /// @notice Gets the balances of all the tokens controlled be the manager contract
    /// @return balances An array of size `subCollaterals` with current balances for all subCollaterals
    /// @return totalValue Cumulated value of all the subCollaterals excluding the one that is actually
    /// used within the Transmuter system
    function getUnderlyingBalances() external view returns (uint256[] memory balances, uint256 totalValue);

    /// @notice Gives the maximum amount of collateral immediately available for a transfer
    function maxAvailable() external view returns (uint256);
}
