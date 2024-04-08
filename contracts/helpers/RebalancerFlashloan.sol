// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import "./Rebalancer.sol";
import { IERC4626 } from "interfaces/external/IERC4626.sol";
import { IERC3156FlashBorrower } from "oz/interfaces/IERC3156FlashBorrower.sol";
import { IERC3156FlashLender } from "oz/interfaces/IERC3156FlashLender.sol";

/// @title RebalancerFlashloan
/// @author Angle Labs, Inc.
/// @dev Rebalancer contract for a Transmuter with as collaterals a liquid stablecoin and an ERC4626 token
/// using this liquid stablecoin as an asset
contract RebalancerFlashloan is Rebalancer, IERC3156FlashBorrower {
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

    /// @notice Burns `amountStablecoins` for one collateral asset and mints stablecoins from the proceeds of the
    /// first burn
    /// @dev If `increase` is 1, then the system tries to increase its exposure to the yield bearing asset which means
    /// burning stablecoin for the liquid asset, depositing into the ERC4626 vault, then minting the stablecoin
    /// @dev This function reverts if the second stablecoin mint gives less than `minAmountOut` of stablecoins
    function adjustYieldExposure(
        uint256 amountStablecoins,
        uint8 increase,
        address collateral,
        address vault,
        uint256 minAmountOut
    ) external {
        if (!TRANSMUTER.isTrustedSeller(msg.sender)) revert NotTrusted();
        FLASHLOAN.flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(AGTOKEN),
            amountStablecoins,
            abi.encode(increase, collateral, vault, minAmountOut)
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
        (uint256 typeAction, address collateral, address vault, uint256 minAmountOut) = abi.decode(
            data,
            (uint256, address, address, uint256)
        );
        address tokenOut;
        address tokenIn;
        if (typeAction == 1) {
            // Increase yield exposure action: we bring in the ERC4626 token
            tokenOut = collateral;
            tokenIn = vault;
        } else {
            // Decrease yield exposure action: we bring in the liquid asset
            tokenIn = collateral;
            tokenOut = vault;
        }
        uint256 amountOut = TRANSMUTER.swapExactInput(amount, 0, AGTOKEN, tokenOut, address(this), block.timestamp);
        if (typeAction == 1) {
            // Granting allowance with the collateral for the vault asset
            _adjustAllowance(collateral, vault, amountOut);
            amountOut = IERC4626(vault).deposit(amountOut, address(this));
        } else amountOut = IERC4626(vault).redeem(amountOut, address(this), address(this));
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
