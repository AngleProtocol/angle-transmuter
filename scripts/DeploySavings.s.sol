// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "./utils/Utils.s.sol";
import "utils/src/Constants.sol";
import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
import "stringutils/strings.sol";
import { Savings } from "contracts/savings/Savings.sol";
import { IAccessControlManager } from "contracts/utils/AccessControl.sol";
import "oz/interfaces/IERC20.sol";
import "oz-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import { TransparentUpgradeableProxy } from "oz/proxy/transparent/TransparentUpgradeableProxy.sol";

import { ImmutableCreate2Factory } from "./utils/TransmuterDeploymentHelper.s.sol";

/// @dev To deploy on a different chain, just replace the chainId and be sure the sdk has the required addresses
contract DeploySavings is Utils {
    using stdJson for string;
    using strings for *;

    function run() external {
        // TODO: make sure that deployer has a 1 agEUR (=1e18) balance
        // TODO: change the chainId
        uint256 chainId = CHAIN_ETHEREUM;
        uint256 deployerPrivateKey = vm.deriveKey(vm.envString("MNEMONIC_MAINNET"), "m/44'/60'/0'/0/", 0);
        ImmutableCreate2Factory create2Factory = ImmutableCreate2Factory(IMMUTABLE_CREATE2_FACTORY_ADDRESS);
        string memory jsonVanity = vm.readFile(JSON_VANITY_PATH);
        bytes32 salt = jsonVanity.readBytes32(string.concat("$.", "salt"));
        vm.startBroadcast(deployerPrivateKey);

        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address: ", deployer);

        // Deploying the proxy.
        // To maintain chain consistency, we deploy with the deployer as a proxyAdmin before transferring
        // to another address
        // We use a contract that is widely deployed across many chains as an implementation to make it resilient
        // to possible implementation changes

        bytes memory emptyData;
        bytes memory initCode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            abi.encode(IMMUTABLE_CREATE2_FACTORY_ADDRESS, deployer, emptyData)
        );
        console.log("Proxy bytecode");
        console.logBytes(initCode);
        console.log("");
        /*
        address computedAddress = create2Factory.findCreate2Address(salt, initCode);
        console.log("Supposed to deploy: %s", computedAddress);
        if (computedAddress != 0x004626A008B1aCdC4c74ab51644093b155e59A23) revert();
        address saving = create2Factory.safeCreate2(salt, initCode);
        console.log("Savings deployed at: ", address(saving));
        // Deploying the implementation
        Savings savingsImpl = new Savings();
        TransparentUpgradeableProxy(payable(saving)).upgradeTo(address(savingsImpl));
        TransparentUpgradeableProxy(payable(saving)).changeAdmin(_chainToContract(chainId, ContractType.ProxyAdmin));
        IERC20MetadataUpgradeable(_chainToContract(chainId, ContractType.AgEUR)).approve(address(saving), 1e18);
        Savings(saving).initialize(
            IAccessControlManager(_chainToContract(chainId, ContractType.CoreBorrow)),
            IERC20MetadataUpgradeable(_chainToContract(chainId, ContractType.AgEUR)),
            "Staked agEUR",
            "stEUR",
            1
        );
        */
        vm.stopBroadcast();
    }
}
