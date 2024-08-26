// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.5.0;

import "./IRebalancer.sol";
import { IERC3156FlashBorrower } from "oz/interfaces/IERC3156FlashBorrower.sol";

/// @title IRebalancer
/// @author Angle Labs, Inc.
interface IRebalancerFlashloan is IRebalancer, IERC3156FlashBorrower {
    /// @notice Burns `amountStablecoins` for one collateral asset, swap for asset then mints stablecoins from the proceeds of the
    /// swap
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
    ) external;
}
