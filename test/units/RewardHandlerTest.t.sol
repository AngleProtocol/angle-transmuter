// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "oz/interfaces/IERC20.sol";

import { stdError } from "forge-std/Test.sol";

import { MockOneInchRouter } from "mock/MockOneInchRouter.sol";
import { MockTokenPermit } from "mock/MockTokenPermit.sol";

import "contracts/transmuter/Storage.sol";
import "contracts/utils/Errors.sol" as Errors;

import "../Fixture.sol";

contract RewardHandlerTest is Fixture {
    event RewardsSoldFor(address indexed tokenObtained, uint256 balanceUpdate);
    MockOneInchRouter oneInch;
    IERC20 tokenA;
    IERC20 tokenB;
    bytes4 public constant SELECTOR =
        bytes4(keccak256("swap(uint256 amountIn, uint256 amountOut, address tokenIn, address tokenOut)"));

    function setUp() public override {
        super.setUp();
        oneInch = MockOneInchRouter(0x1111111254fb6c44bAC0beD2854e76F90643097d);

        tokenA = IERC20(address(new MockTokenPermit("tokenA", "tokenA", 18)));
        tokenB = IERC20(address(new MockTokenPermit("tokenA", "tokenA", 9)));

        MockOneInchRouter tempRouter = new MockOneInchRouter();
        vm.etch(address(oneInch), address(tempRouter).code);
    }

    function test_RevertWhen_SellRewards_NotTrusted() public {
        startHoax(alice);
        vm.expectRevert(Errors.NotTrusted.selector);
        bytes memory data;
        transmuter.sellRewards(0, data);
    }

    function test_RevertWhen_SellRewards_NoApproval() public {
        vm.startPrank(guardian);
        bytes memory payload = abi.encodeWithSelector(
            MockOneInchRouter.swap.selector,
            100,
            100,
            address(tokenA),
            address(tokenB)
        );
        vm.expectRevert();
        transmuter.sellRewards(0, payload);
        vm.stopPrank();
    }

    function test_RevertWhen_SellRewards_NoIncrease() public {
        bytes memory payload = abi.encodeWithSelector(
            MockOneInchRouter.swap.selector,
            100,
            100,
            address(tokenA),
            address(tokenB)
        );
        vm.startPrank(governor);

        deal(address(tokenA), address(transmuter), 100);
        deal(address(tokenB), address(oneInch), 100);
        transmuter.changeAllowance(tokenA, address(oneInch), 100);
        vm.expectRevert(Errors.InvalidSwap.selector);
        transmuter.sellRewards(0, payload);
        vm.stopPrank();
    }

    function test_RevertWhen_SellRewards_TooSmallAmountOut() public {
        bytes memory payload = abi.encodeWithSelector(
            MockOneInchRouter.swap.selector,
            100,
            100,
            address(tokenA),
            address(tokenB)
        );
        vm.startPrank(governor);

        deal(address(tokenA), address(transmuter), 100);
        deal(address(tokenB), address(oneInch), 100);
        transmuter.changeAllowance(tokenA, address(oneInch), 100);
        vm.expectRevert(Errors.TooSmallAmountOut.selector);
        transmuter.sellRewards(1000, payload);
        vm.stopPrank();
    }

    function test_RevertWhen_SellRewards_EmptyErrorMessage() public {
        bytes memory payload = abi.encodeWithSelector(
            MockOneInchRouter.swap.selector,
            100,
            100,
            address(tokenA),
            address(tokenB)
        );
        vm.startPrank(governor);

        deal(address(tokenA), address(transmuter), 100);
        deal(address(tokenB), address(oneInch), 100);
        transmuter.changeAllowance(tokenA, address(oneInch), 100);
        oneInch.setRevertStatuses(true, false);
        vm.expectRevert(Errors.OneInchSwapFailed.selector);
        transmuter.sellRewards(0, payload);
        vm.stopPrank();
    }

    function test_RevertWhen_SellRewards_ErrorMessage() public {
        bytes memory payload = abi.encodeWithSelector(
            MockOneInchRouter.swap.selector,
            100,
            100,
            address(tokenA),
            address(tokenB)
        );
        vm.startPrank(governor);

        deal(address(tokenA), address(transmuter), 100);
        deal(address(tokenB), address(oneInch), 100);
        transmuter.changeAllowance(tokenA, address(oneInch), 100);
        oneInch.setRevertStatuses(false, true);
        vm.expectRevert("wrong swap");
        transmuter.sellRewards(0, payload);
        vm.stopPrank();
    }

    function test_RevertWhen_SellRewards_InvalidSwapBecauseTokenSold() public {
        bytes memory payload = abi.encodeWithSelector(
            MockOneInchRouter.swap.selector,
            100,
            100,
            address(eurA),
            address(eurB)
        );
        vm.startPrank(governor);

        deal(address(eurA), address(transmuter), 100);
        deal(address(eurB), address(oneInch), 100);
        transmuter.changeAllowance(eurA, address(oneInch), 100);
        vm.expectRevert(Errors.InvalidSwap.selector);
        transmuter.sellRewards(0, payload);
        vm.stopPrank();
    }

    function test_SellRewards_WithOneTokenIncrease() public {
        bytes memory payload = abi.encodeWithSelector(
            MockOneInchRouter.swap.selector,
            100,
            100,
            address(tokenA),
            address(eurA)
        );
        vm.startPrank(governor);

        deal(address(tokenA), address(transmuter), 100);
        deal(address(eurA), address(oneInch), 100);
        transmuter.changeAllowance(tokenA, address(oneInch), 100);
        vm.expectEmit(address(transmuter));
        emit RewardsSoldFor(address(eurA), 100);
        transmuter.sellRewards(0, payload);
        vm.stopPrank();
    }

    function test_SellRewards_WithOneTokenIncreaseAndTrusted() public {
        bytes memory payload = abi.encodeWithSelector(
            MockOneInchRouter.swap.selector,
            100,
            100,
            address(tokenA),
            address(eurA)
        );
        vm.startPrank(governor);
        transmuter.toggleTrusted(alice, TrustedType.Seller);
        transmuter.changeAllowance(tokenA, address(oneInch), 100);
        vm.stopPrank();

        deal(address(tokenA), address(transmuter), 100);
        deal(address(eurA), address(oneInch), 100);

        vm.expectEmit(address(transmuter));
        emit RewardsSoldFor(address(eurA), 100);
        vm.prank(alice);
        transmuter.sellRewards(0, payload);
    }
}
