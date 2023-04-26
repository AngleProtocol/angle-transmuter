// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.12;

import { Storage as s } from "../libraries/Storage.sol";
import { AccessControl } from "../utils/AccessControl.sol";
import { Redeemer } from "../libraries/Redeemer.sol";
import { Diamond } from "../libraries/Diamond.sol";
import "../../utils/Constants.sol";

import "../../interfaces/IAccessControlManager.sol";
import "../Storage.sol";

contract Getters is AccessControl {
    function accessControlManager() external view onlyGovernor returns (IAccessControlManager) {
        return s.diamondStorage().accessControlManager;
    }

    /// @notice Checks whether `admin` has the governor role
    function isGovernor(address admin) public view returns (bool) {
        return Diamond.isGovernor(admin);
    }

    /// @notice Checks whether `admin` has the guardian role
    function isGovernorOrGuardian(address admin) public view returns (bool) {
        return Diamond.isGovernorOrGuardian(admin);
    }

    function getCollateralList() external view returns (address[] memory) {
        return s.kheopsStorage().collateralList;
    }

    function getRedeemableModuleList() external view returns (address[] memory) {
        return s.kheopsStorage().redeemableModuleList;
    }

    function getUnredeemableModuleList() external view returns (address[] memory) {
        return s.kheopsStorage().unredeemableModuleList;
    }

    function getCollateralRatio() external view returns (uint64 collatRatio, uint256 reservesValue) {
        (collatRatio, reservesValue, ) = Redeemer.getCollateralRatio();
    }

    function getIssuedByCollateral(address collateral) external view returns (uint256, uint256) {
        KheopsStorage storage ks = s.kheopsStorage();
        uint256 _accumulator = ks.accumulator;
        return ((ks.collaterals[collateral].r * _accumulator) / BASE_27, (ks.reserves * _accumulator) / BASE_27);
    }

    function getModuleBorrowed(address module) external view returns (uint256) {
        KheopsStorage storage ks = s.kheopsStorage();
        return (ks.modules[module].r * ks.accumulator) / BASE_27;
    }
}
