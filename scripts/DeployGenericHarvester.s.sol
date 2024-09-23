// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "./utils/Utils.s.sol";
import { console } from "forge-std/console.sol";
import { GenericHarvester } from "contracts/helpers/GenericHarvester.sol";
import { IAccessControlManager } from "contracts/utils/AccessControl.sol";
import { IAgToken } from "contracts/interfaces/IAgToken.sol";
import { ITransmuter } from "contracts/interfaces/ITransmuter.sol";
import { IERC3156FlashLender } from "oz/interfaces/IERC3156FlashLender.sol";
import "./Constants.s.sol";

contract DeployGenericHarvester is Utils {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address: ", deployer);
        uint256 maxMintAmount = 1000000e18;
        uint96 maxSlippage = 1e9 / 100;
        uint32 maxSwapSlippage = 100; // 1%
        IERC3156FlashLender flashloan = IERC3156FlashLender(_chainToContract(CHAIN_SOURCE, ContractType.FlashLoan));
        IAgToken agToken = IAgToken(_chainToContract(CHAIN_SOURCE, ContractType.AgEUR));
        ITransmuter transmuter = ITransmuter(_chainToContract(CHAIN_SOURCE, ContractType.TransmuterAgEUR));
        IAccessControlManager accessControlManager = transmuter.accessControlManager();

        GenericHarvester harvester = new GenericHarvester(
            maxSlippage,
            ONEINCH_ROUTER,
            ONEINCH_ROUTER,
            maxSwapSlippage,
            agToken,
            transmuter,
            accessControlManager,
            flashloan
        );
        console.log("HarvesterVault deployed at: ", address(harvester));

        vm.stopBroadcast();
    }
}