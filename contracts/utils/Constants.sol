// SPDX-License-Identifier: GPL-3.0

import "../interfaces/external/convex/IClaimZap.sol";
import "../interfaces/external/convex/IBooster.sol";

pragma solidity ^0.8.17;

contract Constants {
    address internal constant _ONE_INCH_ROUTER = 0x1111111254fb6c44bAC0beD2854e76F90643097d;

    IConvexBooster internal constant _CONVEX_BOOSTER = IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    IConvexClaimZap internal constant _CONVEX_CLAIM_ZAP = IConvexClaimZap(0xDd49A93FDcae579AE50B4b9923325e9e335ec82B);

    address internal constant _AGEUR = 0x1a7e4e63778B4f12a199C062f3eFdD288afCBce8;

    // agEUR EUROC Curve Pool
    address internal constant _CURVE_agEUR_EUROC_POOL = 0xBa3436Fd341F2C8A928452Db3C5A3670d1d5Cc73;
    address internal constant _CURVE_agEUR_EUROC_STAKE_DAO_VAULT = 0xDe46532a49c88af504594F488822F452b7FBc7BD;
    address internal constant _CURVE_agEUR_EUROC_GAUGE = 0x63f222079608EEc2DDC7a9acdCD9344a21428Ce7;
    address internal constant _CURVE_agEUR_EUROC_CONVEX_REWARDS_POOL = 0xA91fccC1ec9d4A2271B7A86a7509Ca05057C1A98;
    uint256 internal constant _CURVE_agEUR_EUROC_CONVEX_POOL_ID = 113;

    uint256 internal constant _BASE_9 = 1e9;
    uint256 internal constant _BASE_12 = 1e12;
    uint256 internal constant _BASE_18 = 1e18;
}
