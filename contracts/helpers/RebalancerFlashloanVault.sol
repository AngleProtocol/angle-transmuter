// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import "./BaseRebalancerFlashloan.sol";
import { IERC4626 } from "interfaces/external/IERC4626.sol";

/// @title RebalancerFlashloanVault
/// @author Angle Labs, Inc.
/// @dev Rebalancer contract for a Transmuter with as collaterals a liquid stablecoin and an ERC4626 token
/// using this liquid stablecoin as an asset
contract RebalancerFlashloanVault is BaseRebalancerFlashloan {
    using SafeCast for uint256;

    constructor(
        IAccessControlManager _accessControlManager,
        ITransmuter _transmuter,
        IERC3156FlashLender _flashloan
    ) BaseRebalancerFlashloan(_accessControlManager, _transmuter, _flashloan) {}

    /**
     * @dev Deposit or redeem the vault asset
     * @param typeAction 1 for deposit, 2 for redeem
     * @param tokenIn address of the token to swap
     * @param tokenOut address of the token to receive
     * @param amount amount of token to swap
     */
    function _swapToTokenIn(
        uint256 typeAction,
        address tokenIn,
        address tokenOut,
        uint256 amount,
        bytes memory
    ) internal override returns (uint256 amountOut) {
        if (typeAction == 1) {
            // Granting allowance with the collateral for the vault asset
            _adjustAllowance(tokenOut, tokenIn, amount);
            amountOut = IERC4626(tokenIn).deposit(amount, address(this));
        } else amountOut = IERC4626(tokenOut).redeem(amount, address(this), address(this));
    }
}
