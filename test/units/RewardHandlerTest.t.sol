// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";

import { stdError } from "forge-std/Test.sol";

import { MockOneInchRouter } from "mock/MockOneInchRouter.sol";

import "contracts/transmuter/Storage.sol";
import "contracts/utils/Errors.sol" as Errors;

import "../Fixture.sol";

contract RewardHandlerTest is Fixture {
    MockOneInchRouter oneInch;

    function setUp() public override {
        super.setUp();
        oneInch = MockOneInchRouter(0x1111111254fb6c44bAC0beD2854e76F90643097d);

        MockOneInchRouter tempRouter = new MockOneInchRouter();
        vm.etch(address(oneInch), address(tempRouter).code);
    }

    function test_RevertWhen_SellRewards_NotTrusted() public {
        startHoax(alice);
        vm.expectRevert(Errors.NotTrusted.selector);
        bytes memory data;
        transmuter.sellRewards(0, data);
    }
}
