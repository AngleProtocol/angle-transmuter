// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { MockAccessControlManager } from "../../../contracts/mock/MockAccessControlManager.sol";
import { MockTokenPermit } from "../../../contracts/mock/MockTokenPermit.sol";
import { MockChainlinkOracle } from "../../../contracts/mock/MockChainlinkOracle.sol";
import { AggregatorV3Interface } from "../../../contracts/interfaces/external/chainlink/AggregatorV3Interface.sol";
import { IAccessControlManager } from "../../../contracts/interfaces/IAccessControlManager.sol";
import { IAgToken } from "../../../contracts/interfaces/IAgToken.sol";
import { Test } from "../../../contracts/kheops/configs/Test.sol";
import "../../../contracts/utils/Errors.sol";
import "../../../contracts/utils/Constants.sol";

import { KheopsDeployer } from "./KheopsDeployer.sol";

import { console } from "forge-std/console.sol";

contract TestKheops is KheopsDeployer {
    IAccessControlManager accessControlManager;
    IAgToken agToken;
    AggregatorV3Interface oracle;

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

        // oracle
        oracle = AggregatorV3Interface(address(new MockChainlinkOracle()));
        MockChainlinkOracle(address(oracle)).setLatestAnswer(int256(BASE_18));

        // Config
        config = address(new Test());
        KheopsDeployer.deployKheops(
            config,
            abi.encodeWithSelector(Test.initialize.selector, accessControlManager, agToken, collateral, oracle)
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
