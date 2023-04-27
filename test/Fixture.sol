// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { MockAccessControlManager } from "./mock/MockAccessControlManager.sol";
import { MockTokenPermit } from "./mock/MockTokenPermit.sol";
import { MockChainlinkOracle } from "./mock/MockChainlinkOracle.sol";
import { Kheops } from "./utils/Kheops.sol";

import { AggregatorV3Interface } from "contracts/interfaces/external/chainlink/AggregatorV3Interface.sol";
import { IAccessControlManager } from "contracts/interfaces/IAccessControlManager.sol";
import { IAgToken } from "contracts/interfaces/IAgToken.sol";
import { Test } from "contracts/kheops/configs/Test.sol";
import "contracts/utils/Errors.sol";
import "contracts/utils/Constants.sol";

import { console } from "forge-std/console.sol";

contract Fixture is Kheops {
    IAccessControlManager accessControlManager;
    IAgToken agToken;
    AggregatorV3Interface oracle;

    IERC20 collateral;

    address config;

    function setUp() public virtual {
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
        deployKheops(
            config,
            abi.encodeWithSelector(Test.initialize.selector, accessControlManager, agToken, collateral, oracle)
        );
    }
}
