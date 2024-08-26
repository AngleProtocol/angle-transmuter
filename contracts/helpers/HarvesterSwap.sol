// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

import "./AHarvester.sol";

/// @title HarvesterSwap
/// @author Angle Labs, Inc.
/// @dev Contract for anyone to permissionlessly adjust the reserves of Angle Transmuter through
/// the RebalancerFlashloanSwap contract
contract HarvesterSwap is AHarvester {
    constructor(
        address _rebalancer,
        address collateral,
        address asset,
        uint64 targetExposure,
        uint64 overrideExposures,
        uint64 maxExposureYieldAsset,
        uint64 minExposureYieldAsset,
        uint96 _maxSlippage
    )
        AHarvester(
            _rebalancer,
            collateral,
            asset,
            targetExposure,
            overrideExposures,
            maxExposureYieldAsset,
            minExposureYieldAsset,
            _maxSlippage
        )
    {}
}
