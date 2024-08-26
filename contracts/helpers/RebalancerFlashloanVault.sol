// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import "./ARebalancerFlashloan.sol";
import { IERC4626 } from "interfaces/external/IERC4626.sol";

/// @title RebalancerFlashloanVault
/// @author Angle Labs, Inc.
/// @dev Rebalancer contract for a Transmuter with as collaterals a liquid stablecoin and an ERC4626 token
/// using this liquid stablecoin as an asset
contract RebalancerFlashloanVault is ARebalancerFlashloan {
    using SafeCast for uint256;

    constructor(
        IAccessControlManager _accessControlManager,
        ITransmuter _transmuter,
        IERC3156FlashLender _flashloan
    ) ARebalancerFlashloan(_accessControlManager, _transmuter, _flashloan) {}

    /// @inheritdoc IERC3156FlashBorrower
    function onFlashLoan(
        address initiator,
        address,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) public override returns (bytes32) {
        if (msg.sender != address(FLASHLOAN) || initiator != address(this) || fee != 0) revert NotTrusted();
        (uint256 typeAction, address collateral, address vault, uint256 minAmountOut, ) = abi.decode(
            data,
            (uint256, address, address, uint256, bytes)
        );
        address tokenOut;
        address tokenIn;
        if (typeAction == 1) {
            // Increase yield exposure action: we bring in the ERC4626 token
            tokenOut = collateral;
            tokenIn = vault;
        } else {
            // Decrease yield exposure action: we bring in the liquid asset
            tokenIn = collateral;
            tokenOut = vault;
        }
        uint256 amountOut = TRANSMUTER.swapExactInput(amount, 0, AGTOKEN, tokenOut, address(this), block.timestamp);
        if (typeAction == 1) {
            // Granting allowance with the collateral for the vault asset
            _adjustAllowance(collateral, vault, amountOut);
            amountOut = IERC4626(vault).deposit(amountOut, address(this));
        } else amountOut = IERC4626(vault).redeem(amountOut, address(this), address(this));
        _adjustAllowance(tokenIn, address(TRANSMUTER), amountOut);
        uint256 amountStableOut = TRANSMUTER.swapExactInput(
            amountOut,
            minAmountOut,
            tokenIn,
            AGTOKEN,
            address(this),
            block.timestamp
        );
        if (amount > amountStableOut) {
            uint256 subsidy = amount - amountStableOut;
            orders[tokenIn][tokenOut].subsidyBudget -= subsidy.toUint112();
            budget -= subsidy;
            emit SubsidyPaid(tokenIn, tokenOut, subsidy);
        }
        return CALLBACK_SUCCESS;
    }
}
