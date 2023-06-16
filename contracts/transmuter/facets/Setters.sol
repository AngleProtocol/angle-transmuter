// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import { SafeCast } from "oz/utils/math/SafeCast.sol";
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
import { LibWhitelist } from "../libraries/LibWhitelist.sol";
import { AccessControlModifiers } from "./AccessControlModifiers.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import "../Storage.sol";

/// @title Setters
/// @author Angle Labs, Inc.
contract Setters is AccessControlModifiers, ISetters {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    event CollateralManagerSet(address indexed collateral, ManagerStorage managerData);
    event CollateralRevoked(address indexed collateral);
    event ManagerDataSet(address indexed collateral, ManagerStorage managerData);
    event Recovered(address indexed token, address indexed to, uint256 amount);
    event RedemptionCurveParamsSet(uint64[] xFee, int64[] yFee);
    event ReservesAdjusted(address indexed collateral, uint256 amount, bool increase);
    event TrustedToggled(address indexed sender, bool isTrusted, TrustedType trustedType);
    event WhitelistStatusToggled(WhitelistType whitelistType, address indexed who, uint256 whitelistStatus);

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                  GUARDIAN FUNCTIONS                                                
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISetters
    function togglePause(address collateral, ActionType pausedType) external onlyGuardian {
        LibSetters.togglePause(collateral, pausedType);
    }

    /// @inheritdoc ISetters
    function setFees(address collateral, uint64[] memory xFee, int64[] memory yFee, bool mint) external onlyGuardian {
        LibSetters.setFees(collateral, xFee, yFee, mint);
    }

    /// @inheritdoc ISetters
    function setRedemptionCurveParams(uint64[] memory xFee, int64[] memory yFee) external onlyGuardian {
        TransmuterStorage storage ks = s.transmuterStorage();
        LibSetters.checkFees(xFee, yFee, ActionType.Redeem);
        ks.xRedemptionCurve = xFee;
        ks.yRedemptionCurve = yFee;
        emit RedemptionCurveParamsSet(xFee, yFee);
    }

    /// @inheritdoc ISetters
    function toggleWhitelist(WhitelistType whitelistType, address who) external onlyGuardian {
        TransmuterStorage storage ks = s.transmuterStorage();
        uint256 whitelistStatus = 1 - ks.isWhitelistedForType[whitelistType][who];
        ks.isWhitelistedForType[whitelistType][who] = whitelistStatus;
        emit WhitelistStatusToggled(whitelistType, who, whitelistStatus);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                  GOVERNOR FUNCTIONS                                                
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISetters
    /// @dev No check is made on the collateral that is redeemed: this function could typically be used by a
    /// governance during a manual rebalance of the reserves of the system
    /// @dev `collateral` is different from `token` only in the case of a managed collateral
    function recoverERC20(address collateral, IERC20 token, address to, uint256 amount) external onlyGovernor {
        Collateral storage collatInfo = s.transmuterStorage().collaterals[collateral];
        if (collatInfo.isManaged > 0) LibManager.transferTo(address(token), to, amount, collatInfo.managerData.config);
        else token.safeTransfer(to, amount);
        emit Recovered(address(token), to, amount);
    }

    /// @inheritdoc ISetters
    function setAccessControlManager(address _newAccessControlManager) external onlyGovernor {
        LibSetters.setAccessControlManager(IAccessControlManager(_newAccessControlManager));
    }

    /// @inheritdoc ISetters
    function setCollateralManager(address collateral, ManagerStorage memory managerData) external onlyGovernor {
        Collateral storage collatInfo = s.transmuterStorage().collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        uint8 isManaged = collatInfo.isManaged;
        if (isManaged > 0) LibManager.pullAll(collatInfo.managerData.config);
        if (managerData.config.length != 0) {
            // The first subCollateral given should be the actual collateral asset
            if (address(managerData.subCollaterals[0]) != collateral) revert InvalidParams();
            // Sanity check on the manager data that is passed
            LibManager.parseManagerConfig(managerData.config);
            collatInfo.isManaged = 1;
        } else collatInfo.isManaged = 0;
        collatInfo.managerData = managerData;
        emit CollateralManagerSet(collateral, managerData);
    }

    /// @inheritdoc ISetters
    /// @dev This function can typically be used to grant allowance to a newly added manager for it to pull the
    /// funds associated to the collateral it corresponds to
    function changeAllowance(IERC20 token, address spender, uint256 amount) external onlyGovernor {
        uint256 currentAllowance = token.allowance(address(this), spender);
        if (currentAllowance < amount) {
            token.safeIncreaseAllowance(spender, amount - currentAllowance);
        } else if (currentAllowance > amount) {
            token.safeDecreaseAllowance(spender, currentAllowance - amount);
        }
    }

    /// @inheritdoc ISetters
    function toggleTrusted(address sender, TrustedType t) external onlyGovernor {
        TransmuterStorage storage ks = s.transmuterStorage();
        uint256 trustedStatus;
        if (t == TrustedType.Updater) {
            trustedStatus = 1 - ks.isTrusted[sender];
            ks.isTrusted[sender] = trustedStatus;
        } else {
            trustedStatus = 1 - ks.isSellerTrusted[sender];
            ks.isSellerTrusted[sender] = trustedStatus;
        }
        emit TrustedToggled(sender, trustedStatus == 1, t);
    }

    /// @inheritdoc ISetters
    function addCollateral(address collateral) external onlyGovernor {
        LibSetters.addCollateral(collateral);
    }

    /// @inheritdoc ISetters
    /// @dev The amount passed here must be an absolute amount
    function adjustStablecoins(address collateral, uint128 amount, bool increase) external onlyGovernor {
        TransmuterStorage storage ks = s.transmuterStorage();
        Collateral storage collatInfo = ks.collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        uint128 normalizedAmount = ((amount * BASE_27) / ks.normalizer).toUint128();
        if (increase) {
            collatInfo.normalizedStables += uint216(normalizedAmount);
            ks.normalizedStables += normalizedAmount;
        } else {
            collatInfo.normalizedStables -= uint216(normalizedAmount);
            ks.normalizedStables -= normalizedAmount;
        }
        emit ReservesAdjusted(collateral, amount, increase);
    }

    /// @inheritdoc ISetters
    /// @dev Require `collatInfo.normalizedStables == 0`, that is to say that the collateral
    /// is not used to back stables
    /// @dev The system may still have a non null balance of the collateral that is revoked: this should later
    /// be handled through a recoverERC20 call
    function revokeCollateral(address collateral) external onlyGovernor {
        TransmuterStorage storage ks = s.transmuterStorage();
        Collateral storage collatInfo = ks.collaterals[collateral];
        if (collatInfo.decimals == 0 || collatInfo.normalizedStables > 0) revert NotCollateral();
        uint8 isManaged = collatInfo.isManaged;
        // If the collateral is managed through strategies, pulling all available funds from there
        if (isManaged > 0) LibManager.pullAll(collatInfo.managerData.config);
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
    function setOracle(address collateral, bytes memory oracleConfig) external onlyGovernor {
        LibSetters.setOracle(collateral, oracleConfig);
    }

    /// @inheritdoc ISetters
    function setWhitelistStatus(
        address collateral,
        uint8 whitelistStatus,
        bytes memory whitelistData
    ) external onlyGovernor {
        LibSetters.setWhitelistStatus(collateral, whitelistStatus, whitelistData);
    }

    /// @inheritdoc ISetters
    /// @dev This function may be called by trusted addresses: these could be for instance savings contract
    /// minting stablecoins when they notice a profit
    function updateNormalizer(uint256 amount, bool increase) external returns (uint256) {
        if (!LibDiamond.isGovernor(msg.sender) && s.transmuterStorage().isTrusted[msg.sender] == 0) revert NotTrusted();
        return LibRedeemer.updateNormalizer(amount, increase);
    }
}
