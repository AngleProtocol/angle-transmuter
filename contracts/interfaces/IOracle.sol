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
}
