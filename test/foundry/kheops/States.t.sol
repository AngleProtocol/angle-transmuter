// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/******************************************************************************\
* Authors: Timo Neumann <timo@fyde.fi>, Rohan Sundar <rohan@fyde.fi>
* EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
* Abstract Contracts for the shared setup of the tests
/******************************************************************************/

import "../../../contracts/interfaces/IDiamondCut.sol";
import "../../../contracts/kheops/facets/DiamondCut.sol";
import "../../../contracts/kheops/facets/DiamondLoupe.sol";
import "../../../contracts/utils/Errors.sol";
import "../../../contracts/kheops/DiamondProxy.sol";
import "./Helper.sol";

abstract contract StateDeployDiamond is HelperContract {
    //contract types of facets to be deployed
    Diamond diamond;
    DiamondCutFacet dCutFacet;
    DiamondLoupeFacet dLoupe;
    OwnershipFacet ownerF;

    //interfaces with Facet ABI connected to diamond address
    IDiamondLoupe ILoupe;
    IDiamondCut ICut;

    string[] facetNames;
    address[] facetAddressList;

    // facets
    OracleFacet oracleFacet;
    ActionsFacet actionsFacet;

    // deploys diamond and connects facets
    function setUp() public virtual {
        //deploy facets
        dCutFacet = new DiamondCutFacet();
        dLoupe = new DiamondLoupeFacet();
        ownerF = new OwnershipFacet();
        facetNames = ["DiamondCutFacet", "DiamondLoupeFacet", "OwnershipFacet"];

        // diamond arguments
        DiamondArgs memory _args = DiamondArgs({ owner: address(this), init: address(0), initCalldata: " " });

        // FacetCut with CutFacet for initialisation
        FacetCut[] memory cut0 = new FacetCut[](1);
        cut0[0] = FacetCut({
            facetAddress: address(dCutFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: generateSelectors("DiamondCutFacet")
        });

        // deploy diamond
        diamond = new Diamond(cut0, _args);

        //upgrade diamond with facets

        //build cut struct
        FacetCut[] memory cut = new FacetCut[](2);

        cut[0] = (
            FacetCut({
                facetAddress: address(dLoupe),
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors("DiamondLoupeFacet")
            })
        );

        cut[1] = (
            FacetCut({
                facetAddress: address(ownerF),
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors("OwnershipFacet")
            })
        );

        // initialise interfaces
        ILoupe = IDiamondLoupe(address(diamond));
        ICut = IDiamondCut(address(diamond));

        //upgrade diamond
        ICut.diamondCut(cut, address(0x0), "");

        // get all addresses
        facetAddressList = ILoupe.facetAddresses();

        // Facets
        oracleFacet = new OracleFacet();
        deployFacet(address(oracleFacet), "OracleFacet");
        actionsFacet = new ActionsFacet();
        deployFacet(address(actionsFacet), "ActionsFacet");
    }

    function deployFacet(address facet, string memory name) public {
        bytes4[] memory fromGenSelectors = generateSelectors(name);

        // array of functions to add
        FacetCut[] memory facetCut = new FacetCut[](1);
        facetCut[0] = FacetCut({
            facetAddress: address(facet),
            action: FacetCutAction.Add,
            functionSelectors: fromGenSelectors
        });

        // add functions to diamond
        ICut.diamondCut(facetCut, address(0x0), "");
    }
}
