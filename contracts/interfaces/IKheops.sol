// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IAccessControlManager.sol";
import "../interfaces/IAgToken.sol";

/// @title IKheops
/// @author Angle Labs
/// @notice Interface for the `Minter` contract
interface IKheops {
    function borrow(uint256 amount) external returns (uint256);

    function agToken() external returns (IAgToken);

    function repay(uint256 amount) external returns (uint256);

    function getModuleBorrowed(address module) external view returns (uint256);

    function isModule(address module) external view returns (bool);
}
