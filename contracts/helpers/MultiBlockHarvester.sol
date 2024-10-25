// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IAccessControlManager } from "../utils/AccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BaseHarvester, YieldBearingParams } from "./BaseHarvester.sol";
import { ITransmuter } from "../interfaces/ITransmuter.sol";
import { IAgToken } from "../interfaces/IAgToken.sol";
import { IPool } from "../interfaces/IPool.sol";

import "../utils/Errors.sol";
import "../utils/Constants.sol";

/// @title MultiBlockHarvester
/// @author Angle Labs, Inc.
/// @dev Contract to harvest yield from multiple yield bearing assets in multiple blocks transactions
contract MultiBlockHarvester is BaseHarvester {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       VARIABLES
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice address to deposit to receive yieldBearingAsset
    mapping(address => address) public yieldBearingToDepositAddress;

    /// @notice Maximum amount of stablecoins that can be used in a single transaction
    uint256 public maxOrderAmount;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    constructor(
        uint256 initialOrderMintAmount,
        uint96 initialMaxSlippage,
        IAccessControlManager definitiveAccessControlManager,
        IAgToken definitiveAgToken,
        ITransmuter definitiveTransmuter
    ) BaseHarvester(initialMaxSlippage, definitiveAccessControlManager, definitiveAgToken, definitiveTransmuter) {
        maxOrderAmount = initialOrderMintAmount;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        GOVERNOR FUNCTIONS
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the maximum amount of stablecoins that can be used in a single transaction
     * @param newMaxOrderAmount new maximum amount of stablecoins that can be used in a single transaction
     */
    function setMaxOrderAmount(uint256 newMaxOrderAmount) external onlyGovernor {
        maxOrderAmount = newMaxOrderAmount;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        GUARDIAN FUNCTIONS
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the deposit address for a yieldBearingAsset
     * @param yieldBearingAsset address of the yieldBearingAsset
     * @param newDepositAddress address to deposit to receive yieldBearingAsset
     */
    function setYieldBearingToDepositAddress(
        address yieldBearingAsset,
        address newDepositAddress
    ) external onlyGuardian {
        yieldBearingToDepositAddress[yieldBearingAsset] = newDepositAddress;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        TRUSTED FUNCTIONS
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Initiate a rebalance
     * @param scale scale to apply to the rebalance amount
     * @param yieldBearingAsset address of the yieldBearingAsset
     */
    function harvest(address yieldBearingAsset, uint256 scale, bytes calldata) external onlyTrusted {
        if (scale > 1e9) revert InvalidParam();
        YieldBearingParams memory yieldBearingInfo = yieldBearingData[yieldBearingAsset];
        (uint8 increase, uint256 amount) = _computeRebalanceAmount(yieldBearingAsset, yieldBearingInfo);
        amount = (amount * scale) / 1e9;
        if (amount == 0) revert ZeroAmount();

        try transmuter.updateOracle(yieldBearingAsset) {} catch {}
        _rebalance(increase, yieldBearingAsset, yieldBearingInfo, amount);
    }

    /**
     * @notice Finalize a rebalance
     * @param yieldBearingAsset address of the yieldBearingAsset
     */
    function finalizeRebalance(address yieldBearingAsset, uint256 balance) external onlyTrusted {
        try transmuter.updateOracle(yieldBearingAsset) {} catch {}
        _adjustAllowance(yieldBearingAsset, address(transmuter), balance);
        uint256 amountOut = transmuter.swapExactInput(
            balance,
            0,
            yieldBearingAsset,
            address(agToken),
            address(this),
            block.timestamp
        );
        address depositAddress = yieldBearingAsset == XEVT
            ? yieldBearingToDepositAddress[yieldBearingAsset]
            : address(0);
        _checkSlippage(balance, amountOut, yieldBearingAsset, depositAddress, true);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _rebalance(
        uint8 typeAction,
        address yieldBearingAsset,
        YieldBearingParams memory yieldBearingInfo,
        uint256 amount
    ) internal {
        if (amount > maxOrderAmount) revert TooBigAmountIn();
        _adjustAllowance(address(agToken), address(transmuter), amount);
        address depositAddress = yieldBearingToDepositAddress[yieldBearingAsset];
        if (typeAction == 1) {
            uint256 amountOut = transmuter.swapExactInput(
                amount,
                0,
                address(agToken),
                yieldBearingInfo.stablecoin,
                address(this),
                block.timestamp
            );
            _checkSlippage(amount, amountOut, yieldBearingInfo.stablecoin, depositAddress, false);
            if (yieldBearingAsset == XEVT) {
                _adjustAllowance(yieldBearingInfo.stablecoin, address(depositAddress), amountOut);
                (uint256 shares, ) = IPool(depositAddress).deposit(amountOut, address(this));
                _adjustAllowance(yieldBearingAsset, address(transmuter), shares);
                amountOut = transmuter.swapExactInput(
                    shares,
                    0,
                    yieldBearingAsset,
                    address(agToken),
                    address(this),
                    block.timestamp
                );
            } else if (yieldBearingAsset == USDM) {
                IERC20(yieldBearingInfo.stablecoin).safeTransfer(depositAddress, amountOut);
            }
        } else {
            uint256 amountOut = transmuter.swapExactInput(
                amount,
                0,
                address(agToken),
                yieldBearingAsset,
                address(this),
                block.timestamp
            );
            _checkSlippage(amount, amountOut, yieldBearingAsset, depositAddress, false);
            if (yieldBearingAsset == XEVT) {
                IPool(depositAddress).requestRedeem(amountOut);
            } else if (yieldBearingAsset == USDM) {
                IERC20(yieldBearingAsset).safeTransfer(depositAddress, amountOut);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        HELPER                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _checkSlippage(
        uint256 amountIn,
        uint256 amountOut,
        address asset,
        address depositAddress,
        bool assetIn
    ) internal view {
        uint256 decimalsAsset = IERC20Metadata(asset).decimals();

        // Divide or multiply the amountIn to match the decimals of the asset
        amountIn = _scaleAmountBasedOnDecimals(decimalsAsset, 18, amountIn, assetIn);

        if (asset == USDC || asset == USDM || asset == EURC) {
            // Assume 1:1 ratio between stablecoins
            uint256 slippage = ((amountIn - amountOut) * 1e9) / amountIn;
            if (slippage > maxSlippage) revert SlippageTooHigh();
        } else if (asset == XEVT) {
            // Assume 1:1 ratio between the underlying asset of the vault
            uint256 slippage = ((IPool(depositAddress).convertToAssets(amountIn) - amountOut) * 1e9) / amountIn;
            if (slippage > maxSlippage) revert SlippageTooHigh();
        } else revert InvalidParam();
    }
}
