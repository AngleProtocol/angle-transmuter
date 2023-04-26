// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../contracts/mock/MockAccessControlManager.sol";
import "../../../contracts/mock/MockTokenPermit.sol";
import "../../../contracts/kheops/configs/Test.sol";
import "../../../contracts/utils/Errors.sol";

import { KheopsDeployer } from "./KheopsDeployer.sol";

import { console } from "forge-std/console.sol";

contract TestKheops is KheopsDeployer {
    IAccessControlManager accessControlManager;
    IAgToken agToken;

    IERC20 collateral;

    address config;

    function setUp() public {
        // Access Control
        accessControlManager = IAccessControlManager(address(new MockAccessControlManager()));
        MockAccessControlManager(address(accessControlManager)).toggleGovernor(address(this));
        MockAccessControlManager(address(accessControlManager)).toggleGuardian(address(this));

        // agToken
        agToken = IAgToken(address(new MockTokenPermit("agEUR", "agEUR", 18)));

        // collateral
        collateral = IERC20(address(new MockTokenPermit("EUROC", "EUROC", 6)));

        // Config
        config = address(new Test());
        KheopsDeployer.deployKheops(
            config,
            abi.encodeWithSelector(Test.initialize.selector, accessControlManager, agToken)
        );
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
            for (uint j = 0; j < fromGenSelectors.length; j++) {
                assertEq(facetAddressList[i], kheops.facetAddress(fromGenSelectors[j]));
            }
        }
    }
}
