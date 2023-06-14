// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import { IMockFacet, MockPureFacet } from "mock/MockFacets.sol";

import "contracts/transmuter/Storage.sol";
import { Test } from "contracts/transmuter/configs/Test.sol";
import { DiamondCut } from "contracts/transmuter/facets/DiamondCut.sol";
import "contracts/utils/Constants.sol";

import { Fixture } from "../Fixture.sol";

contract Test_DiamondLoupe is Fixture {
    address pureFacet = address(new MockPureFacet());

    function test_Facets() public {
        Facet[] memory facets = transmuter.facets();

        // DiamondCut, DiamondLoupe, Getters, Redeemer, RewardHandler, Setters, Swapper
        for (uint256 i; i < facetNames.length; ++i) {
            assertEq(facets[i].facetAddress, address(facetAddressList[i])); // Check address

            bytes4[] memory selectors = generateSelectors(facetNames[i]);
            assertEq(facets[i].functionSelectors.length, selectors.length); // Check selectors length

            for (uint256 j; j < selectors.length; ++j) {
                assertEq(facets[i].functionSelectors[j], selectors[j]); // Check all selectors are present
            }
        }
    }

    function test_FacetFunctionSelectors() public {
        // Create a facet added in 2 phases to test the robustness
        bytes4[] memory selectors = generateSelectors("IMockFacet");

        bytes4[] memory auxSelectors = new bytes4[](1);
        auxSelectors[0] = selectors[0];

        FacetCut[] memory facetCut = new FacetCut[](1);
        facetCut[0] = FacetCut({
            facetAddress: address(pureFacet),
            action: FacetCutAction.Add,
            functionSelectors: auxSelectors
        });

        hoax(governor);
        transmuter.diamondCut(facetCut, address(0), ""); // Deploy only the first selector

        bytes4[] memory fetchedSelectors = transmuter.facetFunctionSelectors(pureFacet);

        assertEq(fetchedSelectors.length, 1); // Check only the first selector is accessible
        assertEq(fetchedSelectors[0], selectors[0]);

        auxSelectors[0] = selectors[1];
        facetCut[0] = FacetCut({
            facetAddress: address(pureFacet),
            action: FacetCutAction.Add,
            functionSelectors: auxSelectors
        });

        hoax(governor);
        transmuter.diamondCut(facetCut, address(0), ""); // Deploy the second selector

        fetchedSelectors = transmuter.facetFunctionSelectors(pureFacet);

        assertEq(fetchedSelectors.length, 2); // Check only the first selector is accessible
        assertEq(fetchedSelectors[0], selectors[0]);
        assertEq(fetchedSelectors[1], selectors[1]);
    }

    function test_FacetAddresses() public {
        address[] memory facetAddresses = transmuter.facetAddresses();
        for (uint256 i; i < facetAddresses.length; ++i) {
            assertEq(facetAddresses[i], facetAddressList[i]);
        }
    }

    function test_FacetAddress() public {
        for (uint256 i; i < facetNames.length; ++i) {
            bytes4[] memory selectors = generateSelectors(facetNames[i]);

            for (uint256 j; j < selectors.length; ++j) {
                assertEq(transmuter.facetAddress(selectors[j]), facetAddressList[i]); // Check all selectors are present
            }
        }
    }
}
