// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { Utils } from "./Utils.s.sol";
import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
import "stringutils/strings.sol";
import "./Constants.s.sol";

import { CollateralSetupProd, Production } from "contracts/transmuter/configs/Production.sol";
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

contract DeployTransmuter is Utils {
    using strings for *;
    using stdJson for string;

    address public config;
    string[] facetNames;
    address[] facetAddressList;

    function run() external {
        // TODO: make sure that selectors are well generated `yarn generate` before running this script
        uint256 deployerPrivateKey = vm.deriveKey(vm.envString("MNEMONIC_FORK"), "m/44'/60'/0'/0/", 0);
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Address: %s", deployer);
        console.log(deployer.balance);
        vm.startBroadcast(deployerPrivateKey);

        // Config
        config = address(new Production());
        address dummyImplementation = address(new DummyDiamondImplementation());
        ITransmuter transmuter = _deployTransmuter(
            config,
            abi.encodeWithSelector(Production.initialize.selector, CORE_BORROW, AGEUR, dummyImplementation)
        );

        console.log("Transmuter deployed at: %s", address(transmuter));
        vm.stopBroadcast();
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        HELPERS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    // @dev Deploys diamond and connects facets
    function _deployTransmuter(
        address _init,
        bytes memory _calldata
    ) internal virtual returns (ITransmuter transmuter) {
        // Deploy every facet
        facetNames.push("DiamondCut");
        facetAddressList.push(address(new DiamondCut()));

        facetNames.push("DiamondLoupe");
        facetAddressList.push(address(new DiamondLoupe()));

        facetNames.push("Getters");
        facetAddressList.push(address(new Getters()));

        facetNames.push("Redeemer");
        facetAddressList.push(address(new Redeemer()));

        facetNames.push("RewardHandler");
        facetAddressList.push(address(new RewardHandler()));

        facetNames.push("SettersGovernor");
        facetAddressList.push(address(new SettersGovernor()));

        facetNames.push("SettersGuardian");
        facetAddressList.push(address(new SettersGuardian()));

        facetNames.push("Swapper");
        facetAddressList.push(address(new Swapper()));

        facetNames.push("DiamondEtherscan");
        facetAddressList.push(address(new DiamondEtherscan()));

        string memory json = vm.readFile(JSON_SELECTOR_PATH);
        // Build appropriate payload
        uint256 n = facetNames.length;
        Storage.FacetCut[] memory cut = new Storage.FacetCut[](n);
        for (uint256 i = 0; i < n; ++i) {
            // Get Selectors from json
            bytes4[] memory selectors = _arrayBytes32ToBytes4(
                json.readBytes32Array(string.concat("$.", facetNames[i]))
            );
            cut[i] = Storage.FacetCut({
                facetAddress: facetAddressList[i],
                action: Storage.FacetCutAction.Add,
                functionSelectors: selectors
            });
        }

        // Deploy diamond
        transmuter = ITransmuter(address(new DiamondProxy(cut, _init, _calldata)));
    }
}
