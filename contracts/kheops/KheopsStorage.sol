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
import "../utils/Constants.sol";
import "../utils/FunctionUtils.sol";

/// @title MinterStorage
/// @author Angle Labs, Inc.
/// @notice Parameters, variables and events for the `Minter` contract
contract KheopsStorage is Initializable, AccessControl, Constants, FunctionUtils {
    using SafeERC20 for IERC20;

    struct Collateral {
        address manager;
        address oracle;
        uint8 hasManager;
        uint8 unpausedMint;
        uint8 unpausedBurn;
        uint8 decimals;
        uint256 normalizedStables;
        uint64[] xFeeMint;
        int64[] yFeeMint;
        uint64[] xFeeBurn;
        int64[] yFeeBurn;
    }

    struct Module {
        address token;
        uint64 maxExposure;
        uint8 initialized;
        uint8 redeemable;
        uint8 unpaused;
        uint256 normalizedStables;
    }

    IAgToken public agToken;
    uint8 public pausedRedemption;
    uint256 public normalizedStables;
    uint256 public accumulator;
    address[] public collateralList;
    address[] public redeemableModuleList;
    address[] public unredeemableModuleList;
    uint64[] public xRedemptionCurve;
    int64[] public yRedemptionCurve;
    mapping(address => Collateral) public collaterals;
    mapping(address => Module) public modules;
    mapping(address => uint256) public isTrusted;

    uint256[43] private __gap;
}
