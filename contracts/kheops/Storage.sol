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
    // Whether the collateral supports
    uint8 hasManager;
    // Whether minting from this asset is unpaused
    uint8 unpausedMint;
    // Whether burning for this asset is unpaused
    uint8 unpausedBurn;
    // Amount
    uint8 decimals;
    // TODO: normalizedStables could be encoded into something with lower bytes to gain some place
    // Normalized amount of stablecoins issued from this collateral
    uint256 normalizedStables;
    uint64[] xFeeMint;
    // Mint fees at the exposures specified in `xFeeMint`
    int64[] yFeeMint;
    uint64[] xFeeBurn;
    // Burn fees at the exposures specified in `xFeeBurn`
    int64[] yFeeBurn;
    // TODO: naming for oracle config and oracle storage seems odd -> what's the actual difference between both
    bytes oracleConfig;
    bytes oracleStorage;
    // Storage params if this collateral is invested in other strategies
    ManagerStorage managerStorage;
}

struct KheopsStorage {
    // AgToken handled by the system
    IAgToken agToken;
    // Whether redemption is paused
    uint8 pausedRedemption;
    // Normalized amount of stablecoins issued by the system
    uint256 normalizedStables;
    // Value used to reconcile `normalizedStables` values with the actual amount that have been issued
    uint256 normalizer;
    // List of collateral assets supported by the system
    address[] collateralList;
    uint64[] xRedemptionCurve;
    // Value of the redemption fees at the collateral ratios specified in `xRedemptionCurve`
    int64[] yRedemptionCurve;
    // Maps an asset to its
    mapping(address => Collateral) collaterals;
    // Whether an address is trusted to update the normalizer value
    mapping(address => uint256) isTrusted;
    // Whether an address is trusted to sell external reward tokens accruing to Kheops
    mapping(address => uint256) isSellerTrusted;
}

struct ManagerStorage {
    IERC20 asset;
    // Asset is also in the list
    IERC20[] subCollaterals;
}
