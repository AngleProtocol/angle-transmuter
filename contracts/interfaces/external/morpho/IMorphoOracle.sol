// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.5.0;

/// @title IMorphoOracle
/// @notice Interface for the oracle contracts used within Morpho
interface IMorphoOracle {
    function price() external view returns (uint256);
}
