// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import { IAccessControlManager } from "../interfaces/IAccessControlManager.sol";
import { IAgToken } from "../interfaces/IAgToken.sol";

enum FacetCutAction {
    Add,
    Replace,
    Remove
}

struct FacetCut {
    address facetAddress;
    FacetCutAction action;
    bytes4[] functionSelectors;
}

struct Facet {
    address facetAddress;
    bytes4[] functionSelectors;
}

struct FacetAddressAndSelectorPosition {
    address facetAddress;
    uint16 selectorPosition;
}

struct DiamondStorage {
    // function selector => facet address and selector position in selectors array
    mapping(bytes4 => FacetAddressAndSelectorPosition) facetAddressAndSelectorPosition;
    bytes4[] selectors;
    mapping(bytes4 => bool) supportedInterfaces;
    //`accessControlManager` used to check roles
    IAccessControlManager accessControlManager;
}

enum OracleReadType {
    CHAINLINK_FEEDS,
    EXTERNAL
}

enum OracleQuoteType {
    UNIT,
    WSTETH
}

enum OracleTargetType {
    STABLE,
    WSTETH,
    BONDS
}

struct Collateral {
    address manager;
    uint8 hasManager;
    uint8 unpausedMint;
    uint8 unpausedBurn;
    uint8 decimals;
    uint256 normalizedStables;
    uint64[] xFeeMint;
    int64[] yFeeMint;
    uint64[] xFeeBurn;
    int64[] yFeeBurn;
    bytes oracle;
    bytes oracleStorage;
}

struct Module {
    address token;
    uint64 maxExposure;
    uint8 initialized;
    uint8 redeemable;
    uint8 unpaused;
    uint256 normalizedStables;
}

struct KheopsStorage {
    IAgToken agToken;
    uint8 pausedRedemption;
    uint256 normalizedStables;
    uint256 normalizer;
    address[] collateralList;
    address[] redeemableModuleList;
    address[] unredeemableModuleList;
    uint64[] xRedemptionCurve;
    uint64[] yRedemptionCurve;
    mapping(address => Collateral) collaterals;
    mapping(address => Module) modules;
    mapping(address => uint256) isTrusted;
}
