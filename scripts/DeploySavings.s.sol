// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { Utils } from "./utils/Utils.s.sol";
import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
import "stringutils/strings.sol";
import { Savings } from "contracts/savings/Savings.sol";
import { IAccessControlManager } from "contracts/utils/AccessControl.sol";
import "./Constants.s.sol";
import "oz/interfaces/IERC20.sol";
import "oz-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import { TransparentUpgradeableProxy } from "oz/proxy/transparent/TransparentUpgradeableProxy.sol";

import "./utils/TransmuterDeploymentHelper.s.sol";

/// @dev To deploy on a different chain, just replace the import of the `Constants.s.sol` file by a file which has the
/// constants defined for the chain of your choice.
contract DeploySavings is Utils {
    using stdJson for string;
    using strings for *;

    function run() external {
        // TODO: make sure that deployer has a 1 agEUR (=1e18) balance
        // TODO: check the import of the constants file if it corresponds to the chain you're deploying on
        uint256 deployerPrivateKey = vm.deriveKey(vm.envString("MNEMONIC_MAINNET"), "m/44'/60'/0'/0/", 0);
        ImmutableCreate2Factory create2Factory = ImmutableCreate2Factory(IMMUTABLE_CREATE2_FACTORY_ADDRESS);
        vm.startBroadcast(deployerPrivateKey);

        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address: ", deployer);

        // First deploying the implementation using create2 -> we do it this way in order not to make it dependent
        // on the nonce of the deployer. We choose to this extent a random salt

        bytes memory initCodeImplem = abi.encodePacked(type(Savings).creationCode, "");
        bytes32 saltImplem = 0xfda462548ce04282f4b6d6619823a7c64fdc01850000000000000000005af2a6;

        address computedAddressImplem = create2Factory.findCreate2Address(saltImplem, initCodeImplem);
        Savings savingsImpl = Savings(create2Factory.safeCreate2(saltImplem, initCodeImplem));
        console.log(computedAddressImplem, address(savingsImpl));

        // Then deploying the proxy

        bytes memory emptyData;
        bytes memory initCode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            abi.encode(computedAddressImplem, PROXY_ADMIN, emptyData)
        );
        console.logBytes(initCode);
        string memory jsonVanity = vm.readFile(JSON_VANITY_PATH);
        bytes32 salt = jsonVanity.readBytes32(string.concat("$.", "salt"));

        address computedAddress = create2Factory.findCreate2Address(salt, initCode);
        console.log("Supposed to deploy: %s", address(computedAddress));
        if (computedAddress != 0x004626fEE6FF73fBd42c36d07106fB683CB505CE) revert();
        Savings saving = Savings(create2Factory.safeCreate2(salt, initCode));
        console.log("Savings deployed at: ", address(saving));
        IERC20MetadataUpgradeable(CHAIN_AGEUR).approve(address(saving), 1e18);
        saving.initialize(
            IAccessControlManager(ACCESS_CONTROL_MANAGER),
            IERC20MetadataUpgradeable(CHAIN_AGEUR),
            "Staked agEUR",
            "stEUR",
            1
        );
        vm.stopBroadcast();
    }
}
