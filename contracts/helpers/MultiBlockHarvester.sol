// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControl, IAccessControlManager } from "../utils/AccessControl.sol";
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
                                                       MODIFIERS
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    modifier onlyTrusted() {
        if (!isTrusted[msg.sender]) revert NotTrusted();
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       VARIABLES
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice address to deposit to receive yieldBearingAsset
    mapping(address => address) public yieldBearingToDepositAddress;
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
    ) BaseHarvester(initialMaxSlippage, definitiveAccessControlManager, definitiveAgToken, definitiveTransmuter) {
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

        try transmuter.updateOracle(yieldBearingAsset) {} catch {}
        _rebalance(increase, yieldBearingAsset, yieldBearingInfo, amount);
    }

    /**
     * @notice Finalize a rebalance
     * @param yieldBearingAsset address of the yieldBearingAsset
     */
    function finalizeRebalance(address yieldBearingAsset, uint256 balance) external onlyTrusted {
        try transmuter.updateOracle(yieldBearingAsset) {} catch {}
        _adjustAllowance(address(agToken), address(transmuter), balance);
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
        _checkSlippage(balance, amountOut, yieldBearingAsset, depositAddress);
        agToken.burnSelf(amountOut, address(this));
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
        if (amount > maxMintAmount) revert TooBigAmountIn();
        agToken.mint(address(this), amount);
        _adjustAllowance(address(agToken), address(transmuter), amount);
        if (typeAction == 1) {
            address depositAddress = yieldBearingToDepositAddress[yieldBearingAsset];

            if (yieldBearingAsset == XEVT) {
                uint256 amountOut = transmuter.swapExactInput(
                    amount,
                    0,
                    address(agToken),
                    yieldBearingInfo.stablecoin,
                    address(this),
                    block.timestamp
                );
                _checkSlippage(amount, amountOut, yieldBearingInfo.stablecoin, depositAddress);
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
                agToken.burnSelf(amountOut, address(this));
            } else if (yieldBearingAsset == USDM) {
                uint256 amountOut = transmuter.swapExactInput(
                    amount,
                    0,
                    address(agToken),
                    yieldBearingInfo.stablecoin,
                    address(this),
                    block.timestamp
                );
                _checkSlippage(amount, amountOut, yieldBearingInfo.stablecoin, depositAddress);
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
            address depositAddress = yieldBearingToDepositAddress[yieldBearingAsset];
            _checkSlippage(amount, amountOut, yieldBearingAsset, depositAddress);

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

    function _checkSlippage(uint256 amountIn, uint256 amountOut, address asset, address depositAddress) internal view {
        uint256 decimalsAsset = IERC20Metadata(asset).decimals();
        // Divide or multiply the amountIn to match the decimals of the asset
        if (decimalsAsset > 18) {
            amountIn /= 10 ** (decimalsAsset - 18);
        } else if (decimalsAsset < 18) {
            amountIn *= 10 ** (18 - decimalsAsset);
        }

        if (asset == USDC || asset == USDM) {
            // Assume 1:1 ratio between stablecoins
            uint256 slippage = ((amountIn - amountOut) * 1e9) / amountIn;
            if (slippage > maxSlippage) revert SlippageTooHigh();
        } else if (asset == XEVT) {
            // Assumer 1:1 ratio between the underlying asset of the vault
            uint256 slippage = ((IPool(depositAddress).convertToAssets(amountIn) - amountOut) * 1e9) / amountIn;
            if (slippage > maxSlippage) revert SlippageTooHigh();
        } else revert InvalidParam();
    }
}
