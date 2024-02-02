// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "./utils/Utils.s.sol";
import { console } from "forge-std/console.sol";
import { Savings } from "contracts/savings/Savings.sol";
import { IAccessControlManager } from "contracts/utils/AccessControl.sol";
import "./Constants.s.sol";
import "oz/interfaces/IERC20.sol";
import "oz-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

/// @dev To deploy on a different chain, just replace the chainId and be sure the sdk has the required addresses
/// @dev This is a vanilla deployment file to easily and rapidly deploy a savings implementation at a random address
contract DeploySavingsNoCreate2 is Utils {
    function run() external {
        // TODO: make sure that deployer has a 1 agEUR (=1e18) balance
        // TODO: change the chainId
        uint256 chainId = CHAIN_ETHEREUM;
        uint256 deployerPrivateKey = vm.deriveKey(vm.envString("MNEMONIC_FORK"), "m/44'/60'/0'/0/", 0);
        vm.startBroadcast(deployerPrivateKey);

        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address: ", deployer);

        Savings savingsImpl = new Savings();
        bytes memory emptyData;
        Savings saving = Savings(
            _deployUpgradeable(address(savingsImpl), _chainToContract(chainId, ContractType.ProxyAdmin), emptyData)
        );
        console.log("Savings deployed at: ", address(saving));
        IERC20MetadataUpgradeable(_chainToContract(chainId, ContractType.AgEUR)).approve(address(saving), 1e18);
        saving.initialize(
            IAccessControlManager(_chainToContract(chainId, ContractType.CoreBorrow)),
            IERC20MetadataUpgradeable(_chainToContract(chainId, ContractType.AgEUR)),
            "agEUR Savings Account",
            "sagEUR",
            1
        );

        vm.stopBroadcast();
    }
}
