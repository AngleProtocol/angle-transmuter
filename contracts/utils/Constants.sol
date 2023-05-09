// SPDX-License-Identifier: BUSL-1.1

import "../interfaces/external/lido/IStETH.sol";

pragma solidity ^0.8.17;

/// @dev Storage position of `DiamondStorage` structure.
bytes32 constant DIAMOND_STORAGE_POSITION = 0xc8fcad8db84d3cc18b4c41d551ea0ee66dd599cde068d998e57d5e09332c131b; // keccak256("diamond.standard.diamond.storage") - 1;

bytes32 constant KHEOPS_STORAGE_POSITION = keccak256("diamond.standard.kheops.storage"); // keccak256("diamond.standard.diamond.storage") - 1;

// =================================== MATHS ===================================

uint256 constant BASE_6 = 1e6;
uint256 constant BASE_8 = 1e8;
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

// ============================== OTHER ADDRESSES ==============================

IStETH constant STETH = IStETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
