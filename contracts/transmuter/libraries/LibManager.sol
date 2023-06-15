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
    function transferRecipient(bytes memory config) internal view returns (address recipient) {
        (ManagerType managerType, bytes memory data) = parseManagerConfig(config);
        recipient = address(this);
        if (managerType == ManagerType.EXTERNAL) return abi.decode(data, (address));
    }

    /// @notice Performs a transfer of `token` for a collateral that is managed to a `to` address
    /// @dev `token` may not be the actual collateral itself, as some collaterals have subcollaterals associated
    /// with it
    /// @dev Eventually pulls funds from strategies
    function transferTo(address token, address to, uint256 amount, bytes memory config) internal {
        (ManagerType managerType, bytes memory data) = parseManagerConfig(config);
        if (managerType == ManagerType.EXTERNAL) abi.decode(data, (IManager)).transferTo(token, to, amount);
    }

    /// @notice Performs a collateral transfer from `msg.sender` to an address depending on the type of
    /// manager considered
    function transferFrom(address token, uint256 amount, bytes memory config) internal {
        (ManagerType managerType, bytes memory data) = parseManagerConfig(config);
        if (managerType == ManagerType.EXTERNAL)
            IERC20(token).safeTransferFrom(msg.sender, address(abi.decode(data, (IManager))), amount);
    }

    /// @notice Tries to remove all funds from the strategies associated to `managerData`
    function pullAll(bytes memory config) internal {
        (ManagerType managerType, bytes memory data) = parseManagerConfig(config);
        if (managerType == ManagerType.EXTERNAL) abi.decode(data, (IManager)).pullAll();
    }

    /// @notice Gets the balances of all the tokens controlled through `managerData`
    /// @return balances An array of size `subCollaterals` with current balances of all subCollaterals
    /// including the one corresponding to the `managerData` given
    /// @return totalValue The value of the `subCollaterals` (excluding the collateral used within Transmuter)
    /// @dev `subCollaterals` must always have as first token (index 0) the collateral itself
    function getUnderlyingBalances(
        bytes memory config
    ) internal view returns (uint256[] memory balances, uint256 totalValue) {
        (ManagerType managerType, bytes memory data) = parseManagerConfig(config);
        if (managerType == ManagerType.EXTERNAL) return abi.decode(data, (IManager)).getUnderlyingBalances();
    }

    /// @notice Returns available underlying tokens, for instance if liquidity is fully used and
    /// not withdrawable the function will return 0
    function maxAvailable(bytes memory config) internal view returns (uint256 available) {
        (ManagerType managerType, bytes memory data) = parseManagerConfig(config);
        if (managerType == ManagerType.EXTERNAL) return abi.decode(data, (IManager)).maxAvailable();
    }

    /// @notice Decodes the `managerData` associated to a collateral
    function parseManagerConfig(
        bytes memory config
    ) internal pure returns (ManagerType managerType, bytes memory data) {
        (managerType, data) = abi.decode(config, (ManagerType, bytes));
    }
}
