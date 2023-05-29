// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { IERC20 } from "oz/interfaces/IERC20.sol";

import { IAccessControlManager } from "interfaces/IAccessControlManager.sol";
import { IAgToken } from "interfaces/IAgToken.sol";
import { AggregatorV3Interface } from "interfaces/external/chainlink/AggregatorV3Interface.sol";

import { MockAccessControlManager } from "mock/MockAccessControlManager.sol";
import { MockChainlinkOracle } from "mock/MockChainlinkOracle.sol";
import { MockTokenPermit } from "mock/MockTokenPermit.sol";

import { Test } from "contracts/transmuter/configs/Test.sol";
import { LibRedeemer } from "contracts/transmuter/libraries/LibRedeemer.sol";
import "contracts/transmuter/Storage.sol";
import "contracts/utils/Constants.sol";
import "contracts/utils/Errors.sol";

import { Fixture } from "../Fixture.sol";

contract TestTransmuter is Fixture {
    function test_FacetsHaveCorrectSelectors() public {
        for (uint i = 0; i < facetAddressList.length; ++i) {
            bytes4[] memory fromLoupeFacet = transmuter.facetFunctionSelectors(facetAddressList[i]);
            bytes4[] memory fromGenSelectors = generateSelectors(facetNames[i]);
            assertTrue(sameMembers(fromLoupeFacet, fromGenSelectors));
        }
    }

    function test_SelectorsAssociatedWithCorrectFacet() public {
        for (uint i = 0; i < facetAddressList.length; ++i) {
            bytes4[] memory fromGenSelectors = generateSelectors(facetNames[i]);
            for (uint j = 0; j < fromGenSelectors.length; j++) {
                assertEq(facetAddressList[i], transmuter.facetAddress(fromGenSelectors[j]));
            }
        }
    }

    function test_InterfaceCorrectlyImplemented() public {
        bytes4[] memory selectors = generateSelectors("ITransmuter");
        for (uint i = 0; i < selectors.length; ++i) {
            assertEq(transmuter.isValidSelector(selectors[i]), true);
        }
    }

    // Checks that all implemented selectors are in the interface
    function test_OnlyInterfaceIsImplemented() public {
        bytes4[] memory interfaceSelectors = generateSelectors("ITransmuter");

        Facet[] memory facets = transmuter.facets();

        for (uint256 i; i < facetNames.length; ++i) {
            for (uint256 j; j < facets[i].functionSelectors.length; ++j) {
                bool found = false;
                for (uint256 k; k < interfaceSelectors.length; ++k) {
                    if (facets[i].functionSelectors[j] == interfaceSelectors[k]) {
                        found = true;
                        break;
                    }
                }
                assert(found);
            }
        }
    }

    function testQuoteInScenario() public {
        uint256 quote = (transmuter.quoteIn(BASE_6, address(eurA), address(agToken)));
        assertEq(quote, BASE_27 / (BASE_9 + BASE_9 / 99));
    }

    function testSimpleSwapInScenario() public {
        deal(address(eurA), alice, BASE_6);

        startHoax(alice);
        eurA.approve(address(transmuter), BASE_6);
        transmuter.swapExactInput(BASE_6, 0, address(eurA), address(agToken), alice, block.timestamp + 1 hours);

        assertEq(agToken.balanceOf(alice), BASE_27 / (BASE_9 + BASE_9 / 99));
    }

    function testQuoteCollateralRatio() public {
        transmuter.getCollateralRatio();
        assertEq(uint256(0), uint256(0));
    }

    function testQuoteCollateralRatioDirectCall() public {
        LibRedeemer.getCollateralRatio();
        assertEq(uint256(0), uint256(0));
    }
}
