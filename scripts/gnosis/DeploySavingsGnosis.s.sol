// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { Utils } from "../Utils.s.sol";
import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
import "stringutils/strings.sol";
import { Savings } from "contracts/savings/Savings.sol";
import { AccessControl, IAccessControlManager } from "contracts/utils/AccessControl.sol";
import { MockTokenPermit } from "../../../test/mock/MockTokenPermit.sol";
import "oz/interfaces/IERC20.sol";
import "oz-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

contract DeploySavingsGnosis is Utils {
    using strings for *;
    using stdJson for string;

    // the allowance address was obtained by running the script and check the deployed address of the savings proxy
    address constant SAVING_ADDRESS = 0x9De6Efe3454F8EFF8C8C8d1314CD019AF2432e59;
    ProxyAdmin proxy;

    function run() external {
        uint256 deployerPrivateKey = vm.deriveKey(vm.envString("MNEMONIC_GNOSIS"), 0);
        vm.startBroadcast(deployerPrivateKey);

        address deployer = vm.addr(deployerPrivateKey);
        console.log("address: %s", deployer);

        /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        DEPLOY                                                      
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/
        // Deploy fakes Core borrow, agEUR, and collaterals

        proxy = new ProxyAdmin();
        console.log("Proxy deployed at: %s", address(proxy));

        IAccessControlManager coreBorrow = IAccessControlManager(0xBDbdF128368De1cf6a3Aa37f67Bc19405c96f49F);
        IERC20MetadataUpgradeable agEUR = IERC20MetadataUpgradeable(0x5fE0E497Ac676d8bA78598FC8016EBC1E6cE14a3);

        MockTokenPermit(address(agEUR)).mint(address(deployer), 1e18);
        MockTokenPermit(address(agEUR)).setAllowance(address(deployer), SAVING_ADDRESS);

        Savings savingsImpl = new Savings();
        Savings saving = Savings(
            deployUpgradeable(
                address(savingsImpl),
                address(proxy),
                abi.encodeWithSelector(Savings.initialize.selector, coreBorrow, agEUR, "Mock-sagEUR", "Mock-sagEUR", 1)
            )
        );
        console.log("Savings deployed at: %s", address(saving));

        vm.stopBroadcast();
    }
}
