// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import "oz/token/ERC20/IERC20.sol";
import "oz/token/ERC20/utils/SafeERC20.sol";

contract MockManager {
    address public collateral;
    IERC20[] public subCollaterals;
    address public kheops;
    mapping(address => bool) public governors;
    mapping(address => bool) public guardians;

    /// @notice Transfers `amount` of `token` to the `to` address
    /// @param redeem Whether the transfer operation is part of a redemption or not. If not, this means that
    /// it's a burn or a recover and the system can try to withdraw from its strategies if it does not have
    /// funds immediately available
    function transfer(address token, address to, uint256 amount, bool redeem) external;

    function pullAll() external {}

    /// @notice Gets the balances of all the tokens controlled be the manager contract
    /// @return balances An array of size `subCollaterals` with current balances
    /// @return totalValue The sum of the balances corrected by an oracle
    function getUnderlyingBalances() external view returns (uint256[] memory balances, uint256 totalValue) {
        bool found;
        for (uint256 i; i < subCollaterals.length; ++i) {
            if (token == address(subCollaterals[i])) {
                found = true;
                break;
            }
        }
        if (!found) revert NotCollateral();
        IERC20(token).transfer(to, amount);
    }

    /// @notice Gives the maximum amount of collateral immediately available for a transfer
    function maxAvailable() external view returns (uint256) {
        return IERC20(collateral).balanceOf(kheops);
    }
}
