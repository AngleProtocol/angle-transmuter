// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.12;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import "../Storage.sol";

/// @title ISetters
/// @author Angle Labs, Inc.
interface ISetters {
    function adjustReserve(address collateral, uint128 amount, bool addOrRemove) external;

    function recoverERC20(address collateral, IERC20 token, address to, uint256 amount) external;

    function setAccessControlManager(address _newAccessControlManager) external;

    function setCollateralManager(address collateral, ManagerStorage memory managerData) external;

    function togglePause(address collateral, PauseType pausedType) external;

    function toggleTrusted(address sender, uint8 trustedType) external;

    function addCollateral(address collateral) external;

    function revokeCollateral(address collateral) external;

    function setManagerData(address collateral, ManagerStorage memory managerData) external;

    function setFees(address collateral, uint64[] memory xFee, int64[] memory yFee, bool mint) external;

    function setRedemptionCurveParams(uint64[] memory xFee, int64[] memory yFee) external;

    function setOracle(address collateral, bytes memory oracleConfig) external;

    function updateNormalizer(uint256 amount, bool increase) external returns (uint256);
}
