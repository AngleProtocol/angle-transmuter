// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import "./BaseRebalancerFlashloan.sol";
import { IERC20Metadata } from "oz/interfaces/IERC20Metadata.sol";
import { RouterSwapper } from "utils/src/RouterSwapper.sol";

/// @title RebalancerFlashloanSwap
/// @author Angle Labs, Inc.
/// @dev Rebalancer contract for a Transmuter with as collaterals a liquid stablecoin and an yield bearing asset
/// using this liquid stablecoin as an asset
contract RebalancerFlashloanSwap is BaseRebalancerFlashloan, RouterSwapper {
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
        BaseRebalancerFlashloan(_accessControlManager, _transmuter, _flashloan)
        RouterSwapper(_swapRouter, _tokenTransferAddress)
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
     * @param amount amount of token to swap
     * @param callData bytes to call the router/aggregator
     */
    function _swapToTokenIn(
        uint256,
        address tokenIn,
        address tokenOut,
        uint256 amount,
        bytes memory callData
    ) internal override returns (uint256) {
        uint256 balance = IERC20(tokenIn).balanceOf(address(this));

        address[] memory tokens = new address[](1);
        tokens[0] = tokenOut;
        bytes[] memory callDatas = new bytes[](1);
        callDatas[0] = callData;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        _swap(tokens, callDatas, amounts);

        uint256 amountOut = IERC20(tokenIn).balanceOf(address(this)) - balance;
        uint256 decimalsTokenOut = IERC20Metadata(tokenOut).decimals();
        uint256 decimalsTokenIn = IERC20Metadata(tokenIn).decimals();

        if (decimalsTokenOut > decimalsTokenIn) {
            amount /= 10 ** (decimalsTokenOut - decimalsTokenIn);
        } else if (decimalsTokenOut < decimalsTokenIn) {
            amount *= 10 ** (decimalsTokenIn - decimalsTokenOut);
        }
        if (amountOut < (amount * (BPS - maxSlippage)) / BPS) {
            revert SlippageTooHigh();
        }
        return amountOut;
    }
}
