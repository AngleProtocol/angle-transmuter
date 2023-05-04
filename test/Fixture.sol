// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { MockAccessControlManager } from "./mock/MockAccessControlManager.sol";
import { MockTokenPermit } from "./mock/MockTokenPermit.sol";
import { MockChainlinkOracle } from "./mock/MockChainlinkOracle.sol";
import { Kheops } from "./utils/Kheops.sol";

import { AggregatorV3Interface } from "contracts/interfaces/external/chainlink/AggregatorV3Interface.sol";
import { IAccessControlManager } from "contracts/interfaces/IAccessControlManager.sol";
import { IAgToken } from "contracts/interfaces/IAgToken.sol";
import { CollateralSetup, Test } from "contracts/kheops/configs/Test.sol";
import "contracts/utils/Errors.sol";
import "contracts/utils/Constants.sol";

import { console } from "forge-std/console.sol";

contract Fixture is Kheops {
    IAccessControlManager public accessControlManager;
    IAgToken public agToken;

    IERC20 public eurA;
    AggregatorV3Interface public oracleA;
    IERC20 public eurB;
    AggregatorV3Interface public oracleB;
    IERC20 public eurY;
    AggregatorV3Interface public oracleY;

    address public config;

    address public constant governor = 0xdC4e6DFe07EFCa50a197DF15D9200883eF4Eb1c8;
    address public constant guardian = 0x0C2553e4B9dFA9f83b1A6D3EAB96c4bAaB42d430;
    address public constant angle = 0x31429d1856aD1377A8A0079410B297e1a9e214c2;

    address public constant alice = address(uint160(uint256(keccak256(abi.encodePacked("alice")))));
    address public constant bob = address(uint160(uint256(keccak256(abi.encodePacked("bob")))));
    address public constant charlie = address(uint160(uint256(keccak256(abi.encodePacked("charlie")))));
    address public constant dylan = address(uint160(uint256(keccak256(abi.encodePacked("dylan")))));

    function setUp() public virtual {
        vm.label(governor, "Governor");
        vm.label(guardian, "Guardian");
        vm.label(angle, "ANGLE");
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
        vm.label(dylan, "Dylan");

        // Access Control
        accessControlManager = IAccessControlManager(address(new MockAccessControlManager()));
        MockAccessControlManager(address(accessControlManager)).toggleGovernor(governor);
        MockAccessControlManager(address(accessControlManager)).toggleGuardian(guardian);

        // agToken
        agToken = IAgToken(address(new MockTokenPermit("agEUR", "agEUR", 18)));

        // Collaterals
        eurA = IERC20(address(new MockTokenPermit("EUR_A", "EUR_A", 6)));
        oracleA = AggregatorV3Interface(address(new MockChainlinkOracle()));
        MockChainlinkOracle(address(oracleA)).setLatestAnswer(int256(BASE_8));

        eurB = IERC20(address(new MockTokenPermit("EUR_B", "EUR_B", 12)));
        oracleB = AggregatorV3Interface(address(new MockChainlinkOracle()));
        MockChainlinkOracle(address(oracleB)).setLatestAnswer(int256(BASE_8));

        eurY = IERC20(address(new MockTokenPermit("EUR_Y", "EUR_Y", 18)));
        oracleY = AggregatorV3Interface(address(new MockChainlinkOracle()));
        MockChainlinkOracle(address(oracleY)).setLatestAnswer(int256(BASE_8));

        // Config
        config = address(new Test());
        deployKheops(
            config,
            abi.encodeWithSelector(
                Test.initialize.selector,
                accessControlManager,
                agToken,
                CollateralSetup(address(eurA), address(oracleA)),
                CollateralSetup(address(eurB), address(oracleB)),
                CollateralSetup(address(eurY), address(oracleY))
            )
        );
    }
}
