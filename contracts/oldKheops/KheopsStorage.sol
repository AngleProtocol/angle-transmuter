// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/IAgToken.sol";
import "../interfaces/IModule.sol";
import "../interfaces/IManager.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IOracleFallback.sol";

import "../utils/AccessControl.sol";
import { Constants as c } from "../utils/Constants.sol";
import "../utils/FunctionUtils.sol";

/// @title MinterStorage
/// @author Angle Labs, Inc.
/// @notice Parameters, variables and events for the `Minter` contract
contract KheopsStorage is Initializable, AccessControl, FunctionUtils {
    using SafeERC20 for IERC20;

    // TODO parameter for pausing the whole system or -> is it just setting fees

    struct Collateral {
        address oracle;
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
        // For future upgrades
        bytes extraData;
    }

    struct Module {
        address token;
        uint256 r;
        uint64 maxExposure;
        uint8 initialized;
        uint8 redeemable;
        uint8 unpaused;
        // For future upgrades
        bytes extraData;
    }

    // TODO: rename reserves = not a good name -> as here it's more totalMinted according to the system
    uint256 public reserves;
    address[] public collateralList;
    address[] public redeemableModuleList;
    address[] public unredeemableModuleList;
    mapping(address => Collateral) public collaterals;
    mapping(address => Module) public modules;
    mapping(address => uint256) public isTrusted;
    uint256 public accumulator;

    uint64[] public xRedemptionCurve;
    int64[] public yRedemptionCurve;

    IAgToken public agToken;

    uint256[43] private __gap;
}
