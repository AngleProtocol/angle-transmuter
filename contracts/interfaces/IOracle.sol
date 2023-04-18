// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

/// @title IOracle
/// @author Angle Labs, Inc.
interface IOracle {
    /// @notice Reads the rate from the Chainlink circuit and other data provided
    /// @return quoteAmount The current rate between the in-currency and out-currency in the base
    /// of the out currency
    /// @dev For instance if the out currency is EUR (and hence agEUR), then the base of the returned
    /// value is 10**18
    function read() external view returns (uint256);

    /// @notice Should return the minimum between (current oracle value, target value with respect to the asset)
    /// @dev For EUROC, it should return min(oracle EUROC, 1)
    function readMint() external view returns (uint256);

    /// @notice Returns the current oracle value (overestimated if possible)
    function readBurn() external view returns (uint256, uint256);

    /// @notice Returns the deviation with respect to the target value for the asset
    /// @dev If EUROC is worth 0.995 instead of 1, then this should return 0.995
    function getDeviation() external view returns (uint256);
}
