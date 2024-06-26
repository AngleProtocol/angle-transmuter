// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.5.0;

/// @title IKeyringGuard
/// @notice Interface for the `KeyringGuard` contract
interface IKeyringGuard {
    function isAuthorized(address from, address to) external returns (bool passed);
}
