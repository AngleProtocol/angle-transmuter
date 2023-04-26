// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./KheopsDeployer.sol";

contract TestDeployKheops is KheopsDeployer {
    // TODO PREPARE SETUP
    function testHasThreeFacets() public {
        assertEq(facetAddressList.length, 3);
    }

    function testFacetsHaveCorrectSelectors() public {
        for (uint i = 0; i < facetAddressList.length; i++) {
            bytes4[] memory fromLoupeFacet = kheops.facetFunctionSelectors(facetAddressList[i]);
            bytes4[] memory fromGenSelectors = generateSelectors(facetNames[i]);
            assertTrue(sameMembers(fromLoupeFacet, fromGenSelectors));
        }
    }

    function testSelectorsAssociatedWithCorrectFacet() public {
        for (uint i = 0; i < facetAddressList.length; i++) {
            bytes4[] memory fromGenSelectors = generateSelectors(facetNames[i]);
            for (uint j = 0; i < fromGenSelectors.length; i++) {
                assertEq(facetAddressList[i], kheops.facetAddress(fromGenSelectors[j]));
            }
        }
    }
}
