// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControl, IAccessControlManager } from "../utils/AccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BaseRebalancer, CollatParams } from "./BaseRebalancer.sol";
import { ITransmuter } from "../interfaces/ITransmuter.sol";
import { IAgToken } from "../interfaces/IAgToken.sol";
import { IPool } from "../interfaces/IPool.sol";

import "../utils/Errors.sol";
import "../utils/Constants.sol";

contract MultiBlockRebalancer is BaseRebalancer {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       MODIFIERS
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    modifier onlyTrusted() {
        if (!isTrusted[msg.sender]) revert NotTrusted();
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       VARIABLES
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice address to deposit to receive collateral
    mapping(address => address) public collateralToDepositAddress;
    /// @notice trusted addresses
    mapping(address => bool) public isTrusted;

    /// @notice Maximum amount of stablecoins that can be minted in a single transaction
    uint256 public maxMintAmount;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    constructor(
        uint256 initialMaxMintAmount,
        uint96 initialMaxSlippage,
        IAccessControlManager definitiveAccessControlManager,
        IAgToken definitiveAgToken,
        ITransmuter definitiveTransmuter
    ) BaseRebalancer(initialMaxSlippage, definitiveAccessControlManager, definitiveAgToken, definitiveTransmuter) {
        maxMintAmount = initialMaxMintAmount;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        GOVERNOR FUNCTIONS
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the maximum amount of stablecoins that can be minted in a single transaction
     * @param newMaxMintAmount new maximum amount of stablecoins that can be minted in a single transaction
     */
    function setMaxMintAmount(uint256 newMaxMintAmount) external onlyGovernor {
        maxMintAmount = newMaxMintAmount;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        GUARDIAN FUNCTIONS
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the deposit address for a collateral
     * @param collateral address of the collateral
     * @param newDepositAddress address to deposit to receive collateral
     */
    function setCollateralToDepositAddress(address collateral, address newDepositAddress) external onlyGuardian {
        collateralToDepositAddress[collateral] = newDepositAddress;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        TRUSTED FUNCTIONS
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Initiate a rebalance
     * @param scale scale to apply to the rebalance amount
     * @param collateral address of the collateral
     */
    function initiateRebalance(uint256 scale, address collateral) external onlyTrusted {
        if (scale > 1e9) revert InvalidParam();
        CollatParams memory collatInfo = collateralData[collateral];
        (uint8 increase, uint256 amount) = _computeRebalanceAmount(collateral, collatInfo);
        amount = (amount * scale) / 1e9;

        try transmuter.updateOracle(collateral) {} catch {}
        _rebalance(increase, collateral, amount);
    }

    /**
     * @notice Finalize a rebalance
     * @param collateral address of the collateral
     */
    function finalizeRebalance(address collateral, uint256 balance) external onlyTrusted {
        try transmuter.updateOracle(collateral) {} catch {}
        _adjustAllowance(address(agToken), address(transmuter), balance);
        uint256 amountOut = transmuter.swapExactInput(
            balance,
            0,
            collateral,
            address(agToken),
            address(this),
            block.timestamp
        );
        address depositAddress = collateral == XEVT ? collateralToDepositAddress[collateral] : address(0);
        _checkSlippage(balance, amountOut, collateral, depositAddress);
        agToken.burnSelf(amountOut, address(this));
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _rebalance(uint8 typeAction, address collateral, uint256 amount) internal {
        if (amount > maxMintAmount) revert TooBigAmountIn();
        agToken.mint(address(this), amount);
        _adjustAllowance(address(agToken), address(transmuter), amount);
        if (typeAction == 1) {
            address depositAddress = collateralToDepositAddress[collateral];

            if (collateral == XEVT) {
                uint256 amountOut = transmuter.swapExactInput(
                    amount,
                    0,
                    address(agToken),
                    EURC,
                    address(this),
                    block.timestamp
                );
                _checkSlippage(amount, amountOut, collateral, depositAddress);
                _adjustAllowance(collateral, address(depositAddress), amountOut);
                (uint256 shares, ) = IPool(depositAddress).deposit(amountOut, address(this));
                _adjustAllowance(collateral, address(transmuter), shares);
                amountOut = transmuter.swapExactInput(
                    shares,
                    0,
                    collateral,
                    address(agToken),
                    address(this),
                    block.timestamp
                );
                agToken.burnSelf(amountOut, address(this));
            } else if (collateral == USDM) {
                uint256 amountOut = transmuter.swapExactInput(
                    amount,
                    0,
                    address(agToken),
                    USDC,
                    address(this),
                    block.timestamp
                );
                _checkSlippage(amount, amountOut, collateral, depositAddress);
                IERC20(collateral).safeTransfer(depositAddress, amountOut);
            }
        } else {
            uint256 amountOut = transmuter.swapExactInput(
                amount,
                0,
                address(agToken),
                collateral,
                address(this),
                block.timestamp
            );
            address depositAddress = collateralToDepositAddress[collateral];
            _checkSlippage(amount, amountOut, collateral, depositAddress);

            if (collateral == XEVT) {
                IPool(depositAddress).requestRedeem(amountOut);
            } else if (collateral == USDM) {
                IERC20(collateral).safeTransfer(depositAddress, amountOut);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        HELPER                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _checkSlippage(
        uint256 amountIn,
        uint256 amountOut,
        address collateral,
        address depositAddress
    ) internal view {
        if (collateral == USDC || collateral == USDM) {
            // Assume 1:1 ratio between stablecoins
            uint256 slippage = ((amountIn - amountOut) * 1e9) / amountIn;
            if (slippage > maxSlippage) revert SlippageTooHigh();
        } else if (collateral == XEVT) {
            // Assumer 1:1 ratio between the underlying asset of the vault
            uint256 slippage = ((IPool(depositAddress).convertToAssets(amountIn) - amountOut) * 1e9) / amountIn;
            if (slippage > maxSlippage) revert SlippageTooHigh();
        } else revert InvalidParam();
    }
}
