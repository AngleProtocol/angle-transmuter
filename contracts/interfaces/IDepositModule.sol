// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

/// @title IDepositModule
/// @author Angle Labs, Inc.
interface IDepositModule {
    /// @notice Returns the current balance and value of the asset
    function getBalanceAndValue() external view returns (uint256, uint256);

    // It must return the address of the token
    function transfer(address receiver, uint256 amount) external;
}
