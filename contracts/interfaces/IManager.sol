// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.5.0;

/// @title IManager
/// @author Angle Labs, Inc.
interface IManager {
    /// @notice Returns the value of collateral managed by the Manager, in agToken
    /// @dev MUST NOT revert
    function totalAssets() external view returns (uint256);

    /// @notice Sends a proportion of managed assets to the `to` address
    /// @dev MUST revert if unsuccessful
    /// @dev MUST be callable only by the transmuter
    /// @dev MUST be called with `proportion` in BASE_18
    /// @dev MUST return exactly the amount transferred to `to`
    function redeem(
        address to,
        uint256 proportion,
        address[] memory forfeitTokens
    ) external returns (address[] memory tokens, uint256[] memory amounts);

    /// @notice Returns amounts that would be sent when releasing `proportion` of this manager's holdings
    /// @dev MUST be called with `proportion` in BASE_18
    /// @dev MUST return arrays of same size < 5
    function quoteRedeem(uint256 proportion) external view returns (address[] memory tokens, uint256[] memory amounts);

    /// @notice Sends `amount` of base collateral to the `to` address
    /// @dev Called when `agToken` are burned
    //  @dev MUST revert if there isn't enough available funds
    /// @dev MUST be callable only by the transmuter
    function release(address to, uint256 amount) external;

    /// @notice Manages `amount` new funds (in base collateral)
    /// @dev MUST revert if the manager cannot accept these funds
    /// @dev MUST have received the funds beforehand
    function invest(uint256 amount) external;
}
