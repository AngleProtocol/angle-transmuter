// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "./utils/Utils.s.sol";
import { console } from "forge-std/console.sol";
import { HarvesterSwap } from "contracts/helpers/HarvesterSwap.sol";
import "./Constants.s.sol";

contract DeployHarvester is Utils {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address: ", deployer);
        address rebalancer = 0x22604C0E5633A9810E01c9cb469B23Eee17AC411;
        address asset = USDM;
        address collateral = USDC;
        uint64 targetExposure = (13 * 1e9) / 100;
        uint64 overrideExposures = 0;
        uint96 maxSlippage = 1e9 / 100;
        HarvesterSwap HarvesterSwap = new HarvesterSwap(
            rebalancer,
            collateral,
            asset,
            targetExposure,
            overrideExposures,
            0,
            0,
            maxSlippage
        );
        console.log("HarvesterSwap deployed at: ", address(HarvesterSwap));

        vm.stopBroadcast();
    }
}
