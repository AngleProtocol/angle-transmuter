// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.0;

import { Storage as s } from "../libraries/Storage.sol";
import { Setters } from "../libraries/Setters.sol";
import { Oracle } from "../libraries/Oracle.sol";
import "../../utils/Constants.sol";
import "../../interfaces/external/chainlink/AggregatorV3Interface.sol";

import "../Storage.sol";

/// @dev This contract is used only once to initialize the diamond proxy.
contract Test {
    function initialize(
        IAccessControlManager _accessControlManager,
        address _agToken,
        address collateral,
        address oracle
    ) external {
        Setters.setAccessControlManager(_accessControlManager);

        KheopsStorage storage ks = s.kheopsStorage();
        ks.accumulator = BASE_27;
        ks.agToken = IAgToken(_agToken);

        Setters.addCollateral(collateral);
        bytes memory oracleStorage;
        AggregatorV3Interface[] memory circuitChainlink = new AggregatorV3Interface[](1);
        uint32[] memory stalePeriods = new uint32[](1);
        uint8[] memory circuitChainIsMultiplied = new uint8[](1);
        uint8[] memory chainlinkDecimals = new uint8[](1);
        circuitChainlink[0] = AggregatorV3Interface(address(0));
        stalePeriods[0] = 1 hours;
        circuitChainIsMultiplied[0] = 1;
        chainlinkDecimals[0] = 8;
        bytes memory readData = abi.encode(circuitChainlink, stalePeriods, circuitChainIsMultiplied, chainlinkDecimals);
        Setters.setOracle(
            collateral,
            abi.encode(OracleReadType.CHAINLINK_FEEDS, OracleQuoteType.UNIT, OracleTargetType.STABLE, readData),
            oracleStorage
        );
    }
}
