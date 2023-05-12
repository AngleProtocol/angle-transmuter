// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAccessControlManager } from "../interfaces/IAccessControlManager.sol";
import { IAgToken } from "../interfaces/IAgToken.sol";

/**
 * TODO: should we put the elements that only concern one facet in the corresponding file?
 * Because we don't want to upgrade all files when just adding a new oracle type
 */

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
    // `accessControlManager` used to check roles
    IAccessControlManager accessControlManager;
}

enum PauseType {
    Mint,
    Burn,
    Redeem
}

enum QuoteType {
    MintExactInput,
    MintExactOutput,
    BurnExactInput,
    BurnExactOutput
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
    // Whether the collateral supports strategies
    uint8 isManaged;
    // Whether minting from this asset is unpaused
    uint8 unpausedMint;
    // Whether burning for this asset is unpaused
    uint8 unpausedBurn;
    // Amount of decimals of the collateral
    uint8 decimals;
    // Normalized amount of stablecoins issued from this collateral
    uint224 normalizedStables;
    uint64[] xFeeMint;
    // Mint fees at the exposures specified in `xFeeMint`
    int64[] yFeeMint;
    uint64[] xFeeBurn;
    // Burn fees at the exposures specified in `xFeeBurn`
    int64[] yFeeBurn;
    // Data about the oracle used for the collateral
    bytes oracleConfig;
    // Storage params if this collateral is invested in other strategies
    ManagerStorage managerData;
}

struct KheopsStorage {
    // AgToken handled by the system
    IAgToken agToken;
    // Whether redemption is paused
    uint8 pausedRedemption;
    // Normalized amount of stablecoins issued by the system
    uint128 normalizedStables;
    // Value used to reconcile `normalizedStables` values with the actual amount that have been issued
    uint128 normalizer;
    // List of collateral assets supported by the system
    address[] collateralList;
    uint64[] xRedemptionCurve;
    // Value of the redemption fees at the collateral ratios specified in `xRedemptionCurve`
    int64[] yRedemptionCurve;
    // Maps a collateral asset to its parameters
    mapping(address => Collateral) collaterals;
    // Whether an address is trusted to update the normalizer value
    mapping(address => uint256) isTrusted;
    // Whether an address is trusted to sell external reward tokens accruing to Kheops
    mapping(address => uint256) isSellerTrusted;
}

struct ManagerStorage {
    // The collateral corresponding to the manager must also be in the list
    IERC20[] subCollaterals;
    bytes managerConfig;
}
