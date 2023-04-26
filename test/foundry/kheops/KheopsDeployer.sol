// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/******************************************************************************\
* Authors: Timo Neumann <timo@fyde.fi>, Rohan Sundar <rohan@fyde.fi>
* EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
* Abstract Contracts for the shared setup of the tests
/******************************************************************************/

import { IKheops } from "../../../contracts/kheops/interfaces/IKheops.sol";
import { DiamondCut } from "../../../contracts/kheops/facets/DiamondCut.sol";
import { DiamondLoupe } from "../../../contracts/kheops/facets/DiamondLoupe.sol";
import { DiamondProxy } from "../../../contracts/kheops/DiamondProxy.sol";

import "../../../contracts/kheops/Storage.sol";
import "../../../contracts/utils/Errors.sol";
import "./Helper.sol";

abstract contract KheopsDeployer is Helper {
    // Diamond
    IKheops kheops;

    // Facets
    DiamondCut diamondCut;
    DiamondLoupe diamondLoupe;

    string[] facetNames;
    address[] facetAddressList;

    // @dev Deploys diamond and connects facets
    function deployKheops(address _init, bytes memory _calldata) public virtual {
        FacetCut[] memory cut = new FacetCut[](1);

        diamondCut = new DiamondCut();
        cut[0] = FacetCut({
            facetAddress: address(diamondCut),
            action: FacetCutAction.Add,
            functionSelectors: generateSelectors("DiamondCut")
        });

        cut[1] = FacetCut({
            facetAddress: address(diamondLoupe),
            action: FacetCutAction.Add,
            functionSelectors: generateSelectors("DiamondLoupe")
        });

        // Deploy Config and build payload
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
