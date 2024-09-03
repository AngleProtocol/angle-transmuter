// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

import "./BaseHarvester.sol";
import { IERC4626 } from "interfaces/external/IERC4626.sol";

/// @title HarvesterVault
/// @author Angle Labs, Inc.
/// @dev Contract for anyone to permissionlessly adjust the reserves of Angle Transmuter through
/// the RebalancerFlashloanVault contract
contract HarvesterVault is BaseHarvester {
    constructor(
        address _rebalancer,
        address vault,
        uint64 targetExposure,
        uint64 overrideExposures,
        uint64 maxExposureYieldAsset,
        uint64 minExposureYieldAsset,
        uint96 _maxSlippage
    )
        BaseHarvester(
            _rebalancer,
            address(IERC4626(vault).asset()),
            vault,
            targetExposure,
            overrideExposures,
            maxExposureYieldAsset,
            minExposureYieldAsset,
            _maxSlippage
        )
    {}

    function setCollateralData(
        address vault,
        uint64 targetExposure,
        uint64 minExposureYieldAsset,
        uint64 maxExposureYieldAsset,
        uint64 overrideExposures
    ) public virtual onlyGuardian {
        _setCollateralData(
            address(IERC4626(vault).asset()),
            vault,
            targetExposure,
            minExposureYieldAsset,
            maxExposureYieldAsset,
            overrideExposures
        );
    }
}
