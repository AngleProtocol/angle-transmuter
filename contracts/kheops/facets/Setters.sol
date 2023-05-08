// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Diamond } from "../libraries/Diamond.sol";

import { IAccessControlManager } from "../../interfaces/IAccessControlManager.sol";

import { LibStorage as s } from "../libraries/LibStorage.sol";
import { LibManager } from "../libraries/LibManager.sol";
import { LibSetters } from "../libraries/LibSetters.sol";
import { LibHelper } from "../libraries/LibHelper.sol";
import { LibRedeemer } from "../libraries/LibRedeemer.sol";
import { AccessControlModifiers } from "../utils/AccessControlModifiers.sol";
import "../../utils/Constants.sol";
import "../../utils/Errors.sol";

import "../Storage.sol";

import { ISetters } from "../interfaces/ISetters.sol";

/// @title Setters
/// @author Angle Labs, Inc.
contract Setters is AccessControlModifiers, ISetters {
    using SafeERC20 for IERC20;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @inheritdoc ISetters
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

    /// @inheritdoc ISetters
    function setAccessControlManager(address _newAccessControlManager) external onlyGovernor {
        LibSetters.setAccessControlManager(IAccessControlManager(_newAccessControlManager));
    }

    /// @inheritdoc ISetters
    function setCollateralManager(address collateral, address manager) external onlyGovernor {
        Collateral storage collatInfo = s.kheopsStorage().collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        uint8 hasManager = collatInfo.hasManager;
        if (hasManager > 0) LibManager.pullAll(collateral, false);
        if (manager != address(0)) collatInfo.hasManager = 1;
    }

    /// @inheritdoc ISetters
    function togglePause(address collateral, PauseType pausedType) external onlyGuardian {
        LibSetters.togglePause(collateral, pausedType);
    }

    /// @inheritdoc ISetters
    function toggleTrusted(address sender) external onlyGovernor {
        KheopsStorage storage ks = s.kheopsStorage();
        uint256 trustedStatus = 1 - ks.isTrusted[sender];
        ks.isTrusted[sender] = trustedStatus;
    }

    /// @inheritdoc ISetters
    function toggleSellerTrusted(address seller) external onlyGovernor {
        KheopsStorage storage ks = s.kheopsStorage();
        uint256 trustedStatus = 1 - ks.isSellerTrusted[seller];
        ks.isSellerTrusted[seller] = trustedStatus;
    }

    /// @inheritdoc ISetters
    function addCollateral(address collateral) external onlyGovernor {
        LibSetters.addCollateral(collateral);
    }

    /// @inheritdoc ISetters
    /// @dev amount is an absolute amount (like not normalized) -> need to pay attention to this
    /// Why not normalising directly here? easier for Governance
    function adjustReserve(address collateral, uint256 amount, bool addOrRemove) external onlyGovernor {
        KheopsStorage storage ks = s.kheopsStorage();
        Collateral storage collatInfo = ks.collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        if (addOrRemove) {
            collatInfo.normalizedStables += amount;
            ks.normalizedStables += amount;
        } else {
            collatInfo.normalizedStables -= amount;
            ks.normalizedStables -= amount;
        }
    }

    /// @inheritdoc ISetters
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
    }

    /// @inheritdoc ISetters
    function setOracle(address collateral, bytes memory oracleConfig) external onlyGovernor {
        LibSetters.setOracle(collateral, oracleConfig);
    }

    /// @inheritdoc ISetters
    function updateNormalizer(uint256 amount, bool increase) external returns (uint256) {
        // Trusted addresses can call the function (like a savings contract in the case of a LSD)
        if (!Diamond.isGovernor(msg.sender) && s.kheopsStorage().isTrusted[msg.sender] == 0) revert NotTrusted();
        return LibRedeemer.updateNormalizer(amount, increase);
    }
}
