// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "./utils/Utils.s.sol";
import { console } from "forge-std/console.sol";
import { RebalancerFlashloanSwap } from "contracts/helpers/RebalancerFlashloanSwap.sol";
import { IAccessControlManager } from "contracts/utils/AccessControl.sol";
import { ITransmuter } from "contracts/interfaces/ITransmuter.sol";
import { IERC3156FlashLender } from "oz/interfaces/IERC3156FlashLender.sol";
import "./Constants.s.sol";
import "oz/interfaces/IERC20.sol";
import "oz-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

contract DeployRebalancerFlashloanSwapSwap is Utils {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address: ", deployer);
        console.log(address(IAccessControlManager(_chainToContract(CHAIN_SOURCE, ContractType.CoreBorrow))));
        console.log(address(ITransmuter(_chainToContract(CHAIN_SOURCE, ContractType.TransmuterAgUSD))));
        RebalancerFlashloanSwap rebalancer = new RebalancerFlashloanSwap(
            IAccessControlManager(_chainToContract(CHAIN_SOURCE, ContractType.CoreBorrow)),
            ITransmuter(_chainToContract(CHAIN_SOURCE, ContractType.TransmuterAgUSD)),
            IERC3156FlashLender(_chainToContract(CHAIN_SOURCE, ContractType.FlashLoan)),
            ONEINCH_ROUTER,
            ONEINCH_ROUTER,
            50 // 0.5%
        );

        console.log("Rebalancer deployed at: ", address(rebalancer));

        vm.stopBroadcast();
    }
}
