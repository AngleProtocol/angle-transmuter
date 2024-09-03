// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import "./Rebalancer.sol";
import { IERC3156FlashBorrower } from "oz/interfaces/IERC3156FlashBorrower.sol";
import { IERC3156FlashLender } from "oz/interfaces/IERC3156FlashLender.sol";

/// @title BaseRebalancerFlashloan
/// @author Angle Labs, Inc.
/// @dev General rebalancer contract with flashloan capabilities
contract BaseRebalancerFlashloan is Rebalancer, IERC3156FlashBorrower {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    /// @notice Angle stablecoin flashloan contract
    IERC3156FlashLender public immutable FLASHLOAN;

    constructor(
        IAccessControlManager _accessControlManager,
        ITransmuter _transmuter,
        IERC3156FlashLender _flashloan
    ) Rebalancer(_accessControlManager, _transmuter) {
        if (address(_flashloan) == address(0)) revert ZeroAddress();
        FLASHLOAN = _flashloan;
        IERC20(AGTOKEN).safeApprove(address(_flashloan), type(uint256).max);
    }

    /// @notice Burns `amountStablecoins` for one collateral asset, swap for asset then mints stablecoins
    /// from the proceeds of the swap.
    /// @dev If `increase` is 1, then the system tries to increase its exposure to the yield bearing asset which means
    /// burning stablecoin for the liquid asset, swapping for the yield bearing asset, then minting the stablecoin
    /// @dev This function reverts if the second stablecoin mint gives less than `minAmountOut` of stablecoins
    /// @dev This function reverts if the swap slippage is higher than `maxSlippage`
    function adjustYieldExposure(
        uint256 amountStablecoins,
        uint8 increase,
        address collateral,
        address asset,
        uint256 minAmountOut,
        bytes calldata extraData
    ) public virtual {
        if (!TRANSMUTER.isTrustedSeller(msg.sender)) revert NotTrusted();
        FLASHLOAN.flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(AGTOKEN),
            amountStablecoins,
            abi.encode(increase, collateral, asset, minAmountOut, extraData)
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
        if (msg.sender != address(FLASHLOAN) || initiator != address(this) || fee != 0) revert NotTrusted();
        (uint256 typeAction, address collateral, address asset, uint256 minAmountOut, bytes memory callData) = abi
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

        // Swap to tokenIn
        amountOut = _swapToTokenIn(typeAction, tokenIn, tokenOut, amountOut, callData);

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

    /**
     * @dev hook to swap from tokenOut to tokenIn
     * @param typeAction 1 for deposit, 2 for redeem
     * @param tokenIn address of the token to swap
     * @param tokenOut address of the token to receive
     * @param amount amount of token to swap
     * @param callData extra call data (if needed)
     */
    function _swapToTokenIn(
        uint256 typeAction,
        address tokenIn,
        address tokenOut,
        uint256 amount,
        bytes memory callData
    ) internal virtual returns (uint256) {}
}
