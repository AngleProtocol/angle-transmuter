// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import { IAccessControlManager } from "../../interfaces/IAccessControlManager.sol";

interface IGetters {
    function isValidSelector(bytes4 selector) external view returns (bool);

    function accessControlManager() external view returns (IAccessControlManager);

    function isGovernor(address admin) external view returns (bool);

    function isGovernorOrGuardian(address admin) external view returns (bool);

    function getCollateralList() external view returns (address[] memory);

    function getCollateralMintFees(address collateralAddress) external view returns (uint64[] memory, int64[] memory);

    function getCollateralBurnFees(address collateralAddress) external view returns (uint64[] memory, int64[] memory);

    function getRedemptionFees() external view returns (uint64[] memory, uint64[] memory);

    function getRedeemableModuleList() external view returns (address[] memory);

    function getUnredeemableModuleList() external view returns (address[] memory);

    function getCollateralRatio() external view returns (uint64 collatRatio, uint256 reservesValue);

    function getIssuedByCollateral(address collateral) external view returns (uint256, uint256);

    function getModuleBorrowed(address module) external view returns (uint256);

    function isModule(address module) external view returns (bool);
}
