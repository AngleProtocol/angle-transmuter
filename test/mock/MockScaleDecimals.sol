// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.19;

import "contracts/helpers/BaseHarvester.sol";

contract MockScaleDecimals is BaseHarvester {
    constructor(
        uint96 initialMaxSlippage,
        IAccessControlManager definitiveAccessControlManager,
        IAgToken definitiveAgToken,
        ITransmuter definitiveTransmuter
    ) BaseHarvester(initialMaxSlippage, definitiveAccessControlManager, definitiveAgToken, definitiveTransmuter) {}

    function harvest(address yieldBearingAsset, uint256 scale, bytes calldata extraData) external override {}

    function scaleDecimals(
        uint256 decimalsTokenIn,
        uint256 decimalsTokenOut,
        uint256 amountIn,
        bool assetIn
    ) external pure returns (uint256) {
        return _scaleAmountBasedOnDecimals(decimalsTokenIn, decimalsTokenOut, amountIn, assetIn);
    }
}
