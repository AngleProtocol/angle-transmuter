// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { Utils } from "./Utils.s.sol";
import { console } from "forge-std/console.sol";
import { Savings } from "contracts/savings/Savings.sol";
import { IAccessControlManager } from "contracts/utils/AccessControl.sol";
import "./Constants.s.sol";
import "oz/interfaces/IERC20.sol";
import "oz-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

/// @dev To deploy on a different chain, just replace the import of the `Constants.s.sol` file by a file which has the
/// constants defined for the chain of your choice.
contract DeploySavings is Utils {
    function run() external {
        // TODO: make sure that deployer has a 1 agEUR (=1e18) balance
        uint256 deployerPrivateKey = vm.deriveKey(vm.envString("MNEMONIC_FORK"), "m/44'/60'/0'/0/", 0);
        vm.startBroadcast(deployerPrivateKey);

        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address: ", deployer);

        Savings savingsImpl = new Savings();
        bytes memory emptyData;
        Savings saving = Savings(deployUpgradeable(address(savingsImpl), PROXY_ADMIN, emptyData));
        console.log("Savings deployed at: ", address(saving));
        IERC20MetadataUpgradeable(CHAIN_AGEUR).approve(address(saving), 1e18);
        saving.initialize(
            IAccessControlManager(ACCESS_CONTROL_MANAGER),
            IERC20MetadataUpgradeable(CHAIN_AGEUR),
            "agEUR Savings Account",
            "sagEUR",
            1
        );

        vm.stopBroadcast();
    }
}
