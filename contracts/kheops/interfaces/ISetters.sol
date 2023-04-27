// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

interface ISetters {
    function recoverERC20(IERC20 token, address to, uint256 amount, bool manager) external;

    function setAccessControlManager(address _newAccessControlManager) external;

    function setCollateralManager(address collateral, address manager) external;

    function togglePause(address collateral, uint8 pausedType) external;

    function toggleTrusted(address sender) external;

    function addCollateral(address collateral) external;

    function addModule(address moduleAddress, address token, uint8 redeemable) external;

    function revokeCollateral(address collateral) external;

    function revokeModule(address moduleAddress) external;

    function setFees(address collateral, uint64[] memory xFee, int64[] memory yFee, bool mint) external;

    function setRedemptionCurveParams(uint64[] memory xFee, uint64[] memory yFee) external;

    function setModuleMaxExposure(address moduleAddress, uint64 maxExposure) external;

    function setOracle(address collateral, bytes memory oracle) external;
}
