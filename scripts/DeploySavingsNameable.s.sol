// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "./utils/Utils.s.sol";
import "utils/src/Constants.sol";
import { console } from "forge-std/console.sol";
import { CHAIN_SOURCE } from "./Constants.s.sol";
import { Savings } from "contracts/savings/Savings.sol";
import "oz/interfaces/IERC20.sol";
import { SavingsNameable } from "contracts/savings/nameable/SavingsNameable.sol";

/// @dev To deploy on a different chain, just replace the chainId and be sure the sdk has the required addresses
contract DeploySavingsNameable is Utils {
    function run() external {
        uint256 chainId = CHAIN_SOURCE;
        uint256 deployerPrivateKey = vm.deriveKey(vm.envString("MNEMONIC_MAINNET"), "m/44'/60'/0'/0/", 0);

        vm.startBroadcast(deployerPrivateKey);

        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address: ", deployer);

        SavingsNameable savingsImpl = new SavingsNameable();

        console.log("New Savings Implementation deployed at: ", address(savingsImpl));

        // TODO run the updateAndCall by the proxy admin
        // bytes memory data = abi.encodeWithSelector(SavingsNameable.setNameAndSymbol.selector, "Staked EURA", "stEURA");
        // TransparentUpgradeableProxy(_chainToContract(chainId, ContractType.ProxyAdmin)).upgradeAndCall(0, address(savingsImpl), _chainToContract(chainId, ContractType.StEUR), data);

        vm.stopBroadcast();
    }
}
