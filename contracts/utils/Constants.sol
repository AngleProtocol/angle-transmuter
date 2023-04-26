// SPDX-License-Identifier: GPL-3.0

import "../interfaces/external/convex/IClaimZap.sol";
import "../interfaces/external/convex/IBooster.sol";
import "../interfaces/external/lido/IStETH.sol";

pragma solidity ^0.8.17;

// =================================== MATHS ===================================

uint256 constant BASE_6 = 1e6;
uint256 constant BASE_9 = 1e9;
uint256 constant BASE_12 = 1e12;
uint256 constant BASE_18 = 1e18;
uint256 constant HALF_BASE_27 = 1e27 / 2;
uint256 constant BASE_27 = 1e27;
uint256 constant BASE_36 = 1e36;

// ============================== COMMON ADDRESSES =============================

address constant ONE_INCH_ROUTER = 0x1111111254fb6c44bAC0beD2854e76F90643097d;
address constant AGEUR = 0x1a7e4e63778B4f12a199C062f3eFdD288afCBce8;

// =========================== CURVE - CONVEX - STAKE ==========================

IConvexBooster constant CONVEX_BOOSTER = IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
IConvexClaimZap constant CONVEX_CLAIM_ZAP = IConvexClaimZap(0xDd49A93FDcae579AE50B4b9923325e9e335ec82B);

// agEUR EUROC Curve Pool
address constant CURVE_AGEUR_EUROC_POOL = 0xBa3436Fd341F2C8A928452Db3C5A3670d1d5Cc73;
address constant CURVE_AGEUR_EUROC_STAKE_DAO_VAULT = 0xDe46532a49c88af504594F488822F452b7FBc7BD;
address constant CURVE_AGEUR_EUROC_GAUGE = 0x63f222079608EEc2DDC7a9acdCD9344a21428Ce7;
address constant CURVE_AGEUR_EUROC_CONVEX_REWARDS_POOL = 0xA91fccC1ec9d4A2271B7A86a7509Ca05057C1A98;
uint256 constant CURVE_AGEUR_EUROC_CONVEX_POOL_ID = 113;

// ============================== OTHER ADDRESSES ==============================

IStETH constant STETH = IStETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
