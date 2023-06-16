// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.5.0;

/// @title IManager
/// @author Angle Labs, Inc.
interface IManager {
    /// @notice Returns the value of collateral managed by the Manager, in agToken
    /// @dev MUST NOT revert
    function totalAssets() external view returns (uint256[] memory balances, uint256 totalValue);

    /// @notice Manages `amount` new funds (in base collateral)
    /// @dev MUST revert if the manager cannot accept these funds
    /// @dev MUST have received the funds beforehand
    function invest(uint256 amount) external;

    /// @notice Sends `amount` of base collateral to the `to` address
    /// @dev Called when `agToken` are burned and during redemptions
    //  @dev MUST revert if there isn't enough available funds
    /// @dev MUST be callable only by the transmuter
    function release(address asset, address to, uint256 amount) external;

    /// @notice Gives the maximum amount of collateral immediately available for a transfer
    /// @notice Useful for integrators using `quoteIn` and `quoteOut`
    function maxAvailable() external view returns (uint256);
}
