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
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../utils/Errors.sol";
import "../utils/Constants.sol";

/// @title MultiBlockHarvester
/// @author Angle Labs, Inc.
/// @dev Contract to harvest yield from multiple yield bearing assets in multiple blocks transactions
contract MultiBlockHarvester is BaseHarvester {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       VARIABLES
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice address to deposit to receive yieldBearingAsset
    mapping(address => address) public yieldBearingToDepositAddress;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    constructor(
        uint96 initialMaxSlippage,
        IAccessControlManager definitiveAccessControlManager,
        IAgToken definitiveAgToken,
        ITransmuter definitiveTransmuter
    ) BaseHarvester(initialMaxSlippage, definitiveAccessControlManager, definitiveAgToken, definitiveTransmuter) {}

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
        _adjustAllowance(address(agToken), address(transmuter), amount);
        address depositAddress = yieldBearingToDepositAddress[yieldBearingAsset];
        if (typeAction == 1) {
            uint256 amountOut = transmuter.swapExactInput(
                amount,
                0,
                address(agToken),
                yieldBearingInfo.asset,
                address(this),
                block.timestamp
            );
            if (yieldBearingAsset == XEVT) {
                _adjustAllowance(yieldBearingInfo.asset, address(depositAddress), amountOut);
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
                _checkSlippage(amount, amountOut, address(agToken), depositAddress, false);
            } else if (yieldBearingAsset == USDM) {
                IERC20(yieldBearingInfo.asset).safeTransfer(depositAddress, amountOut);
                _checkSlippage(amount, amountOut, yieldBearingInfo.asset, depositAddress, false);
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
        // Divide or multiply the amountIn to match the decimals of the asset
        amountIn = _scaleAmountBasedOnDecimals(IERC20Metadata(asset).decimals(), 18, amountIn, assetIn);

        uint256 result;
        if (asset == USDC || asset == USDM || asset == EURC || asset == address(agToken)) {
            // Assume 1:1 ratio between stablecoins
            (, result) = amountIn.trySub(amountOut);
        } else if (asset == XEVT) {
            // Assume 1:1 ratio between the underlying asset of the vault
            if (assetIn) {
                (, result) = IPool(depositAddress).convertToAssets(amountIn).trySub(amountOut);
            } else {
                (, result) = amountIn.trySub(IPool(depositAddress).convertToAssets(amountOut));
            }
        } else revert InvalidParam();

        uint256 slippage = (result * 1e9) / amountIn;
        if (slippage > maxSlippage) revert SlippageTooHigh();
    }
}
