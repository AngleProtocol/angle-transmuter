// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import { Storage as s } from "../libraries/Storage.sol";
import { Diamond } from "../libraries/Diamond.sol";
import "../../utils/Errors.sol";

contract AccessControl {
    /// @notice Checks whether the `msg.sender` has the governor role
    modifier onlyGovernor() {
        if (!Diamond.isGovernor(msg.sender)) revert NotGovernor();
        _;
    }

    /// @notice Checks whether the `msg.sender` has the guardian role
    modifier onlyGuardian() {
        if (!Diamond.isGovernorOrGuardian(msg.sender)) revert NotGovernorOrGuardian();
        _;
    }
}
