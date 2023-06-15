// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import { IERC20 } from "oz/token/ERC20/IERC20.sol";
import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";

import { IManager } from "interfaces/IManager.sol";

import "../Storage.sol";

/// @title LibManager
/// @author Angle Labs, Inc.
/// @dev Managed collateral assets may be handled through external smart contracts or directly through this library
/// @dev There is no implementation at this point for a managed collateral handled through this library, and
/// a new specific `ManagerType` would need to be added in this case
library LibManager {
    using SafeERC20 for IERC20;

    /// @notice Checks to which address managed funds must be transferred
    function transferRecipient(bytes memory config) internal view returns (address) {
        (ManagerType managerType, bytes memory data) = parseManagerConfig(config);
        if (managerType == ManagerType.EXTERNAL) return abi.decode(data, (address));
        return address(this);
    }

    /// @notice Invests new funds into the collateral manager
    function invest(uint256 amount, bytes memory config) internal {
        (ManagerType managerType, bytes memory data) = parseManagerConfig(config);
        if (managerType == ManagerType.EXTERNAL) abi.decode(data, (IManager)).invest(amount);
    }

    /// @notice Sends `amount` of base collateral to the `to` address
    function release(address to, uint256 amount, bytes memory config) internal {
        (ManagerType managerType, bytes memory data) = parseManagerConfig(config);
        if (managerType == ManagerType.EXTERNAL) abi.decode(data, (IManager)).release(to, amount);
    }

    /// @notice Redeem a proportion of managed funds
    function redeem(
        address to,
        uint256 proportion,
        address[] memory forfeitTokens,
        bytes memory config
    ) internal returns (address[] memory, uint256[] memory) {
        (ManagerType managerType, bytes memory data) = parseManagerConfig(config);
        if (managerType == ManagerType.EXTERNAL)
            return abi.decode(data, (IManager)).redeem(to, proportion, forfeitTokens);
        return (new address[](0), new uint256[](0));
    }

    /// @notice Redeem a proportion of managed funds
    function quoteRedeem(
        uint256 proportion,
        bytes memory config
    ) internal view returns (address[] memory, uint256[] memory) {
        (ManagerType managerType, bytes memory data) = parseManagerConfig(config);
        if (managerType == ManagerType.EXTERNAL) return abi.decode(data, (IManager)).quoteRedeem(proportion);
        return (new address[](0), new uint256[](0));
    }

    /// @notice Returns the total assets managed by the Manager, in the corresponding collateral
    function totalAssets(bytes memory config) internal view returns (uint256) {
        (ManagerType managerType, bytes memory data) = parseManagerConfig(config);
        if (managerType == ManagerType.EXTERNAL) return abi.decode(data, (IManager)).totalAssets();
        return 0;
    }

    /// @notice Decodes the `managerData` associated to a collateral
    function parseManagerConfig(
        bytes memory config
    ) internal pure returns (ManagerType managerType, bytes memory data) {
        (managerType, data) = abi.decode(config, (ManagerType, bytes));
    }
}
