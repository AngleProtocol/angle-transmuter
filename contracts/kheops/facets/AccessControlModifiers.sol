// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.12;

import { LibDiamond } from "../libraries/LibDiamond.sol";

import "../../utils/Errors.sol";

/// @title AccessControlModifiers
/// @author Angle Labs, Inc.
contract AccessControlModifiers {
    /// @notice Checks whether the `msg.sender` has the governor role
    modifier onlyGovernor() {
        if (!LibDiamond.isGovernor(msg.sender)) revert NotGovernor();
        _;
    }

    /// @notice Checks whether the `msg.sender` has the guardian role
    modifier onlyGuardian() {
        if (!LibDiamond.isGovernorOrGuardian(msg.sender)) revert NotGovernorOrGuardian();
        _;
    }
}

