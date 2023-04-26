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

enum OracleType {
    CHAINLINK_SIMPLE,
    CHAINLINK_TWO_FEEDS,
    WSTETH,
    EXTERNAL
}

struct Collateral {
    address manager;
    // TODO r can potentially be formatted into something with fewer bytes
    uint256 r;
    uint8 hasOracleFallback;
    uint8 unpaused;
    uint8 decimals;
    uint64[] xFeeMint;
    int64[] yFeeMint;
    uint64[] xFeeBurn;
    int64[] yFeeBurn;
    bytes oracle;
}

struct Module {
    address token;
    uint256 r;
    uint64 maxExposure;
    uint8 initialized;
    uint8 redeemable;
    uint8 unpaused;
}

struct KheopsStorage {
    // TODO: rename reserves = not a good name -> as here it's more totalMinted according to the system
    uint256 reserves;
    address[] collateralList;
    address[] redeemableModuleList;
    address[] unredeemableModuleList;
    mapping(address => Collateral) collaterals;
    mapping(address => Module) modules;
    mapping(address => uint256) isTrusted;
    uint256 accumulator;
    uint64[] xRedemptionCurve;
    int64[] yRedemptionCurve;
    IAgToken agToken;
}
