// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/******************************************************************************\
* Authors: Timo Neumann <timo@fyde.fi>, Rohan Sundar <rohan@fyde.fi>
* EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
/******************************************************************************/

import "./States.t.sol";

// test proper deployment of diamond
contract TestDeployDiamond is StateDeployDiamond {
    // TEST CASES

    function testHasThreeFacets() public {
        assertEq(facetAddressList.length, 3);
    }

    function testFacetsHaveCorrectSelectors() public {
        for (uint i = 0; i < facetAddressList.length; i++) {
            bytes4[] memory fromLoupeFacet = ILoupe.facetFunctionSelectors(facetAddressList[i]);
            bytes4[] memory fromGenSelectors = generateSelectors(facetNames[i]);
            assertTrue(sameMembers(fromLoupeFacet, fromGenSelectors));
        }
    }

    function testSelectorsAssociatedWithCorrectFacet() public {
        for (uint i = 0; i < facetAddressList.length; i++) {
            bytes4[] memory fromGenSelectors = generateSelectors(facetNames[i]);
            for (uint j = 0; i < fromGenSelectors.length; i++) {
                assertEq(facetAddressList[i], ILoupe.facetAddress(fromGenSelectors[j]));
            }
        }
    }
}

contract TestAddFacets is StateDeployDiamond {
    function testAddOracleFacetFunctions() public {
        // check if functions added to diamond
        bytes4[] memory fromLoupeFacet = ILoupe.facetFunctionSelectors(address(oracleFacet));
        bytes4[] memory fromGenSelectors = generateSelectors("OracleFacet");
        assertTrue(sameMembers(fromLoupeFacet, fromGenSelectors));
    }

    function testAddActionsFacetFunctions() public {
        // check if functions added to diamond
        bytes4[] memory fromLoupeFacet = ILoupe.facetFunctionSelectors(address(actionsFacet));
        bytes4[] memory fromGenSelectors = generateSelectors("ActionsFacet");
        assertTrue(sameMembers(fromLoupeFacet, fromGenSelectors));
    }

    function testCanCallOracleFacetFunction() public {
        // try to call function on new Facet
        OracleFacet(address(diamond)).setOracleValue(address(this), 1);
        uint256 value = OracleFacet(address(diamond)).getOracleValue(address(this));
        assertEq(value, 1);
    }

    // Without Proxy
    function testBenchMark() public {
        // try to call function on new Facet
        OracleFacet(oracleFacet).setOracleValue(address(this), 1);
        uint256 value = OracleFacet(oracleFacet).getOracleValue(address(this));
        assertEq(value, 1);
    }

    // Test Actions facet
    function testCanCallActionsFacetFunction() public {
        OracleFacet(address(diamond)).setOracleValue(address(diamond), 1);
        uint256 value = ActionsFacet(address(diamond)).swapExact(
            0,
            0,
            address(diamond),
            address(diamond),
            address(diamond),
            0
        );
        assertEq(value, 1);
    }

    function testActionBenchmark() public {
        OracleFacet(oracleFacet).setOracleValue(address(oracleFacet), 1);
        uint256 value = ActionsFacet(address(actionsFacet)).swapExact(
            0,
            0,
            address(oracleFacet),
            address(oracleFacet),
            address(oracleFacet),
            0
        );
        assertEq(value, 1);
    }
}
