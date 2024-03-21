// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import { IERC20 } from "oz/interfaces/IERC20.sol";
import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";

import { IAccessControlManager } from "interfaces/IAccessControlManager.sol";
import { ISettersGovernor } from "interfaces/ISetters.sol";

import { LibManager } from "../libraries/LibManager.sol";
import { LibOracle } from "../libraries/LibOracle.sol";
import { LibSetters } from "../libraries/LibSetters.sol";
import { LibStorage as s } from "../libraries/LibStorage.sol";
import { AccessControlModifiers } from "./AccessControlModifiers.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import "../Storage.sol";

/// @title SettersGovernor
/// @author Angle Labs, Inc.
contract SettersGovernor is AccessControlModifiers, ISettersGovernor {
    using SafeERC20 for IERC20;

    event Recovered(address indexed token, address indexed to, uint256 amount);

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
    /// @dev Funds need to have been withdrawn from the eventual previous manager prior to this call
    function setCollateralManager(address collateral, ManagerStorage memory managerData) external onlyGovernor {
        LibSetters.setCollateralManager(collateral, managerData);
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
        LibSetters.toggleTrusted(sender, t);
    }

    /// @inheritdoc ISettersGovernor
    /// @dev Collateral assets with a fee on transfer are not supported by the system
    function addCollateral(address collateral) external onlyGovernor {
        LibSetters.addCollateral(collateral);
    }

    /// @inheritdoc ISettersGovernor
    /// @dev The amount passed here must be an absolute amount
    function adjustStablecoins(address collateral, uint128 amount, bool increase) external onlyGovernor {
        LibSetters.adjustStablecoins(collateral, amount, increase);
    }

    /// @inheritdoc ISettersGovernor
    /// @dev Require `collatInfo.normalizedStables == 0`, that is to say that the collateral
    /// is not used to back stables
    /// @dev The system may still have a non null balance of the collateral that is revoked: this should later
    /// be handled through a recoverERC20 call
    /// @dev Funds needs to have been withdrew from the manager prior to this call
    function revokeCollateral(address collateral) external onlyGovernor {
        LibSetters.revokeCollateral(collateral);
    }

    /// @inheritdoc ISettersGovernor
    function setOracle(address collateral, bytes memory oracleConfig) external onlyGovernor {
        LibSetters.setOracle(collateral, oracleConfig);
    }

    function updateOracle(address collateral) external {
        if (s.transmuterStorage().isSellerTrusted[msg.sender] == 0) revert NotTrusted();
        LibOracle.updateOracle(collateral);
    }

    /// @inheritdoc ISettersGovernor
    function setWhitelistStatus(
        address collateral,
        uint8 whitelistStatus,
        bytes memory whitelistData
    ) external onlyGovernor {
        LibSetters.setWhitelistStatus(collateral, whitelistStatus, whitelistData);
    }
}
