// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IAccessControlManager.sol";

/// @title IManager
/// @author Angle Labs
/// @notice Interface for the `Minter` contract
interface IManager {
    // Should implement this function to transfer underlying tokens to the right address
    // TODO add element potentially for a refund or not
    function transfer(address to, uint256 amount, bool revertIfNotEnough) external;

    function pullAll() external;

    function getUnderlyingBalance() external view returns (uint256);

    function maxAvailable() external view returns (uint256);
}
