// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "./utils/Utils.s.sol";
import "utils/src/Constants.sol";
import { console } from "forge-std/console.sol";
import "oz/interfaces/IERC20.sol";
import { SavingsNameable } from "contracts/savings/nameable/SavingsNameable.sol";

/// @dev To deploy on a different chain, just replace the chainId and be sure the sdk has the required addresses
contract DeploySavingsNameable is Utils {
    function run() external {
        uint256 privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(privateKey);
        address executor = vm.addr(privateKey);
        vm.label(executor, "Executor");
        SavingsNameable savingsImpl = new SavingsNameable();
        console.log("New Savings Implementation deployed at: ", address(savingsImpl));
        vm.stopBroadcast();
    }
}
