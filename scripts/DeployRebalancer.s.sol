// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "./utils/Utils.s.sol";
import { console } from "forge-std/console.sol";
import { Rebalancer } from "contracts/helpers/Rebalancer.sol";
import { IAccessControlManager } from "contracts/utils/AccessControl.sol";
import { ITransmuter } from "contracts/interfaces/ITransmuter.sol";
import "./Constants.s.sol";
import "oz/interfaces/IERC20.sol";
import "oz-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

contract DeployRebalancer is Utils {
    function run() external {
        uint256 deployerPrivateKey = vm.deriveKey(vm.envString("MNEMONIC_FORK"), "m/44'/60'/0'/0/", 0);
        vm.startBroadcast(deployerPrivateKey);

        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address: ", deployer);
        Rebalancer rebalancer = new Rebalancer(
            IAccessControlManager(_chainToContract(CHAIN_SOURCE, ContractType.CoreBorrow)),
            ITransmuter(_chainToContract(CHAIN_SOURCE, ContractType.TransmuterAgEUR))
        );
        console.log("Rebalancer deployed at: ", address(rebalancer));

        vm.stopBroadcast();
    }
}
