// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { Utils } from "./utils/Utils.s.sol";
import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
import "./Constants.s.sol";

import "contracts/utils/Errors.sol" as Errors;
import "contracts/transmuter/Storage.sol" as Storage;
import { Redeemer } from "contracts/transmuter/facets/Redeemer.sol";
import { ITransmuter } from "interfaces/ITransmuter.sol";

contract DeployRedeemer is Utils {
    using stdJson for string;

    string[] facetNames;
    address[] facetAddressList;

    ITransmuter transmuter = ITransmuter(0x00253582b2a3FE112feEC532221d9708c64cEFAb);
    address oldRedeemer = 0x8E669F6eF8485694196F32d568BA4Ac268b9FE8f;

    function run() external {
        // vm.startPrank(_chainToContract(CHAIN_SOURCE, ContractType.GovernorMultisig);

        uint256 deployerPrivateKey = vm.deriveKey(vm.envString("MNEMONIC_FORK"), 0);
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Address: %s", deployer);
        vm.startBroadcast(deployerPrivateKey);

        facetNames.push("Redeemer");
        facetAddressList.push(address(new Redeemer()));

        string memory json = vm.readFile(JSON_SELECTOR_PATH);
        // Build appropriate payload
        uint256 n = facetNames.length;
        Storage.FacetCut[] memory cut = new Storage.FacetCut[](n);
        Storage.FacetCut[] memory removeCut = new Storage.FacetCut[](n);
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

            removeCut[i] = Storage.FacetCut({
                facetAddress: address(0),
                action: Storage.FacetCutAction.Remove,
                functionSelectors: selectors
            });
        }

        console.log("Redeemer deployed at: %s", facetAddressList[0]);

        vm.stopBroadcast();

        // // if fork
        // bytes memory callData;
        // transmuter.diamondCut(removeCut, address(0), callData);
        // transmuter.diamondCut(cut, address(0), callData);
        // vm.stopPrank();
    }
}
