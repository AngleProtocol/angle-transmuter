// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

/// @title IKheopsOracle
/// @author Angle Labs, Inc.
interface IKheopsOracle {
    function readRedemption() external view returns (uint256);

    function readMint() external view returns (uint256);

    function readBurn() external view returns (uint256 oracleValue, uint256 deviation);
}
