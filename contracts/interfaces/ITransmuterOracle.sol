// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.5.0;

/// @title ITransmuterOracle
/// @author Angle Labs, Inc.
interface ITransmuterOracle {
    /// @notice Reads the oracle value for asset to use in a redemption to compute the collateral ratio
    function readRedemption() external view returns (uint256);

    /// @notice Reads the oracle value for asset to use in a mint. It should be comprehensive of the
    /// deviation from the target price
    function readMint() external view returns (uint256);

    /// @notice Reads the oracle value for asset to use in a burn transaction as well as the deviation
    /// from the target price for the asset
    function readBurn() external view returns (uint256 oracleValue, uint256 deviation);
}
