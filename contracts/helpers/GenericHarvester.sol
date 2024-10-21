// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

import { SafeCast } from "oz/utils/math/SafeCast.sol";
import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "oz/interfaces/IERC20.sol";
import { IERC20Metadata } from "oz/interfaces/IERC20Metadata.sol";

import { ITransmuter } from "interfaces/ITransmuter.sol";
import { IAgToken } from "interfaces/IAgToken.sol";
import { RouterSwapper } from "utils/src/RouterSwapper.sol";

import { IAccessControlManager } from "../utils/AccessControl.sol";
import "../utils/Constants.sol";
import "../utils/Errors.sol";

import { IERC3156FlashBorrower } from "oz/interfaces/IERC3156FlashBorrower.sol";
import { IERC3156FlashLender } from "oz/interfaces/IERC3156FlashLender.sol";
import { IERC4626 } from "interfaces/external/IERC4626.sol";
import { BaseHarvester, YieldBearingParams } from "./BaseHarvester.sol";

enum SwapType {
    VAULT,
    SWAP
}

/// @title GenericHarvester
/// @author Angle Labs, Inc.
/// @dev Generic contract for anyone to permissionlessly adjust the reserves of Angle Transmuter
contract GenericHarvester is BaseHarvester, IERC3156FlashBorrower, RouterSwapper {
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    /// @notice Angle stablecoin flashloan contract
    IERC3156FlashLender public immutable flashloan;
    /// @notice Maximum slippage for swaps
    uint32 public maxSwapSlippage;
    /// @notice Budget of AGToken available for each users
    mapping(address => uint256) public budget;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    INITIALIZATION                                                  
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    constructor(
        uint96 initialMaxSlippage,
        address initialTokenTransferAddress,
        address initialSwapRouter,
        uint32 initialMaxSwapSlippage,
        IAgToken definitiveAgToken,
        ITransmuter definitiveTransmuter,
        IAccessControlManager definitiveAccessControlManager,
        IERC3156FlashLender definitiveFlashloan
    )
        RouterSwapper(initialSwapRouter, initialTokenTransferAddress)
        BaseHarvester(initialMaxSlippage, definitiveAccessControlManager, definitiveAgToken, definitiveTransmuter)
    {
        if (address(definitiveFlashloan) == address(0)) revert ZeroAddress();
        flashloan = definitiveFlashloan;

        IERC20(agToken).safeApprove(address(definitiveFlashloan), type(uint256).max);
        maxSwapSlippage = initialMaxSwapSlippage;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        REBALANCE                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Burns `amountStablecoins` for one yieldBearing asset, swap for asset then mints stablecoins
    /// from the proceeds of the swap.
    /// @dev If `increase` is 1, then the system tries to increase its exposure to the yield bearing asset which means
    /// burning stablecoin for the liquid stablecoin, swapping for the yield bearing asset, then minting the stablecoin
    /// @dev This function reverts if the second stablecoin mint gives less than `minAmountOut` of stablecoins
    /// @dev This function reverts if the swap slippage is higher than `maxSlippage`
    function adjustYieldExposure(
        uint256 amountStablecoins,
        uint8 increase,
        address yieldBearingAsset,
        address stablecoin,
        uint256 minAmountOut,
        SwapType swapType,
        bytes memory extraData
    ) public virtual {
        flashloan.flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(agToken),
            amountStablecoins,
            abi.encode(msg.sender, increase, yieldBearingAsset, stablecoin, minAmountOut, swapType, extraData)
        );
    }

    /// @inheritdoc IERC3156FlashBorrower
    function onFlashLoan(
        address initiator,
        address,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) public virtual returns (bytes32) {
        if (msg.sender != address(flashloan) || initiator != address(this) || fee != 0) revert NotTrusted();
        address sender;
        uint256 typeAction;
        uint256 minAmountOut;
        SwapType swapType;
        bytes memory callData;
        address tokenOut;
        address tokenIn;
        {
            address yieldBearingAsset;
            address stablecoin;
            (sender, typeAction, yieldBearingAsset, stablecoin, minAmountOut, swapType, callData) = abi.decode(
                data,
                (address, uint256, address, address, uint256, SwapType, bytes)
            );
            if (typeAction == 1) {
                // Increase yield exposure action: we bring in the yield bearing asset
                tokenOut = yieldBearingAsset;
                tokenIn = stablecoin;
            } else {
                // Decrease yield exposure action: we bring in the liquid stablecoin
                tokenIn = yieldBearingAsset;
                tokenOut = stablecoin;
            }
        }
        uint256 amountOut = transmuter.swapExactInput(
            amount,
            0,
            address(agToken),
            tokenOut,
            address(this),
            block.timestamp
        );

        // Swap to tokenIn
        amountOut = _swapToTokenOut(typeAction, tokenOut, tokenIn, amountOut, swapType, callData);

        _adjustAllowance(tokenIn, address(transmuter), amountOut);
        uint256 amountStableOut = transmuter.swapExactInput(
            amountOut,
            minAmountOut,
            tokenIn,
            address(agToken),
            address(this),
            block.timestamp
        );
        if (amount > amountStableOut) {
            budget[sender] -= amount - amountStableOut; // Will revert if not enough funds
        }
        return CALLBACK_SUCCESS;
    }

    /**
     * @notice Add budget to a receiver
     * @param amount amount of AGToken to add to the budget
     * @param receiver address of the receiver
     */
    function addBudget(uint256 amount, address receiver) public virtual {
        IERC20(agToken).safeTransferFrom(msg.sender, address(this), amount);

        budget[receiver] += amount;
    }

    /**
     * @notice Remove budget from a receiver
     * @param amount amount of AGToken to remove from the budget
     * @param receiver address of the receiver
     */
    function removeBudget(uint256 amount, address receiver) public virtual {
        budget[msg.sender] -= amount; // Will revert if not enough funds

        IERC20(agToken).safeTransfer(receiver, amount);
    }

    function _swapToTokenOut(
        uint256 typeAction,
        address tokenIn,
        address tokenOut,
        uint256 amount,
        SwapType swapType,
        bytes memory callData
    ) internal returns (uint256 amountOut) {
        if (swapType == SwapType.SWAP) {
            amountOut = _swapToTokenOutSwap(tokenIn, tokenOut, amount, callData);
        } else if (swapType == SwapType.VAULT) {
            amountOut = _swapToTokenOutVault(typeAction, tokenOut, amount);
        }
    }

    /**
     * @notice Swap token using the router/aggregator
     * @param tokenIn address of the token to swap
     * @param tokenOut address of the token to receive
     * @param amount amount of token to swap
     * @param callData bytes to call the router/aggregator
     */
    function _swapToTokenOutSwap(
        address tokenIn,
        address tokenOut,
        uint256 amount,
        bytes memory callData
    ) internal returns (uint256) {
        uint256 balance = IERC20(tokenOut).balanceOf(address(this));

        address[] memory tokens = new address[](1);
        tokens[0] = tokenIn;
        bytes[] memory callDatas = new bytes[](1);
        callDatas[0] = callData;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        _swap(tokens, callDatas, amounts);

        uint256 amountOut = IERC20(tokenOut).balanceOf(address(this)) - balance;
        uint256 decimalsTokenIn = IERC20Metadata(tokenIn).decimals();
        uint256 decimalsTokenOut = IERC20Metadata(tokenOut).decimals();

        if (decimalsTokenIn > decimalsTokenOut) {
            amount /= 10 ** (decimalsTokenIn - decimalsTokenOut);
        } else if (decimalsTokenIn < decimalsTokenOut) {
            amount *= 10 ** (decimalsTokenOut - decimalsTokenIn);
        }
        if (amountOut < (amount * (BPS - maxSwapSlippage)) / BPS) {
            revert SlippageTooHigh();
        }
        return amountOut;
    }

    /**
     * @dev Deposit or redeem the vault asset
     * @param typeAction 1 for deposit, 2 for redeem
     * @param tokenOut address of the token to receive
     * @param amount amount of token to swap
     */
    function _swapToTokenOutVault(
        uint256 typeAction,
        address tokenOut,
        uint256 amount
    ) internal returns (uint256 amountOut) {
        if (typeAction == 1) {
            // Granting allowance with the yieldBearingAsset for the vault asset
            _adjustAllowance(tokenOut, tokenOut, amount);
            amountOut = IERC4626(tokenOut).deposit(amount, address(this));
        } else amountOut = IERC4626(tokenOut).redeem(amount, address(this), address(this));
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        HARVEST                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Invests or divests from the yield asset associated to `yieldBearingAsset` based on the current exposure
    ///  to this yieldBearingAsset
    /// @dev This transaction either reduces the exposure to `yieldBearingAsset` in the Transmuter or frees up
    /// some yieldBearingAsset that can then be used for people looking to burn stablecoins
    /// @dev Due to potential transaction fees within the Transmuter, this function doesn't exactly bring
    /// `yieldBearingAsset` to the target exposure
    /// @dev scale is a number between 0 and 1e9 that represents the proportion of the agToken to harvest,
    /// it is used to lower the amount of the asset to harvest for example to have a lower slippage
    function harvest(address yieldBearingAsset, uint256 scale, bytes calldata extraData) public virtual {
        if (scale > 1e9) revert InvalidParam();
        YieldBearingParams memory yieldBearingInfo = yieldBearingData[yieldBearingAsset];
        (uint8 increase, uint256 amount) = _computeRebalanceAmount(yieldBearingAsset, yieldBearingInfo);
        amount = (amount * scale) / 1e9;

        (SwapType swapType, bytes memory data) = abi.decode(extraData, (SwapType, bytes));

        if (amount > 0) {
            try transmuter.updateOracle(yieldBearingInfo.stablecoin) {} catch {}

            adjustYieldExposure(
                amount,
                increase,
                yieldBearingAsset,
                yieldBearingInfo.stablecoin,
                (amount * (1e9 - maxSlippage)) / 1e9,
                swapType,
                data
            );
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        SETTERS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the token transfer address
     * @param newTokenTransferAddress address of the token transfer contract
     */
    function setTokenTransferAddress(address newTokenTransferAddress) public override onlyGuardian {
        super.setTokenTransferAddress(newTokenTransferAddress);
    }

    /**
     * @notice Set the swap router
     * @param newSwapRouter address of the swap router
     */
    function setSwapRouter(address newSwapRouter) public override onlyGuardian {
        super.setSwapRouter(newSwapRouter);
    }

    /**
     * @notice Set the max swap slippage
     * @param newMaxSwapSlippage max slippage in BPS
     */
    function setMaxSwapSlippage(uint32 newMaxSwapSlippage) external onlyGuardian {
        maxSwapSlippage = newMaxSwapSlippage;
    }
}
