// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.5.0;

/// @title IKeyringGuard
/// @notice Interface for the IKeyringGuard contract
interface IKeyringGuard {
    function isAuthorized(address from, address to) external view returns (bool passed);
}
