// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

/// @title IOracle
/// @author Angle Labs, Inc.
interface IOracle {
    /// @notice Should return the minimum between (current oracle value, target value with respect to the asset)
    /// @dev For EUROC, it should return min(oracle EUROC, 1)
    function readMint() external view returns (uint256);

    /// @notice Returns the current oracle value (overestimated if possible), and the deviation from the target value
    function readBurn() external view returns (uint256, uint256);

    function read() external view returns (uint256);

    /// @notice Returns the deviation with respect to the target value for the asset
    /// @dev If EUROC is worth 0.995 instead of 1, then this should return 0.995
    function getDeviation() external view returns (uint256);
}
