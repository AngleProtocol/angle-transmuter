// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

interface ISetters {
    function adjustReserve(address collateral, uint256 amount, bool addOrRemove) external;

    function recoverERC20(address collateral, IERC20 token, address to, uint256 amount) external;

    function setAccessControlManager(address _newAccessControlManager) external;

    function setCollateralManager(address collateral, address manager) external;

    function togglePause(address collateral, uint8 pausedType) external;

    function toggleTrusted(address sender) external;

    function addCollateral(address collateral) external;

    function revokeCollateral(address collateral) external;

    function setFees(address collateral, uint64[] memory xFee, int64[] memory yFee, bool mint) external;

    function setRedemptionCurveParams(uint64[] memory xFee, int64[] memory yFee) external;

    function setOracle(address collateral, bytes memory oracleConfig, bytes memory oracleStorage) external;

    function updateNormalizer(uint256 amount, bool increase) external returns (uint256);
}
