// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { Utils } from "./utils/Utils.s.sol";
import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
import "stringutils/strings.sol";
import "./Constants.s.sol";

import { Savings } from "contracts/savings/Savings.sol";

contract SetRate is Utils {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("KEEPER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Address: %s", deployer);
        console.log(deployer.balance);
        vm.startBroadcast(deployerPrivateKey);

        // stUSD: 0x0022228a2cc5E7eF0274A7Baa600d44da5aB5776
        // stEUR: 0x004626A008B1aCdC4c74ab51644093b155e59A23

        Savings savings = Savings(0x004626A008B1aCdC4c74ab51644093b155e59A23);
        savings.setRate(1996917742275172864);

        vm.stopBroadcast();
    }
}
