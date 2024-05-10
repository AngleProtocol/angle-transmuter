// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import { IERC20 } from "oz/interfaces/IERC20.sol";

import { IAccessControlManager } from "interfaces/IAccessControlManager.sol";
import { IAgToken } from "interfaces/IAgToken.sol";
import { AggregatorV3Interface } from "interfaces/external/chainlink/AggregatorV3Interface.sol";

import { MockAccessControlManager } from "mock/MockAccessControlManager.sol";
import { MockChainlinkOracle } from "mock/MockChainlinkOracle.sol";
import { MockTokenPermit } from "mock/MockTokenPermit.sol";

import { Test } from "contracts/transmuter/configs/Test.sol";
import { LibGetters } from "contracts/transmuter/libraries/LibGetters.sol";
import "contracts/transmuter/Storage.sol";
import "contracts/utils/Constants.sol";
import "contracts/utils/Errors.sol" as Errors;

import { Fixture } from "../Fixture.sol";

contract StablecoinCapTest is Fixture {
    function test_GetStablecoinCap_Init_Success() public {
        assertEq(transmuter.getStablecoinCap(address(eurA)), type(uint256).max);
        assertEq(transmuter.getStablecoinCap(address(eurB)), type(uint256).max);
        assertEq(transmuter.getStablecoinCap(address(eurY)), type(uint256).max);
    }

    function test_RevertWhen_SetStablecoinCap_TooLargeMint() public {
        uint256 amount = 2 ether;
        uint256 stablecoinCap = 1 ether;
        address collateral = address(eurA);

        vm.prank(governor);
        transmuter.setStablecoinCap(collateral, stablecoinCap);

        deal(collateral, bob, amount);
        startHoax(bob);
        IERC20(collateral).approve(address(transmuter), amount);
        vm.expectRevert(Errors.InvalidSwap.selector);
        startHoax(bob);
        transmuter.swapExactOutput(amount, type(uint256).max, collateral, address(agToken), bob, block.timestamp * 2);
    }

    function test_RevertWhen_SetStablecoinCap_SlightlyLargeMint() public {
        uint256 amount = 1.0000000000001 ether;
        uint256 stablecoinCap = 1 ether;
        address collateral = address(eurA);

        vm.prank(governor);
        transmuter.setStablecoinCap(collateral, stablecoinCap);

        deal(collateral, bob, amount);
        startHoax(bob);
        IERC20(collateral).approve(address(transmuter), amount);
        vm.expectRevert(Errors.InvalidSwap.selector);
        startHoax(bob);
        transmuter.swapExactOutput(amount, type(uint256).max, collateral, address(agToken), bob, block.timestamp * 2);
    }

    function test_SetStablecoinCap_Success() public {
        uint256 amount = 0.99 ether;
        uint256 stablecoinCap = 1 ether;
        address collateral = address(eurA);

        vm.prank(governor);
        transmuter.setStablecoinCap(collateral, stablecoinCap);

        deal(collateral, bob, amount);
        startHoax(bob);
        IERC20(collateral).approve(address(transmuter), amount);
        startHoax(bob);
        transmuter.swapExactOutput(amount, type(uint256).max, collateral, address(agToken), bob, block.timestamp * 2);
    }
}
