// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import { Storage as s } from "../libraries/Storage.sol";
import "../../utils/Errors.sol";

contract AccessControl {
    /// @notice Checks whether `admin` has the governor role
    function isGovernor(address admin) public view returns (bool) {
        return s.diamondStorage().accessControlManager.isGovernor(admin);
    }

    /// @notice Checks whether `admin` has the guardian role
    function isGovernorOrGuardian(address admin) public view returns (bool) {
        return s.diamondStorage().accessControlManager.isGovernorOrGuardian(admin);
    }

    /// @notice Checks whether the `msg.sender` has the governor role
    modifier onlyGovernor() {
        if (!isGovernor(msg.sender)) revert NotGovernor();
        _;
    }

    /// @notice Checks whether the `msg.sender` has the guardian role
    modifier onlyGuardian() {
        if (!isGovernorOrGuardian(msg.sender)) revert NotGovernorOrGuardian();
        _;
    }
}
