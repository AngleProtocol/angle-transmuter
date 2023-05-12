// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { IKheops } from "contracts/kheops/interfaces/IKheops.sol";
import { DiamondProxy } from "contracts/kheops/DiamondProxy.sol";

import { DiamondCut } from "contracts/kheops/facets/DiamondCut.sol";
import { DiamondLoupe } from "contracts/kheops/facets/DiamondLoupe.sol";
import { Swapper } from "contracts/kheops/facets/Swapper.sol";
import { Getters } from "contracts/kheops/facets/Getters.sol";
import { Redeemer } from "contracts/kheops/facets/Redeemer.sol";
import { Setters } from "contracts/kheops/facets/Setters.sol";

import "contracts/kheops/Storage.sol";
import "contracts/utils/Errors.sol";
import "./Helper.sol";

abstract contract Kheops is Helper {
    // Diamond
    IKheops kheops;

    string[] facetNames;
    address[] facetAddressList;

    // @dev Deploys diamond and connects facets
    function deployKheops(address _init, bytes memory _calldata) public virtual {
        // Deploy every facet
        facetNames.push("DiamondCut");
        facetAddressList.push(address(new DiamondCut()));

        facetNames.push("DiamondLoupe");
        facetAddressList.push(address(new DiamondLoupe()));

        facetNames.push("Getters");
        facetAddressList.push(address(new Getters()));

        facetNames.push("Redeemer");
        facetAddressList.push(address(new Redeemer()));

        facetNames.push("Setters");
        facetAddressList.push(address(new Setters()));

        facetNames.push("Swapper");
        facetAddressList.push(address(new Swapper()));

        // Build appropriate payload
        uint256 n = facetNames.length;
        FacetCut[] memory cut = new FacetCut[](n);
        for (uint256 i = 0; i < n; i++) {
            cut[i] = FacetCut({
                facetAddress: facetAddressList[i],
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors(facetNames[i])
            });
        }

        // Deploy diamond
        kheops = IKheops(address(new DiamondProxy(cut, _init, _calldata)));
    }

    // @dev Helper to deploy a given Facet
    function deployFacet(address facet, string memory name) public {
        bytes4[] memory fromGenSelectors = generateSelectors(name);

        // Array of functions to add
        FacetCut[] memory facetCut = new FacetCut[](1);
        facetCut[0] = FacetCut({
            facetAddress: address(facet),
            action: FacetCutAction.Add,
            functionSelectors: fromGenSelectors
        });

        // Add functions to diamond
        kheops.diamondCut(facetCut, address(0x0), "");
    }
}
