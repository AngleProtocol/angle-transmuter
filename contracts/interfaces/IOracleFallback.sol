// SPDX-License-Identifier: GPL-3.0

import "./IExternalOracle.sol";

pragma solidity ^0.8.12;

/// @title IOracle
/// @author Angle Labs, Inc.
interface IOracleFallback is IExternalOracle {
    function updateInternalData(uint256 amountIn, uint256 amountOut, bool mint) external;
}
