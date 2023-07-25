// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { Utils } from "../Utils.s.sol";
import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
import "stringutils/strings.sol";
import "contracts/utils/Errors.sol" as Errors;
import "contracts/transmuter/Storage.sol" as Storage;
import { DiamondEtherscan } from "contracts/transmuter/facets/DiamondEtherscan.sol";
import { DummyDiamondImplementation } from "../generated/DummyDiamondImplementation.sol";
import { ITransmuter } from "interfaces/ITransmuter.sol";

contract VerifyProxyEtherscanGnosis is Utils {
    using strings for *;
    using stdJson for string;

    ITransmuter transmuter;
    DiamondEtherscan etherscanFacet;
    string[] facetNames;
    address[] facetAddressList;

    function run() external {
        uint256 deployerPrivateKey = vm.deriveKey(vm.envString("MNEMONIC_GNOSIS"), 0);
        vm.startBroadcast(deployerPrivateKey);

        address deployer = vm.addr(deployerPrivateKey);
        console.log("address: %s", deployer);

        /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        DEPLOY                                                      
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

        transmuter = ITransmuter(0x4A44f77978Daa3E92Eb3D97210bd11645cF935Ab);

        // deploy dummy implementation
        DummyDiamondImplementation dummyImpl = new DummyDiamondImplementation();
        //DummyDiamondImplementation dummyImpl = DummyDiamondImplementation(0x8911084eF979Ac1B02D6d9AAbfAD86927C5b1589);
        _deployDiamondEtherscan();
        transmuter.setDummyImplementation(address(dummyImpl));

        vm.stopBroadcast();
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        HELPERS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    // @dev Deploys diamond and connects facets
    function _deployDiamondEtherscan() internal {
        // Deploy every facet
        facetNames.push("DiamondEtherscan");
        etherscanFacet = new DiamondEtherscan();
        // etherscanFacet = DiamondEtherscan(0xC492fBAe68cE6C5E14C7ed5cd8a59babD5c90e4C);
        facetAddressList.push(address(etherscanFacet));

        string memory json = vm.readFile(JSON_SELECTOR_PATH);

        // Build appropriate payload
        uint256 n = facetNames.length;
        Storage.FacetCut[] memory cut = new Storage.FacetCut[](n);
        for (uint256 i = 0; i < n; ++i) {
            bytes4[] memory selectors = _arrayBytes32ToBytes4(
                json.readBytes32Array(string.concat("$.", facetNames[i]))
            );
            cut[i] = Storage.FacetCut({
                facetAddress: facetAddressList[i],
                action: Storage.FacetCutAction.Add,
                functionSelectors: selectors
            });
        }

        // add facet
        transmuter.diamondCut(cut, address(0), hex"");
    }
}
