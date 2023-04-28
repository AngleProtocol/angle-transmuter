// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IAccessControlManager } from "../../interfaces/IAccessControlManager.sol";

import { Storage as s } from "../libraries/Storage.sol";
import { LibManager } from "../libraries/LibManager.sol";
import { Setters as Lib } from "../libraries/Setters.sol";
import { Helper as LibHelper } from "../libraries/Helper.sol";
// import { Utils } from "../libraries/Utils.sol";
import { AccessControl } from "../utils/AccessControl.sol";
import { Oracle } from "../libraries/Oracle.sol";
import "../../utils/Constants.sol";
import "../../utils/Errors.sol";

import "../Storage.sol";

contract Setters is AccessControl {
    using SafeERC20 for IERC20;

    function recoverERC20(address collateral, IERC20 token, address to, uint256 amount) external onlyGovernor {
        KheopsStorage storage ks = s.kheopsStorage();
        Collateral storage collatInfo = ks.collaterals[collateral];
        LibHelper.transferCollateral(
            collateral,
            collatInfo.hasManager > 0 ? address(token) : address(0),
            to,
            amount,
            false
        );
    }

    function setAccessControlManager(IAccessControlManager _newAccessControlManager) external onlyGovernor {
        Lib.setAccessControlManager(_newAccessControlManager);
    }

    function setCollateralManager(address collateral, address manager) external onlyGovernor {
        Collateral storage collatInfo = s.kheopsStorage().collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        uint8 hasManager = collatInfo.hasManager;
        if (hasManager > 0) LibManager.pullAll(collateral, false);
        if (manager != address(0)) collatInfo.hasManager = 1;
    }

    function togglePause(address collateral, uint8 pausedType) external onlyGuardian {
        if (pausedType == 0 || pausedType == 1) {
            Collateral storage collatInfo = s.kheopsStorage().collaterals[collateral];
            if (collatInfo.decimals == 0) revert NotCollateral();
            if (pausedType == 0) {
                uint8 pausedStatus = collatInfo.unpausedMint;
                collatInfo.unpausedMint = 1 - pausedStatus;
            } else {
                uint8 pausedStatus = collatInfo.unpausedBurn;
                collatInfo.unpausedBurn = 1 - pausedStatus;
            }
        } else if (pausedType == 2) {
            Module storage module = s.kheopsStorage().modules[collateral];
            if (module.initialized == 0) revert NotModule();
            uint8 pausedStatus = module.unpaused;
            module.unpaused = 1 - pausedStatus;
        } else {
            KheopsStorage storage ks = s.kheopsStorage();
            uint8 pausedStatus = ks.pausedRedemption;
            ks.pausedRedemption = 1 - pausedStatus;
        }
    }

    function toggleTrusted(address sender) external onlyGovernor {
        KheopsStorage storage ks = s.kheopsStorage();
        uint256 trustedStatus = 1 - ks.isTrusted[sender];
        ks.isTrusted[sender] = trustedStatus;
    }

    // Need to be followed by a call to set fees and set oracle and unpaused
    function addCollateral(address collateral) external onlyGovernor {
        Lib.addCollateral(collateral);
    }

    function addModule(address moduleAddress, address token, uint8 redeemable) external onlyGovernor {
        KheopsStorage storage ks = s.kheopsStorage();
        Module storage module = ks.modules[moduleAddress];
        if (module.initialized != 0) revert AlreadyAdded();
        module.token = token;
        module.redeemable = redeemable;
        module.initialized = 1;
        if (redeemable > 0) ks.redeemableModuleList.push(moduleAddress);
        else ks.unredeemableModuleList.push(moduleAddress);
    }

    function revokeCollateral(address collateral) external onlyGovernor {
        KheopsStorage storage ks = s.kheopsStorage();
        Collateral memory collatInfo = ks.collaterals[collateral];
        if (collatInfo.decimals == 0 || collatInfo.normalizedStables > 0) revert NotCollateral();
        delete ks.collaterals[collateral];
        address[] memory collateralListMem = ks.collateralList;
        uint256 length = collateralListMem.length;
        // We already know that it is in the list
        for (uint256 i; i < length - 1; ++i) {
            if (collateralListMem[i] == collateral) {
                ks.collateralList[i] = collateralListMem[length - 1];
                break;
            }
        }
        ks.collateralList.pop();
    }

    function revokeModule(address moduleAddress) external onlyGovernor {
        KheopsStorage storage ks = s.kheopsStorage();
        Module storage module = ks.modules[moduleAddress];
        if (module.initialized == 0 || module.normalizedStables > 0) revert NotModule();
        if (module.redeemable > 0) {
            address[] memory redeemableModuleListMem = ks.redeemableModuleList;
            uint256 length = redeemableModuleListMem.length;
            // We already know that it is in the list
            for (uint256 i; i < length - 1; ++i) {
                if (ks.redeemableModuleList[i] == moduleAddress) {
                    ks.redeemableModuleList[i] = redeemableModuleListMem[length - 1];
                    break;
                }
            }
            ks.redeemableModuleList.pop();
        }
        // No need to remove from the unredeemable module list -> it is never actually queried
        delete ks.modules[moduleAddress];
    }

    function setFees(address collateral, uint64[] memory xFee, int64[] memory yFee, bool mint) external onlyGuardian {
        Collateral storage collatInfo = s.kheopsStorage().collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        uint8 setter;
        if (!mint) setter = 1;
        // _checkFees(xFee, yFee, setter);
        if (mint) {
            collatInfo.xFeeMint = xFee;
            collatInfo.yFeeMint = yFee;
        } else {
            collatInfo.xFeeBurn = xFee;
            collatInfo.yFeeBurn = yFee;
        }
    }

    function setRedemptionCurveParams(uint64[] memory xFee, uint64[] memory yFee) external onlyGuardian {
        KheopsStorage storage ks = s.kheopsStorage();
        // _checkFees(xFee, yFee, 2);
        ks.xRedemptionCurve = xFee;
        ks.yRedemptionCurve = yFee;
    }

    function setModuleMaxExposure(address moduleAddress, uint64 maxExposure) external onlyGuardian {
        Module storage module = s.kheopsStorage().modules[moduleAddress];
        if (module.initialized == 0) revert NotModule();
        if (maxExposure > BASE_9) revert InvalidParam();
        module.maxExposure = maxExposure;
    }

    function setOracle(address collateral, bytes memory oracleConfig) external onlyGovernor {
        Collateral storage collatInfo = s.kheopsStorage().collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        if (keccak256(oracleConfig) != keccak256("0x")) Oracle.readMint(oracleConfig, collatInfo.oracleStorage);
        collatInfo.oracleConfig = oracleConfig;
    }

    // function _checkFees(uint64[] memory xFee, uint64[] memory yFee, uint8 setter) internal view {
    //     uint256 n = xFee.length;
    //     if (n != yFee.length || n == 0) revert InvalidParams();
    //     for (uint256 i = 0; i < n - 1; ++i) {
    //         if (
    //             (xFee[i] >= xFee[i + 1]) ||
    //             (setter == 0 && (yFee[i + 1] < yFee[i])) ||
    //             (setter == 1 && (yFee[i + 1] > yFee[i])) ||
    //             (setter == 2 && yFee[i] < 0) ||
    //             xFee[i] > uint64(BASE_9) ||
    //             yFee[i] < -int64(uint64(BASE_9)) ||
    //             yFee[i] > int64(uint64(BASE_9))
    //         ) revert InvalidParams();
    //     }

    //     KheopsStorage storage ks = s.kheopsStorage();
    //     address[] memory collateralListMem = ks.collateralList;
    //     uint256 length = collateralListMem.length;
    //     if (setter == 0 && yFee[0] < 0) {
    //         // Checking that the mint fee is still bigger than the smallest burn fee everywhere
    //         for (uint256 i; i < length; ++i) {
    //             int64[] memory burnFees = ks.collaterals[collateralListMem[i]].yFeeBurn;
    //             if (burnFees[burnFees.length - 1] + yFee[0] < 0) revert InvalidParams();
    //         }
    //     }
    //     if (setter == 1 && yFee[n - 1] < 0) {
    //         for (uint256 i; i < length; ++i) {
    //             int64[] memory mintFees = ks.collaterals[collateralListMem[i]].yFeeMint;
    //             if (mintFees[0] + yFee[n - 1] < 0) revert InvalidParams();
    //         }
    //     }
    // }
}
