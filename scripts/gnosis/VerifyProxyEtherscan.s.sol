// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { Utils } from "../Utils.s.sol";
import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
import "stringutils/strings.sol";
import "contracts/utils/Errors.sol" as Errors;
import "contracts/transmuter/Storage.sol" as Storage;
import { DiamondEtherscanFacet } from "contracts/transmuter/facets/DiamondEtherscanFacet.sol";
import { DummyDiamondImplementation } from "../generated/DummyDiamondImplementation.sol";
import { ITransmuter } from "interfaces/ITransmuter.sol";

contract VerifyProxyEtherscan is Utils {
    using strings for *;
    using stdJson for string;

    ITransmuter transmuter;
    DiamondEtherscanFacet etherscanFacet;
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

        transmuter = ITransmuter(0x1A42a30dCbA20A22b69C40098d89cB7304f429B9);

        // deploy dummy implementation
        DummyDiamondImplementation dummyImpl = new DummyDiamondImplementation();
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
        facetNames.push("DiamondEtherscanFacet");
        etherscanFacet = new DiamondEtherscanFacet();
        facetAddressList.push(address(etherscanFacet));

        // Build appropriate payload
        uint256 n = facetNames.length;
        Storage.FacetCut[] memory cut = new Storage.FacetCut[](n);
        for (uint256 i = 0; i < n; ++i) {
            cut[i] = Storage.FacetCut({
                facetAddress: facetAddressList[i],
                action: Storage.FacetCutAction.Add,
                functionSelectors: _generateSelectors(facetNames[i])
            });
        }

        // add facet
        transmuter.diamondCut(cut, address(0), hex"");
    }
}
