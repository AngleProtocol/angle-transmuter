// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import { SafeCast } from "oz/utils/math/SafeCast.sol";
import { IERC20 } from "oz/interfaces/IERC20.sol";
import { IERC20Metadata } from "oz/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";

import { IAccessControlManager } from "interfaces/IAccessControlManager.sol";
import { ISettersGovernor } from "interfaces/ISetters.sol";

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

/// @title SettersGovernor
/// @author Angle Labs, Inc.
contract SettersGovernor is AccessControlModifiers, ISettersGovernor {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    event CollateralManagerSet(address indexed collateral, ManagerStorage managerData);
    event CollateralRevoked(address indexed collateral);
    event Recovered(address indexed token, address indexed to, uint256 amount);
    event ReservesAdjusted(address indexed collateral, uint256 amount, bool increase);
    event TrustedToggled(address indexed sender, bool isTrusted, TrustedType trustedType);

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                  GOVERNOR FUNCTIONS                                                
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISettersGovernor
    /// @dev No check is made on the collateral that is redeemed: this function could typically be used by a
    /// governance during a manual rebalance of the reserves of the system
    /// @dev `collateral` is different from `token` only in the case of a managed collateral
    function recoverERC20(address collateral, IERC20 token, address to, uint256 amount) external onlyGovernor {
        Collateral storage collatInfo = s.transmuterStorage().collaterals[collateral];
        if (collatInfo.isManaged > 0) LibManager.release(address(token), to, amount, collatInfo.managerData.config);
        else token.safeTransfer(to, amount);
        emit Recovered(address(token), to, amount);
    }

    /// @inheritdoc ISettersGovernor
    function setAccessControlManager(address _newAccessControlManager) external onlyGovernor {
        LibSetters.setAccessControlManager(IAccessControlManager(_newAccessControlManager));
    }

    /// @inheritdoc ISettersGovernor
    /// @dev Funds needs to have been withdrew from the eventual previous manager prior to this call
    function setCollateralManager(address collateral, ManagerStorage memory managerData) external onlyGovernor {
        Collateral storage collatInfo = s.transmuterStorage().collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        uint8 isManaged = collatInfo.isManaged;
        if (isManaged > 0) {
            (, uint256 totalValue) = LibManager.totalAssets(collatInfo.managerData.config);
            if (totalValue > 0) revert ManagerHasAssets();
        }
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

    /// @inheritdoc ISettersGovernor
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

    /// @inheritdoc ISettersGovernor
    function toggleTrusted(address sender, TrustedType t) external onlyGovernor {
        TransmuterStorage storage ts = s.transmuterStorage();
        uint256 trustedStatus;
        if (t == TrustedType.Updater) {
            trustedStatus = 1 - ts.isTrusted[sender];
            ts.isTrusted[sender] = trustedStatus;
        } else {
            trustedStatus = 1 - ts.isSellerTrusted[sender];
            ts.isSellerTrusted[sender] = trustedStatus;
        }
        emit TrustedToggled(sender, trustedStatus == 1, t);
    }

    /// @inheritdoc ISettersGovernor
    function addCollateral(address collateral) external onlyGovernor {
        LibSetters.addCollateral(collateral);
    }

    /// @inheritdoc ISettersGovernor
    /// @dev The amount passed here must be an absolute amount
    function adjustStablecoins(address collateral, uint128 amount, bool increase) external onlyGovernor {
        TransmuterStorage storage ts = s.transmuterStorage();
        Collateral storage collatInfo = ts.collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        uint128 normalizedAmount = ((amount * BASE_27) / ts.normalizer).toUint128();
        if (increase) {
            collatInfo.normalizedStables += uint216(normalizedAmount);
            ts.normalizedStables += normalizedAmount;
        } else {
            collatInfo.normalizedStables -= uint216(normalizedAmount);
            ts.normalizedStables -= normalizedAmount;
        }
        emit ReservesAdjusted(collateral, amount, increase);
    }

    /// @inheritdoc ISettersGovernor
    /// @dev Require `collatInfo.normalizedStables == 0`, that is to say that the collateral
    /// is not used to back stables
    /// @dev The system may still have a non null balance of the collateral that is revoked: this should later
    /// be handled through a recoverERC20 call
    /// @dev Funds needs to have been withdrew from the manager prior to this call
    function revokeCollateral(address collateral) external onlyGovernor {
        TransmuterStorage storage ts = s.transmuterStorage();
        Collateral storage collatInfo = ts.collaterals[collateral];
        if (collatInfo.decimals == 0 || collatInfo.normalizedStables > 0) revert NotCollateral();
        uint8 isManaged = collatInfo.isManaged;
        if (isManaged > 0) {
            (, uint256 totalValue) = LibManager.totalAssets(collatInfo.managerData.config);
            if (totalValue > 0) revert ManagerHasAssets();
        }
        delete ts.collaterals[collateral];
        address[] memory collateralListMem = ts.collateralList;
        uint256 length = collateralListMem.length;
        for (uint256 i; i < length - 1; ++i) {
            if (collateralListMem[i] == collateral) {
                ts.collateralList[i] = collateralListMem[length - 1];
                break;
            }
        }
        ts.collateralList.pop();
        emit CollateralRevoked(collateral);
    }

    /// @inheritdoc ISettersGovernor
    function setOracle(address collateral, bytes memory oracleConfig) external onlyGovernor {
        LibSetters.setOracle(collateral, oracleConfig);
    }

    /// @inheritdoc ISettersGovernor
    function setWhitelistStatus(
        address collateral,
        uint8 whitelistStatus,
        bytes memory whitelistData
    ) external onlyGovernor {
        LibSetters.setWhitelistStatus(collateral, whitelistStatus, whitelistData);
    }

    /// @inheritdoc ISettersGovernor
    /// @dev This function may be called by trusted addresses: these could be for instance savings contract
    /// minting stablecoins when they notice a profit
    function updateNormalizer(uint256 amount, bool increase) external returns (uint256) {
        if (!LibDiamond.isGovernor(msg.sender) && s.transmuterStorage().isTrusted[msg.sender] == 0) revert NotTrusted();
        return LibRedeemer.updateNormalizer(amount, increase);
    }
}
