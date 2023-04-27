// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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

enum PauseType {
    Mint,
    Burn,
    Module,
    Redeem
}

enum OracleReadType {
    CHAINLINK_FEEDS,
    EXTERNAL,
    NO_ORACLE
}

enum OracleQuoteType {
    UNIT,
    WSTETH
}

enum OracleTargetType {
    STABLE,
    WSTETH
}

struct Collateral {
    uint8 hasManager;
    uint8 unpausedMint;
    uint8 unpausedBurn;
    uint8 decimals;
    uint256 normalizedStables;
    uint64[] xFeeMint;
    int64[] yFeeMint;
    uint64[] xFeeBurn;
    int64[] yFeeBurn;
    bytes oracleConfig;
    bytes oracleStorage;
    ManagerStorage managerStorage;
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

struct ManagerStorage {
    IERC20 asset;
    // Asset is also in the list
    IERC20[] subCollaterals;
}
