// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.5.0;

/// @title ITransmuterOracle
/// @author Angle Labs, Inc.
interface ITransmuterOracle {
    function readRedemption() external view returns (uint256);

    function readMint() external view returns (uint256);

    function readBurn() external view returns (uint256 oracleValue, uint256 deviation);
}
