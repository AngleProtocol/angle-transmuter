// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.5.0;

/// @title IOracle
/// @author Angle Labs, Inc.
interface IOracle {
    /// @notice Update oracle data for a given `collateral`
    function updateOracle(address collateral) external;
}
