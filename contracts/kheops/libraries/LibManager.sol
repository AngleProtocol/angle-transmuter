// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { IManager } from "interfaces/IManager.sol";

import "../Storage.sol";

/// @title LibManager
/// @author Angle Labs, Inc.
/// @dev Managed collateral assets may be handled through external smart contracts or directly through this library
/// @dev There is no implementation at this point for a managed collateral handled through this library
library LibManager {
    /// @notice Performs a transfer of `token` for a collateral that is managed to a `to` address
    /// @dev `token` may not be the actual collateral itself, as some collaterals have subcollaterals associated
    /// with it
    function transfer(
        address token,
        address to,
        uint256 amount,
        bool redeem,
        ManagerStorage memory managerData
    ) internal {
        (ManagerType managerType, bytes memory data) = _parseManagerData(managerData);
        if (managerType == ManagerType.EXTERNAL) abi.decode(data, (IManager)).transfer(token, to, amount, redeem);
    }

    /// @notice Tries to remove all funds from the strategies associated to `managerData`
    function pullAll(ManagerStorage memory managerData) internal {
        (ManagerType managerType, bytes memory data) = _parseManagerData(managerData);
        if (managerType == ManagerType.EXTERNAL) abi.decode(data, (IManager)).pullAll();
    }

    /// @notice Gets the balances of all the tokens controlled through `managerData`
    /// @return balances An array of size `subCollaterals` with current balances
    /// @return totalValue The sum of the balances corrected by an oracle
    /// @dev 'subCollaterals' must always have as first token the collateral itself
    function getUnderlyingBalances(
        ManagerStorage memory managerData
    ) internal view returns (uint256[] memory balances, uint256 totalValue) {
        (ManagerType managerType, bytes memory data) = _parseManagerData(managerData);
        if (managerType == ManagerType.EXTERNAL) return abi.decode(data, (IManager)).getUnderlyingBalances();
    }

    /// @notice Returns available underlying tokens, for instance if liquidity fully used and
    /// not withdrawable the function will return 0
    function maxAvailable(ManagerStorage memory managerData) internal view returns (uint256 available) {
        (ManagerType managerType, bytes memory data) = _parseManagerData(managerData);
        if (managerType == ManagerType.EXTERNAL) return abi.decode(data, (IManager)).maxAvailable();
    }

    /// @notice Decodes the `managerData` associated to a collateral
    function _parseManagerData(
        ManagerStorage memory managerData
    ) private pure returns (ManagerType managerType, bytes memory data) {
        (managerType, data) = abi.decode(managerData.managerConfig, (ManagerType, bytes));
    }
}
