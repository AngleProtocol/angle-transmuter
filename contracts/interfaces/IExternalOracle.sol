// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

/// @title IExternalOracle
/// @author Angle Labs, Inc.
interface IExternalOracle {
    function targetPrice() external view returns (uint256);

    function read() external view returns (uint256);

    function quoteAmount() external view returns (uint256);
}
