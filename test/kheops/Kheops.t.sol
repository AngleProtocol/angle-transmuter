// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { MockAccessControlManager } from "../mock/MockAccessControlManager.sol";
import { MockTokenPermit } from "../mock/MockTokenPermit.sol";
import { MockChainlinkOracle } from "../mock/MockChainlinkOracle.sol";

import { AggregatorV3Interface } from "contracts/interfaces/external/chainlink/AggregatorV3Interface.sol";
import { IAccessControlManager } from "contracts/interfaces/IAccessControlManager.sol";
import { IAgToken } from "contracts/interfaces/IAgToken.sol";
import { Test } from "contracts/kheops/configs/Test.sol";
import "contracts/utils/Errors.sol";
import "contracts/utils/Constants.sol";

import { Fixture } from "../Fixture.sol";

import { console } from "forge-std/console.sol";

contract TestKheops is Fixture {
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
            for (uint j = 0; j < fromGenSelectors.length; j++) {
                assertEq(facetAddressList[i], kheops.facetAddress(fromGenSelectors[j]));
            }
        }
    }

    function testInterfaceCorrectlyImplemented() public {
        bytes4[] memory selectors = generateSelectors("IKheops");
        for (uint i = 0; i < selectors.length; i++) {
            assertEq(kheops.isValidSelector(selectors[i]), true);
        }
    }

    function testQuoteInScenario() public {
        console.log(kheops.quoteIn(BASE_18, address(collateral), address(agToken)));
    }

    function testSimpleSwapInScenario() public {
        deal(address(collateral), alice, BASE_18);

        startHoax(alice);
        collateral.approve(address(kheops), BASE_18);
        kheops.swapExactInput(BASE_18, 0, address(collateral), address(agToken), alice, block.timestamp + 1 hours);
        console.log(agToken.balanceOf(alice));
    }
}
