// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "./utils/Utils.s.sol";
import { console } from "forge-std/console.sol";
import { RebalancerFlashloan } from "contracts/helpers/RebalancerFlashloan.sol";
import { IAccessControlManager } from "contracts/utils/AccessControl.sol";
import { ITransmuter } from "contracts/interfaces/ITransmuter.sol";
import { IERC3156FlashLender } from "oz/interfaces/IERC3156FlashLender.sol";
import "./Constants.s.sol";
import "oz/interfaces/IERC20.sol";
import "oz-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

contract DeployRebalancerFlashloan is Utils {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address: ", deployer);
        console.log(address(IAccessControlManager(_chainToContract(CHAIN_SOURCE, ContractType.CoreBorrow))));
        console.log(address(ITransmuter(_chainToContract(CHAIN_SOURCE, ContractType.TransmuterAgUSD))));
        RebalancerFlashloan rebalancer = new RebalancerFlashloan(
            IAccessControlManager(_chainToContract(CHAIN_SOURCE, ContractType.CoreBorrow)),
            ITransmuter(_chainToContract(CHAIN_SOURCE, ContractType.TransmuterAgUSD)),
            IERC3156FlashLender(0x4A2FF9bC686A0A23DA13B6194C69939189506F7F)
        );
        /*
        RebalancerFlashloan rebalancer = new RebalancerFlashloan(
            IAccessControlManager(0x5bc6BEf80DA563EBf6Df6D6913513fa9A7ec89BE),
            ITransmuter(0x222222fD79264BBE280b4986F6FEfBC3524d0137),
            IERC3156FlashLender(0x4A2FF9bC686A0A23DA13B6194C69939189506F7F)
        );
        */
        console.log("Rebalancer deployed at: ", address(rebalancer));

        vm.stopBroadcast();
    }
}
