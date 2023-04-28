// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../Storage.sol";

/// @title LibManager
/// @author Angle Labs
/// @notice Library sed for by `Manager` contracts
library LibManager {
    using SafeERC20 for IERC20;

    // Should implement this function to transfer underlying tokens to the right address
    // The facet itself will handle itself how to free the funds necessary
    // @param collateral Helps find the manager storage
    // @param token Is the actual token we want to send
    // TODO add element potentially for a refund or not
    function transfer(address collateral, address token, address to, uint256 amount, bool revertIfNotEnough) internal {}

    /// @notice Try to remove all funds from the manager, except the underlying as reserves can handle it
    /// @param force Whether to force the pull and abandon the funds if it can't be recovered
    function pullAll(address token, bool force) internal {}

    /// @notice Get all the token balances owned by the manager
    /// @return balances An array of size `subCollaterals` with current balances
    /// @return totalValue The sum of the balances corrected by an oracle
    function getUnderlyingBalances(
        ManagerStorage memory managerStorage
    ) internal view returns (uint256[] memory balances, uint256 totalValue) {}

    /// @notice Return available underlying tokens, for instanc if liquidity fully used and
    /// not withdrawable the function will return 0
    function maxAvailable(address token) internal view returns (uint256) {}
}
