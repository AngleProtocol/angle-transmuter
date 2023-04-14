// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IAccessControlManager.sol";

/// @title IManager
/// @author Angle Labs
/// @notice Interface for the `Minter` contract
interface IManager {
    function pull(uint256 amount) external;
}
