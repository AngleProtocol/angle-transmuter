// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { Utils } from "./utils/Utils.s.sol";
import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
import "stringutils/strings.sol";
import "./Constants.s.sol";

import { RebalancerFlashloanVault } from "contracts/helpers/RebalancerFlashloanVault.sol";

contract AdjustYieldExposure is Utils {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("KEEPER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Address: %s", deployer);
        console.log(deployer.balance);
        vm.startBroadcast(deployerPrivateKey);

        RebalancerFlashloanVault rebalancer = RebalancerFlashloanVault(0x22604C0E5633A9810E01c9cb469B23Eee17AC411);
        rebalancer.adjustYieldExposure(1300000 * 1 ether, 0, USDC, STEAK_USDC, 1200000 * 1 ether, new bytes(0));

        vm.stopBroadcast();
    }
}
