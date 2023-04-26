// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IDiamondCut.sol";
import "../interfaces/IAccessControlManager.sol";
import "../interfaces/IAgToken.sol";

/// @title IKheops
/// @author Angle Labs
/// @notice Interface for the `Minter` contract
interface IKheops is IDiamondCut {
    // TODO TO UPDATE
    function borrow(uint256 amount) external returns (uint256);

    function agToken() external returns (IAgToken);

    function repay(uint256 amount) external returns (uint256);

    function getModuleBorrowed(address module) external view returns (uint256);

    function isModule(address module) external view returns (bool);

    function getCollateralRatio() external view returns (uint64 collatRatio, uint256 reservesValue);

    function getIssuedByCollateral(address collateral) external view returns (uint256, uint256);

    function updateAccumulator(uint256 amount, bool increase) external returns (uint256);
}
