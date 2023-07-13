// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import "../utils/Constants.sol";
import { DiamondStorage, TransmuterStorage, Collateral, FacetInfo, WhitelistType } from "./Storage.sol";

/// @notice Contract mimicking the overall storage layout of the transmuter system.
/// @dev Not meant to be deployed or used. The goals are:
///  - To ensure the storage layout is well understood by everyone
///  - To force test failures if the layout is changed
/// @dev 
///  - uint256(TRANSMUTER_STORAGE_POSITION)      
///         = 87725637715361972314474735372533017845526400132006062725239677556399819577533
///  - uint256(DIAMOND_STORAGE_POSITION)         
///         = 90909012999857140622417080374671856515688564136957639390032885430481714942747
///  - uint256(IMPLEMENTATION_STORAGE_POSITION)  
///         = 24440054405305269366569402256811496959409073762505157381672968839269610695612
contract Layout {
    // uint256(IMPLEMENTATION_STORAGE_POSITION)
    uint256[24440054405305269366569402256811496959409073762505157381672968839269610695612] private __gap1;
    address public implementation;
    // uint256(TRANSMUTER_STORAGE_POSITION) - 1 - uint256(IMPLEMENTATION_STORAGE_POSITION)
    uint256[63285583310056702947905333115721520886117326369500905343566708717130208881920] private __gap2;
    address public agToken;                                                             // slot 1
    uint8 public isRedemptionLive;                                                      // slot 1
    uint8 public nonReentrant;                                                          // slot 1
    uint128 public normalizedStables;                                                   // slot 2
    uint128 public normalizer;                                                          // slot 2
    address[] public collateralList;                                                    // slot 3
    uint64[] public xRedemptionCurve;                                                   // slot 4
    int64[] public yRedemptionCurve;                                                    // slot 5
    mapping(address => Collateral) public collaterals;                                  // slot 6
    mapping(address => uint256) public isTrusted;                                       // slot 7
    mapping(address => uint256) public isSellerTrusted;                                 // slot 8
    mapping(WhitelistType => mapping(address => uint256)) public isWhitelistedForType;  // slot 9
    // uint256(TRANSMUTER_STORAGE_POSITION) - TransmuterStorage offset (9) - uint256(DIAMOND_STORAGE_POSITION)
    uint256[3183375284495168307942345002138838670162164004951576664793207874081895365205] private __gap3;
    bytes4[] public selectors;                                                          // slot 1
    mapping(bytes4 => FacetInfo) public selectorInfo;                                   // slot 2
    address public accessControlManager;                                                // slot 3
}
