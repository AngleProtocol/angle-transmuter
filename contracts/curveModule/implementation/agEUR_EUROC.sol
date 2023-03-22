// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import "../CurveModule.sol";

/// @title ConvexAgEURvEUROCAMO
/// @author Angle Labs
/// @notice Implements ConvexBPAMO for the pool agEUR-EUROC
contract CurveModuleAgEUR_EUROC is CurveModule {
    constructor()
        initializer
        CurveModule(
            _CURVE_agEUR_EUROC_POOL,
            _AGEUR,
            _CURVE_agEUR_EUROC_STAKE_DAO_VAULT,
            _CURVE_agEUR_EUROC_GAUGE,
            _CURVE_agEUR_EUROC_CONVEX_REWARDS_POOL,
            _CURVE_agEUR_EUROC_CONVEX_POOL_ID
        )
    {}
}
