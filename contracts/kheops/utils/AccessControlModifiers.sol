// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.12;

import { Diamond } from "../libraries/Diamond.sol";

import "../../utils/Errors.sol";

/// @title AccessControlModifiers
/// @author Angle Labs, Inc.
contract AccessControlModifiers {
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
