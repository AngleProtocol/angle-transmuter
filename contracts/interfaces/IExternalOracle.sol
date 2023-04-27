// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

/// @title IExternalOracle
/// @author Angle Labs, Inc.
interface IExternalOracle {
    function readRedemption() external view returns (uint256);

    function readMint() external view returns (uint256);

    function readBurn() external view returns (uint256 oracleValue, uint256 deviation);

    // Function need access control
    function updateInternalData(uint256 amountIn, uint256 amountOut, bool mint) external;

    // TODO delete when old oracle are removed
    function read() external view returns (uint256);
}
