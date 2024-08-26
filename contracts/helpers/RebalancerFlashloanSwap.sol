// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import "./ARebalancerFlashloan.sol";
import { ASwapper } from "utils/src/Swapper.sol";

/// @title RebalancerFlashloanSwap
/// @author Angle Labs, Inc.
/// @dev Rebalancer contract for a Transmuter with as collaterals a liquid stablecoin and an yield bearing asset
/// using this liquid stablecoin as an asset
contract RebalancerFlashloanSwap is ARebalancerFlashloan, ASwapper {
    using SafeCast for uint256;

    uint32 public maxSlippage;

    constructor(
        IAccessControlManager _accessControlManager,
        ITransmuter _transmuter,
        IERC3156FlashLender _flashloan,
        address _swapRouter,
        address _tokenTransferAddress,
        uint32 _maxSlippage
    )
        ARebalancerFlashloan(_accessControlManager, _transmuter, _flashloan)
        ASwapper(_swapRouter, _tokenTransferAddress)
    {
        maxSlippage = _maxSlippage;
    }

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
     * @notice Set the max slippage
     * @param _maxSlippage max slippage in BPS
     */
    function setMaxSlippage(uint32 _maxSlippage) external onlyGuardian {
        maxSlippage = _maxSlippage;
    }

    /**
     * @notice Swap token using the router/aggregator
     * @param tokenIn address of the token to swap
     * @param tokenOut address of the token to receive
     * @param callData bytes to call the router/aggregator
     * @param amount amount of token to swap
     */
    function _swap(
        address tokenIn,
        address tokenOut,
        bytes memory callData,
        uint256 amount
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
            amountOut /= 10**(decimalsTokenIn - decimalsTokenOut);
        } else if (decimalsTokenIn < decimalsTokenOut) {
            amountOut *= 10**(decimalsTokenOut - decimalsTokenIn);
        }
        if (amountOut  < (amount * (BPS - maxSlippage)) / BPS) {
            revert SlippageTooHigh();
        }
        return amountOut;
    }

    /// @inheritdoc IERC3156FlashBorrower
    function onFlashLoan(
        address initiator,
        address,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) public override returns (bytes32) {
        if (msg.sender != address(FLASHLOAN) || initiator != address(this) || fee != 0) revert NotTrusted();
        (uint256 typeAction, address collateral, address asset, uint256 minAmountOut, bytes memory swapCallData) = abi
            .decode(data, (uint256, address, address, uint256, bytes));
        address tokenOut;
        address tokenIn;
        if (typeAction == 1) {
            // Increase yield exposure action: we bring in the yield bearing asset
            tokenOut = collateral;
            tokenIn = asset;
        } else {
            // Decrease yield exposure action: we bring in the liquid asset
            tokenIn = collateral;
            tokenOut = asset;
        }
        uint256 amountOut = TRANSMUTER.swapExactInput(amount, 0, AGTOKEN, tokenOut, address(this), block.timestamp);
        amountOut = _swap(tokenOut, tokenIn, swapCallData, amountOut);

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
