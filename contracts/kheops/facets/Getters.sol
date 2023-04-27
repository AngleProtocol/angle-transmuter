// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.12;

import { Storage as s } from "../libraries/Storage.sol";
import { AccessControl } from "../utils/AccessControl.sol";
import { LibRedeemer } from "../libraries/LibRedeemer.sol";
import { Diamond } from "../libraries/Diamond.sol";
import "../../utils/Constants.sol";

import { IAccessControlManager } from "../../interfaces/IAccessControlManager.sol";
import "../Storage.sol";

contract Getters {
    function accessControlManager() external view returns (IAccessControlManager) {
        return s.diamondStorage().accessControlManager;
    }

    /// @notice Checks whether `admin` has the governor role
    function isGovernor(address admin) external view returns (bool) {
        return Diamond.isGovernor(admin);
    }

    /// @notice Checks whether `admin` has the guardian role
    function isGovernorOrGuardian(address admin) external view returns (bool) {
        return Diamond.isGovernorOrGuardian(admin);
    }

    function getCollateralList() external view returns (address[] memory) {
        return s.kheopsStorage().collateralList;
    }

    function getCollateralMintFees(address collateralAddress) external view returns (uint64[] memory, int64[] memory) {
        Collateral storage collateral = s.kheopsStorage().collaterals[collateralAddress];
        return (collateral.xFeeMint, collateral.yFeeMint);
    }

    function getCollateralBurnFees(address collateralAddress) external view returns (uint64[] memory, int64[] memory) {
        Collateral storage collateral = s.kheopsStorage().collaterals[collateralAddress];
        return (collateral.xFeeBurn, collateral.yFeeBurn);
    }

    function getRedemptionFees() external view returns (uint64[] memory, uint64[] memory) {
        KheopsStorage storage ks = s.kheopsStorage();
        return (ks.xRedemptionCurve, ks.yRedemptionCurve);
    }

    function getRedeemableModuleList() external view returns (address[] memory) {
        return s.kheopsStorage().redeemableModuleList;
    }

    function getUnredeemableModuleList() external view returns (address[] memory) {
        return s.kheopsStorage().unredeemableModuleList;
    }

    function getCollateralRatio() external view returns (uint64 collatRatio, uint256 reservesValue) {
        (collatRatio, reservesValue, ) = LibRedeemer.getCollateralRatio();
    }

    function getIssuedByCollateral(address collateral) external view returns (uint256, uint256) {
        KheopsStorage storage ks = s.kheopsStorage();
        uint256 _normalizer = ks.normalizer;
        return (
            (ks.collaterals[collateral].normalizedStables * _normalizer) / BASE_27,
            (ks.normalizedStables * _normalizer) / BASE_27
        );
    }

    function getModuleBorrowed(address module) external view returns (uint256) {
        KheopsStorage storage ks = s.kheopsStorage();
        return (ks.modules[module].normalizedStables * ks.normalizer) / BASE_27;
    }

    function isModule(address module) external view returns (bool) {
        return s.kheopsStorage().modules[module].initialized > 0;
    }
}
