// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import "./Rebalancer.sol";
import { IERC4626 } from "interfaces/external/IERC4626.sol";
import { IERC3156FlashBorrower } from "oz/interfaces/IERC3156FlashBorrower.sol";
import { IERC3156FlashLender } from "oz/interfaces/IERC3156FlashLender.sol";

/// @title RebalancerFlashloan
/// @author Angle Labs, Inc.
contract RebalancerFlashloan is Rebalancer, IERC3156FlashBorrower {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    /// @notice ERC4626 Vault accepted as a collateral
    IERC4626 public immutable VAULT;

    /// @notice Liquid collateral wrapped in the vault
    IERC20 public immutable COLLATERAL;

    /// @notice Angle stablecoin flashloan contract
    IERC3156FlashLender public immutable FLASHLOAN;

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
        COLLATERAL.safeApprove(address(_vault), type(uint256).max);
        IERC20(AGTOKEN).safeApprove(address(_flashloan), type(uint256).max);
    }

    /// @notice Burns `amountStablecoins` for one collateral asset and mints the same with another asset
    /// @dev If `increase` is 1, then the system
    function adjustYieldExposure(uint256 amountStablecoins, uint8 increase) external {
        if (!TRANSMUTER.isTrustedSeller(msg.sender)) revert NotTrusted();
        FLASHLOAN.flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(AGTOKEN),
            amountStablecoins,
            abi.encode(increase)
        );
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
        uint256 typeAction = abi.decode(data, (uint256));
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
        else amountOut = VAULT.redeem(amountOut, address(this), address(this));
        uint256 allowance = IERC20(tokenIn).allowance(address(this), address(TRANSMUTER));
        if (allowance < amountOut)
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
