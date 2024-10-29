// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.5.0;

interface IHarvester {
    function setYieldBearingAssetData(
        address yieldBearingAsset,
        address stablecoin,
        uint64 targetExposure,
        uint64 minExposureYieldAsset,
        uint64 maxExposureYieldAsset,
        uint64 overrideExposures
    ) external;

    function updateLimitExposuresYieldAsset(address yieldBearingAsset) external;

    function setMaxSlippage(uint96 newMaxSlippage) external;

    function harvest(address yieldBearingAsset, uint256 scale, bytes calldata extraData) external;
}
