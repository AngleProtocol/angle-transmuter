// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { Utils } from "./utils/Utils.s.sol";
import { TransmuterDeploymentHelper } from "./utils/TransmuterDeploymentHelper.s.sol";
import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
import "stringutils/strings.sol";
import "./Constants.s.sol";

import { CollateralSetupProd, ProductionUSD } from "contracts/transmuter/configs/ProductionUSD.sol";
import "contracts/transmuter/Storage.sol" as Storage;
import { DiamondCut } from "contracts/transmuter/facets/DiamondCut.sol";
import { DiamondEtherscan } from "contracts/transmuter/facets/DiamondEtherscan.sol";
import { DiamondLoupe } from "contracts/transmuter/facets/DiamondLoupe.sol";
import { DiamondProxy } from "contracts/transmuter/DiamondProxy.sol";
import { Getters } from "contracts/transmuter/facets/Getters.sol";
import { Redeemer } from "contracts/transmuter/facets/Redeemer.sol";
import { RewardHandler } from "contracts/transmuter/facets/RewardHandler.sol";
import { SettersGovernor } from "contracts/transmuter/facets/SettersGovernor.sol";
import { SettersGuardian } from "contracts/transmuter/facets/SettersGuardian.sol";
import { DummyDiamondImplementation } from "./generated/DummyDiamondImplementation.sol";
import { Swapper } from "contracts/transmuter/facets/Swapper.sol";
import { ITransmuter } from "interfaces/ITransmuter.sol";

import { MockTreasury } from "test/mock/MockTreasury.sol";

contract DeployTransmuterWithoutFacets is TransmuterDeploymentHelper {
    function run() external {
        // TODO: make sure that selectors are well generated `yarn generate` before running this script
        // Here the `selectors.json` file is normally up to date
        uint256 deployerPrivateKey = vm.deriveKey(vm.envString("MNEMONIC_MAINNET"), "m/44'/60'/0'/0/", 0);
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Address: %s", deployer);
        console.log(deployer.balance);
        vm.startBroadcast(deployerPrivateKey);

        // TODO change before actual deployment and replace with actual addresses inherited from other
        // deployment

        address agToken = 0x0000206329b97DB379d5E1Bf586BbDB969C63274;
        address treasury = 0xf8588520E760BB0b3bDD62Ecb25186A28b0830ee;
        address accessControlManager = 0x3fc5a1bd4d0A435c55374208A6A81535A1923039;

        config = address(new ProductionUSD()); // Config
        // Already deployed
        address dummyImplementation = 0x5d34839A3d4051f630D36e26698d53c58DD39072;
        ITransmuter transmuter = _deployTransmuterWithoutFacets(
            config,
            abi.encodeWithSelector(
                ProductionUSD.initialize.selector,
                accessControlManager,
                agToken,
                dummyImplementation
            )
        );

        console.log("Transmuter deployed at: %s", address(transmuter));

        MockTreasury(treasury).addMinter(address(transmuter));
        vm.stopBroadcast();
        // TODO: test minting afterwards
    }
}
