// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { Utils } from "./utils/Utils.s.sol";
import { TransmuterDeploymentHelper } from "./utils/TransmuterDeploymentHelper.s.sol";
import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
import "stringutils/strings.sol";
import "./Constants.s.sol";

import { CollateralSetupProd, Production } from "contracts/transmuter/configs/Production.sol";
import "contracts/transmuter/Storage.sol" as Storage;
import { DiamondCut } from "contracts/transmuter/facets/DiamondCut.sol";
import { DiamondEtherscan } from "contracts/transmuter/facets/DiamondEtherscan.sol";
import { DiamondLoupe } from "contracts/transmuter/facets/DiamondLoupe.sol";
import { DiamondProxy } from "contracts/transmuter/DiamondProxy.sol";
import { Getters } from "contracts/transmuter/facets/Getters.sol";
import { Redeemer } from "contracts/transmuter/facets/Redeemer.sol";
import { RewardHandler } from "contracts/transmuter/facets/RewardHandler.sol";
import { SettersGovernor } from "contracts/transmuter/facets/SettersGovernor.sol";
import { SettersGuardian } from "contracts/transmuter/facets/SettersGuardian.sol";
import { DummyDiamondImplementation } from "./generated/DummyDiamondImplementation.sol";
import { Swapper } from "contracts/transmuter/facets/Swapper.sol";
import { ITransmuter } from "interfaces/ITransmuter.sol";

contract SetOracle is Utils {
    function run() external {
        bytes memory oracleConfig;
        {
            // Pyth oracle for EUROC
            bytes32[] memory feedIds = new bytes32[](2);
            uint32[] memory stalePeriods = new uint32[](2);
            uint8[] memory isMultiplied = new uint8[](2);
            // pyth address
            address pyth = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6;
            // EUROC/USD
            feedIds[0] = 0x76fa85158bf14ede77087fe3ae472f66213f6ea2f5b411cb2de472794990fa5c;
            // USD/EUR
            feedIds[1] = 0xa995d00bb36a63cef7fd2c287dc105fc8f3d93779f062f09551b0af3e81ec30b;
            stalePeriods[0] = 14 days;
            stalePeriods[1] = 14 days;
            isMultiplied[0] = 1;
            isMultiplied[1] = 0;
            Storage.OracleQuoteType quoteType = Storage.OracleQuoteType.UNIT;
            bytes memory readData = abi.encode(pyth, feedIds, stalePeriods, isMultiplied, quoteType);
            bytes memory targetData;
            oracleConfig = abi.encode(Storage.OracleReadType.PYTH, Storage.OracleReadType.STABLE, readData, targetData);
            console.logBytes(oracleConfig);
        }
    }
}
