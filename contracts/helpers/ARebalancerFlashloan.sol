// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import "./Rebalancer.sol";
import { IERC3156FlashBorrower } from "oz/interfaces/IERC3156FlashBorrower.sol";
import { IERC3156FlashLender } from "oz/interfaces/IERC3156FlashLender.sol";

/// @title ARebalancerFlashloan
/// @author Angle Labs, Inc.
/// @dev General rebalancer contract with flashloan capabilities
contract ARebalancerFlashloan is Rebalancer, IERC3156FlashBorrower {
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
    ) public virtual returns (bytes32) {}
}
