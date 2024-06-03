// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { Utils } from "./utils/Utils.s.sol";
import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
import "stringutils/strings.sol";
import "./Constants.s.sol";

import "contracts/transmuter/Storage.sol" as Storage;
import { ITransmuter } from "interfaces/ITransmuter.sol";
import "interfaces/external/chainlink/AggregatorV3Interface.sol";
import "interfaces/external/IERC4626.sol";

import { CollateralSetupProd } from "contracts/transmuter/configs/ProductionTypes.sol";

contract UpdateOracle is Utils {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("KEEPER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Address: %s", deployer);
        console.log(deployer.balance);
        vm.startBroadcast(deployerPrivateKey);

        ITransmuter usdaTransmuter = ITransmuter(0x222222fD79264BBE280b4986F6FEfBC3524d0137);
        console.log(address(usdaTransmuter));
        usdaTransmuter.updateOracle(0xBEEF01735c132Ada46AA9aA4c54623cAA92A64CB);

        /*
        ITransmuter euraTransmuter = ITransmuter(0x00253582b2a3FE112feEC532221d9708c64cEFAb);
        // euraTransmuter.updateOracle(0x3f95AA88dDbB7D9D484aa3D482bf0a80009c52c9);
        euraTransmuter.updateOracle(0x2F123cF3F37CE3328CC9B5b8415f9EC5109b45e7);
        */
        vm.stopBroadcast();
    }
}
