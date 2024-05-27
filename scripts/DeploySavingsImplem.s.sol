// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "./utils/Utils.s.sol";
import "utils/src/Constants.sol";
import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
import "stringutils/strings.sol";
import { SavingsNameable } from "contracts/savings/nameable/SavingsNameable.sol";
import { IAccessControlManager } from "contracts/utils/AccessControl.sol";
import "oz/interfaces/IERC20.sol";
import "oz-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import { ImmutableCreate2Factory } from "./utils/TransmuterDeploymentHelper.s.sol";

contract DeploySavingsImplem is Utils {
    using stdJson for string;
    using strings for *;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        ImmutableCreate2Factory create2Factory = ImmutableCreate2Factory(IMMUTABLE_CREATE2_FACTORY_ADDRESS);
        bytes32 salt = 0xa9ddd91249dfdd450e81e1c56ab60e1a62651701000000000000000000438ec0;

        vm.startBroadcast(deployerPrivateKey);

        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address: ", deployer);

        bytes memory emptyData;
        bytes memory initCode = abi.encodePacked(
            type(SavingsNameable).creationCode,
            abi.encode(IMMUTABLE_CREATE2_FACTORY_ADDRESS, deployer, emptyData)
        );
        address computedAddress = create2Factory.findCreate2Address(salt, initCode);
        console.log("Supposed to deploy: %s", computedAddress);
        if (computedAddress != 0x2C28Bd22aB59341892e85aD76d159d127c4B03FA) revert();
        /*
        address saving = create2Factory.safeCreate2(salt, initCode);
        console.log("Savings implementation deployed at: ", address(saving));
        */

        vm.stopBroadcast();
    }
}
