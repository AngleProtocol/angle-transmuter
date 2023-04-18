// SPDX-License-Identifier: GPL-3.0

import "./IOracle.sol";

pragma solidity ^0.8.12;

/// @title IOracle
/// @author Angle Labs, Inc.
interface IOracleFallback is IOracle {
    function updateInternalData(uint256 amountIn, uint256 amountOut, bool mint) external;
}
