// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import "./Rebalancer.sol";
import { IERC4626 } from "interfaces/external/IERC4626.sol";
import { IERC3156FlashBorrower } from "oz/interfaces/IERC3156FlashBorrower.sol";
import { IERC3156FlashLender } from "oz/interfaces/IERC3156FlashLender.sol";

/// @title RebalancerFlashloan
/// @author Angle Labs, Inc.
/// @notice Contract built to subsidize rebalances between collateral tokens
contract RebalancerFlashloan is Rebalancer, IERC3156FlashBorrower {
    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    IERC4626 public immutable VAULT;

    IERC20 public immutable COLLATERAL;

    IERC3156FlashLender public immutable FLASHLOAN;

    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    INITIALIZATION                                                  
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Initializes the immutable variables of the contract: `accessControlManager`, `transmuter` and `agToken`
    constructor(
        IAccessControlManager _accessControlManager,
        ITransmuter _transmuter,
        IERC4626 _vault,
        IERC3156FlashLender _flashloan
    ) Rebalancer(_accessControlManager, _transmuter) {
        if (address(_flashloan) == address(0)) revert ZeroAddress();
        VAULT = _vault;
        COLLATERAL = IERC20(_vault.asset());
        FLASHLOAN = _flashloan;
        _collateral.safeApprove(type(uint256).max, address(_vault));
        IERC20(AGTOKEN).safeApprove(type(uint256).max, address(_flashloan));
    }

    function adjustYieldExposure(uint256 amountStablecoins, uint8 increase) external {
        if (!TRANSMUTER.isSellerTrusted(sender)) revert NotTrusted();
        FLASHLOAN.flashLoan(address(this), address(AGTOKEN), amountStablecoins, abi.encode(increase));
    }

    /// @inheritdoc IERC3156FlashBorrower
    function onFlashLoan(
        address initiator,
        address,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32) {
        if (msg.sender != address(FLASHLOAN) || initiator != address(this) || fee != 0) revert NotTrusted();
        uint256 typeAction = abi.decode(data, uint256);
        address tokenOut;
        address tokenIn;
        if (typeAction == 1) {
            // Increase yield exposure action: we bring in the vault
            tokenOut = address(COLLATERAL);
            tokenIn = address(VAULT);
        } else {
            // Decrease yield exposure action: we bring in the collateral
            tokenIn = address(COLLATERAL);
            tokenOut = address(VAULT);
        }
        uint256 amountOut = TRANSMUTER.swapExactInput(amount, 0, AGTOKEN, tokenOut, address(this), block.timestamp);
        if (typeAction == 1) amountOut = VAULT.deposit(amountOut, address(this));
        else amountOut = VAULT.redeem(amountOut, address(this));
        uint256 allowance = IERC20(tokenIn).allowance(address(this), address(TRANSMUTER));
        if (allowance < amountIn)
            IERC20(tokenIn).safeIncreaseAllowance(address(TRANSMUTER), type(uint256).max - allowance);
        uint256 amountStableOut = TRANSMUTER.swapExactInput(
            amountOut,
            0,
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
