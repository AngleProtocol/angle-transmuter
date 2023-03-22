// SPDX-License-Identifier: GPL-3.0

import "../interfaces/external/convex/IClaimZap.sol";
import "../interfaces/external/convex/IBooster.sol";
import "../interfaces/ITreasury.sol";

import "../utils/Errors.sol";

pragma solidity ^0.8.17;

contract AccessControl {
    /// @notice `accessControlManager` used to check roles
    IAccessControlManager public accessControlManager;

    uint256[49] private __gapStorage;

    // ================================= MODIFIERS =================================

    /// @notice Checks whether the `msg.sender` has the governor role
    modifier onlyGovernor() {
        if (!accessControlManager.isGovernor(msg.sender)) revert NotGovernor();
        _;
    }

    /// @notice Checks whether the `msg.sender` has the guardian role
    modifier onlyGuardian(address module) {
        if (!accessControlManager.isGovernorOrGuardian(msg.sender)) revert NotGovernorOrGuardian();
        _;
    }

    /// @notice Checks whether `admin` has the governor role
    function isGovernor(address admin) external view returns (bool) {
        return accessControlManager.isGovernor(admin);
    }

    /// @notice Checks whether `admin` has the guardian role
    function isGovernorOrGuardian(address admin) external view returns (bool) {
        return accessControlManager.isGovernorOrGuardian(admin);
    }
}
