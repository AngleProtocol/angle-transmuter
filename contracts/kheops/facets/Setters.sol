// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { IERC20 } from "oz/interfaces/IERC20.sol";
import { IERC20Metadata } from "oz/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";

import { IAccessControlManager } from "interfaces/IAccessControlManager.sol";
import { ISetters } from "interfaces/ISetters.sol";

import { LibDiamond } from "../libraries/LibDiamond.sol";
import { LibHelpers } from "../libraries/LibHelpers.sol";
import { LibManager } from "../libraries/LibManager.sol";
import { LibRedeemer } from "../libraries/LibRedeemer.sol";
import { LibSetters } from "../libraries/LibSetters.sol";
import { LibStorage as s } from "../libraries/LibStorage.sol";
import { AccessControlModifiers } from "./AccessControlModifiers.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import "../Storage.sol";

/// @title Setters
/// @author Angle Labs, Inc.
contract Setters is AccessControlModifiers, ISetters {
    using SafeERC20 for IERC20;

    event CollateralManagerSet(address indexed collateral, ManagerStorage managerData);
    event CollateralRevoked(address indexed collateral);
    event ManagerDataSet(address indexed collateral, ManagerStorage managerData);
    event RedemptionCurveParamsSet(uint64[] xFee, int64[] yFee);
    event ReservesAdjusted(address indexed collateral, uint256 amount, bool addOrRemove);
    event TrustedToggled(address indexed sender, uint256 trustedStatus, uint8 trustedType);

    /// @inheritdoc ISetters
    /// @dev No check is made on the collateral that is redeemed: this function could typically be used by a governance
    /// during a manual rebalance the reserves of the system
    function recoverERC20(address collateral, IERC20 token, address to, uint256 amount) external onlyGovernor {
        KheopsStorage storage ks = s.kheopsStorage();
        Collateral storage collatInfo = ks.collaterals[collateral];
        bool isManaged = collatInfo.isManaged > 0;
        ManagerStorage memory emptyManagerData;
        LibHelpers.transferCollateralTo(
            isManaged ? address(token) : collateral,
            to,
            amount,
            false,
            isManaged ? collatInfo.managerData : emptyManagerData
        );
    }

    /// @inheritdoc ISetters
    function setAccessControlManager(address _newAccessControlManager) external onlyGovernor {
        LibSetters.setAccessControlManager(IAccessControlManager(_newAccessControlManager));
    }

    /// @inheritdoc ISetters
    function setCollateralManager(address collateral, ManagerStorage memory managerData) external onlyGovernor {
        Collateral storage collatInfo = s.kheopsStorage().collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        uint8 isManaged = collatInfo.isManaged;
        if (isManaged > 0) LibManager.pullAll(collatInfo.managerData);
        if (managerData.managerConfig.length != 0) {
            // The first subCollateral given should be the actual collateral asset
            if (address(managerData.subCollaterals[0]) != collateral) revert InvalidParam();
            // Sanity check on the manager data that is passed
            LibManager.parseManagerData(managerData);
            collatInfo.isManaged = 1;
        } else {
            ManagerStorage memory emptyManagerData;
            managerData = emptyManagerData;
        }
        collatInfo.managerData = managerData;
        emit CollateralManagerSet(collateral, managerData);
    }

    /// @inheritdoc ISetters
    function togglePause(address collateral, PauseType pausedType) external onlyGuardian {
        LibSetters.togglePause(collateral, pausedType);
    }

    /// @inheritdoc ISetters
    function toggleTrusted(address sender, uint8 trustedType) external onlyGovernor {
        KheopsStorage storage ks = s.kheopsStorage();
        uint256 trustedStatus;
        if (trustedType == 0) {
            trustedStatus = 1 - ks.isTrusted[sender];
            ks.isTrusted[sender] = trustedStatus;
        } else {
            trustedStatus = 1 - ks.isSellerTrusted[sender];
            ks.isSellerTrusted[sender] = trustedStatus;
        }
        emit TrustedToggled(sender, trustedStatus, trustedType);
    }

    /// @inheritdoc ISetters
    function addCollateral(address collateral) external onlyGovernor {
        LibSetters.addCollateral(collateral);
    }

    /// @inheritdoc ISetters
    /// @dev The amount passed here must be a normalized amount and not an absolute amount
    function adjustNormalizedStablecoins(address collateral, uint128 amount, bool addOrRemove) external onlyGovernor {
        KheopsStorage storage ks = s.kheopsStorage();
        Collateral storage collatInfo = ks.collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        if (addOrRemove) {
            collatInfo.normalizedStables += uint224(amount);
            ks.normalizedStables += amount;
        } else {
            collatInfo.normalizedStables -= uint224(amount);
            ks.normalizedStables -= amount;
        }
        emit ReservesAdjusted(collateral, amount, addOrRemove);
    }

    /// @inheritdoc ISetters
    /// @dev The system may still have a non null balance of the collateral that is revoked: this should later
    /// be handled through a recoverERC20 call
    function revokeCollateral(address collateral) external onlyGovernor {
        KheopsStorage storage ks = s.kheopsStorage();
        Collateral storage collatInfo = ks.collaterals[collateral];
        if (collatInfo.decimals == 0 || collatInfo.normalizedStables > 0) revert NotCollateral();
        uint8 isManaged = collatInfo.isManaged;
        // If the collateral is managed through strategies, pulling all available funds from there
        if (isManaged > 0) LibManager.pullAll(collatInfo.managerData);
        delete ks.collaterals[collateral];
        address[] memory collateralListMem = ks.collateralList;
        uint256 length = collateralListMem.length;
        for (uint256 i; i < length - 1; ++i) {
            if (collateralListMem[i] == collateral) {
                ks.collateralList[i] = collateralListMem[length - 1];
                break;
            }
        }
        ks.collateralList.pop();
        emit CollateralRevoked(collateral);
    }

    /// @inheritdoc ISetters
    function setFees(address collateral, uint64[] memory xFee, int64[] memory yFee, bool mint) external onlyGuardian {
        LibSetters.setFees(collateral, xFee, yFee, mint);
    }

    /// @inheritdoc ISetters
    function setRedemptionCurveParams(uint64[] memory xFee, int64[] memory yFee) external onlyGuardian {
        KheopsStorage storage ks = s.kheopsStorage();
        LibSetters.checkFees(xFee, yFee, 2);
        ks.xRedemptionCurve = xFee;
        ks.yRedemptionCurve = yFee;
        emit RedemptionCurveParamsSet(xFee, yFee);
    }

    /// @inheritdoc ISetters
    function setOracle(address collateral, bytes memory oracleConfig) external onlyGovernor {
        LibSetters.setOracle(collateral, oracleConfig);
    }

    /// @inheritdoc ISetters
    /// @dev This function may be called by trusted addresses: these could be for instance savings contract
    /// minting stablecoins when they notice a profit
    function updateNormalizer(uint256 amount, bool increase) external returns (uint256) {
        if (!LibDiamond.isGovernor(msg.sender) && s.kheopsStorage().isTrusted[msg.sender] == 0) revert NotTrusted();
        return LibRedeemer.updateNormalizer(amount, increase);
    }
}
