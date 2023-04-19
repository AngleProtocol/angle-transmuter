// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/IAgToken.sol";
import "../interfaces/IDepositModule.sol";
import "../interfaces/IManager.sol";
import "../interfaces/IMinter.sol";
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
        address oracle;
        uint8 hasOracleFallback;
        uint8 delegated;
        uint8 unpaused;
        uint8 decimals;
        address manager;
        uint256 r;
        uint64[] xFeeMint;
        int64[] yFeeMint;
        uint64[] xFeeBurn;
        int64[] yFeeBurn;
    }

    struct DirectDeposit {
        uint256 r;
        address token;
        uint64 maxExposure;
        uint8 redeemable;
        uint8 paused;
    }

    uint256 public reserves;
    address[] public collateralList;
    address[] public redeemableDirectDepositList;
    address[] public unredeemableDirectDepositList;
    mapping(IERC20 => Collateral) public collaterals;
    mapping(address => DirectDeposit) public directDeposits;

    uint64[] public xRedemptionCurve;
    int64[] public yRedemptionCurve;

    IAgToken public agToken;

    uint256[43] private __gap;
}
