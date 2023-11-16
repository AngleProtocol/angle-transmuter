// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";

import { stdError } from "forge-std/Test.sol";

import "contracts/utils/Errors.sol" as Errors;

import "../Fixture.sol";
import { IERC20Metadata } from "../mock/MockTokenPermit.sol";
import "../utils/FunctionUtils.sol";

import "contracts/helpers/Rebalancer.sol";

contract RebalancerTest is Fixture, FunctionUtils {
    using SafeERC20 for IERC20;

    address[] internal _collaterals;

    Rebalancer public rebalancer;

    function setUp() public override {
        super.setUp();

        // set mint Fees to 0 on all collaterals
        uint64[] memory xFeeMint = new uint64[](1);
        xFeeMint[0] = uint64(0);
        uint64[] memory xFeeBurn = new uint64[](1);
        xFeeBurn[0] = uint64(BASE_9);
        int64[] memory yFeeMint = new int64[](1);
        yFeeMint[0] = 0;
        int64[] memory yFeeBurn = new int64[](1);
        yFeeBurn[0] = 0;
        int64[] memory yFeeRedemption = new int64[](1);
        yFeeRedemption[0] = int64(int256(BASE_9));
        vm.startPrank(governor);
        transmuter.setFees(address(eurA), xFeeMint, yFeeMint, true);
        transmuter.setFees(address(eurA), xFeeBurn, yFeeBurn, false);
        transmuter.setFees(address(eurB), xFeeMint, yFeeMint, true);
        transmuter.setFees(address(eurB), xFeeBurn, yFeeBurn, false);
        transmuter.setFees(address(eurY), xFeeMint, yFeeMint, true);
        transmuter.setFees(address(eurY), xFeeBurn, yFeeBurn, false);
        transmuter.setRedemptionCurveParams(xFeeMint, yFeeRedemption);
        vm.stopPrank();

        _collaterals.push(address(eurA));
        _collaterals.push(address(eurB));
        _collaterals.push(address(eurY));
        rebalancer = new Rebalancer(accessControlManager, transmuter);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    INITIALIZATION                                                  
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function test_RebalancerInitialization() public {
        assertEq(address(rebalancer.accessControlManager()), address(accessControlManager));
        assertEq(address(rebalancer.agToken()), address(agToken));
        assertEq(address(rebalancer.transmuter()), address(transmuter));
    }

    function test_Constructor_RevertWhen_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new Rebalancer(IAccessControlManager(address(0)), transmuter);

        vm.expectRevert();
        new Rebalancer(accessControlManager, ITransmuter(address(0)));
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       SET ORDER                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function test_SetOrder_RevertWhen_NonGovernorOrGuardian() public {
        vm.expectRevert(Errors.NotGovernorOrGuardian.selector);
        rebalancer.setOrder(address(eurA), address(eurB), 100, 1);
    }

    function test_SetOrder_RevertWhen_InvalidParam() public {
        vm.startPrank(governor);
        vm.expectRevert(Errors.InvalidParam.selector);
        rebalancer.setOrder(address(eurA), address(eurB), 100, 1);
        vm.stopPrank();
    }

    function testFuzz_SetOrder(
        uint256 subsidyBudget,
        uint256 premium,
        uint256 subsidyBudget1,
        uint256 premium1
    ) public {
        uint256 a;
        uint256 b;
        subsidyBudget = bound(subsidyBudget, 10 ** 9, 10 ** 27);
        premium = bound(premium, 0, 10 ** 9);
        subsidyBudget1 = bound(subsidyBudget1, 10 ** 9, 10 ** 27);
        premium1 = bound(premium1, 0, 10 ** 9);
        deal(address(eurB), address(rebalancer), subsidyBudget);
        vm.startPrank(governor);
        rebalancer.setOrder(address(eurA), address(eurB), subsidyBudget, premium);
        vm.stopPrank();
        (a, b) = rebalancer.orders(address(eurA), address(eurB));
        assertEq(a, subsidyBudget);
        assertEq(b, premium);
        assertEq(rebalancer.budget(address(eurB)), subsidyBudget);
        if (premium == 0) assertEq(rebalancer.estimateAmountEligibleForIncentives(address(eurA), address(eurB)), 0);
        else
            assertEq(
                rebalancer.estimateAmountEligibleForIncentives(address(eurA), address(eurB)),
                (subsidyBudget * BASE_9) / premium
            );

        vm.startPrank(governor);
        vm.expectRevert(Errors.InvalidParam.selector);
        rebalancer.setOrder(address(eurA), address(eurB), subsidyBudget + 1, premium + 1);
        vm.stopPrank();

        vm.startPrank(governor);
        rebalancer.setOrder(address(eurA), address(eurB), subsidyBudget / 3, premium);
        vm.stopPrank();
        (a, b) = rebalancer.orders(address(eurA), address(eurB));
        assertEq(a, subsidyBudget / 3);
        assertEq(b, premium);
        assertEq(rebalancer.budget(address(eurB)), subsidyBudget / 3);
        if (premium == 0) assertEq(rebalancer.estimateAmountEligibleForIncentives(address(eurA), address(eurB)), 0);
        else
            assertEq(
                rebalancer.estimateAmountEligibleForIncentives(address(eurA), address(eurB)),
                ((subsidyBudget / 3) * BASE_9) / premium
            );

        vm.startPrank(governor);
        rebalancer.setOrder(address(eurA), address(eurB), subsidyBudget, premium / 2);
        vm.stopPrank();
        (a, b) = rebalancer.orders(address(eurA), address(eurB));
        assertEq(a, subsidyBudget);
        assertEq(b, premium / 2);
        assertEq(rebalancer.budget(address(eurB)), subsidyBudget);
        if (premium / 2 == 0) assertEq(rebalancer.estimateAmountEligibleForIncentives(address(eurA), address(eurB)), 0);
        else
            assertEq(
                rebalancer.estimateAmountEligibleForIncentives(address(eurA), address(eurB)),
                (subsidyBudget * BASE_9) / (premium / 2)
            );
        // Resetting to normal
        vm.startPrank(governor);
        rebalancer.setOrder(address(eurA), address(eurB), subsidyBudget, premium);
        vm.stopPrank();
        // Now checking with multi token budget

        deal(address(eurB), address(governor), subsidyBudget1);

        vm.startPrank(governor);
        if (premium1 > 0) {
            vm.expectRevert(Errors.InvalidParam.selector);
            rebalancer.setOrder(address(eurY), address(eurB), subsidyBudget1, premium1);
        }

        eurB.transfer(address(rebalancer), subsidyBudget1);
        rebalancer.setOrder(address(eurY), address(eurB), subsidyBudget1, premium1);
        vm.stopPrank();
        (a, b) = rebalancer.orders(address(eurY), address(eurB));
        assertEq(a, subsidyBudget1);
        assertEq(b, premium1);
        assertEq(rebalancer.budget(address(eurB)), subsidyBudget + subsidyBudget1);
        if (premium1 == 0) assertEq(rebalancer.estimateAmountEligibleForIncentives(address(eurY), address(eurB)), 0);
        else
            assertEq(
                rebalancer.estimateAmountEligibleForIncentives(address(eurY), address(eurB)),
                (subsidyBudget1 * BASE_9) / premium1
            );

        vm.startPrank(governor);
        if (premium1 > 0) {
            vm.expectRevert(Errors.InvalidParam.selector);
            rebalancer.setOrder(address(eurY), address(eurB), subsidyBudget1 + 1, premium1 + 1);
        }

        rebalancer.setOrder(address(eurY), address(eurB), subsidyBudget1, premium1 / 2);
        vm.stopPrank();
        (a, b) = rebalancer.orders(address(eurY), address(eurB));
        assertEq(a, subsidyBudget1);
        assertEq(b, premium1 / 2);
        assertEq(rebalancer.budget(address(eurB)), subsidyBudget + subsidyBudget1);
        if (premium1 / 2 == 0)
            assertEq(rebalancer.estimateAmountEligibleForIncentives(address(eurY), address(eurB)), 0);
        else
            assertEq(
                rebalancer.estimateAmountEligibleForIncentives(address(eurY), address(eurB)),
                (subsidyBudget1 * BASE_9) / (premium1 / 2)
            );

        vm.startPrank(governor);
        rebalancer.setOrder(address(eurY), address(eurB), subsidyBudget1 / 3, premium1);
        vm.stopPrank();
        (a, b) = rebalancer.orders(address(eurY), address(eurB));
        assertEq(a, subsidyBudget1 / 3);
        assertEq(b, premium1);
        assertEq(rebalancer.budget(address(eurB)), subsidyBudget + subsidyBudget1 / 3);
        if (premium1 == 0) assertEq(rebalancer.estimateAmountEligibleForIncentives(address(eurY), address(eurB)), 0);
        else
            assertEq(
                rebalancer.estimateAmountEligibleForIncentives(address(eurY), address(eurB)),
                ((subsidyBudget1 / 3) * BASE_9) / premium1
            );
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        RECOVER                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function test_Recover_RevertWhen_NonGovernorOrGuardian() public {
        vm.expectRevert(Errors.NotGovernorOrGuardian.selector);
        rebalancer.recover(address(eurA), 100, address(governor));
    }

    function test_Recover_RevertWhen_InvalidParam() public {
        vm.startPrank(governor);
        vm.expectRevert(Errors.InvalidParam.selector);
        rebalancer.recover(address(eurA), 100, address(governor));
        vm.stopPrank();
    }

    function testFuzz_Recover(uint256 amount) public {
        amount = bound(amount, 10 ** 9, 10 ** 27);
        deal(address(eurB), address(rebalancer), amount);
        vm.startPrank(governor);
        rebalancer.recover(address(eurB), amount / 2, address(governor));
        vm.stopPrank();
        assertEq(eurB.balanceOf(address(governor)), amount / 2);
        vm.startPrank(governor);
        rebalancer.setOrder(address(eurA), address(eurB), amount / 2, BASE_9 / 100);
        vm.stopPrank();
        (uint256 a, uint256 b) = rebalancer.orders(address(eurA), address(eurB));
        assertEq(a, amount / 2);
        assertEq(b, BASE_9 / 100);
        vm.startPrank(governor);
        vm.expectRevert(Errors.InvalidParam.selector);
        rebalancer.recover(address(eurB), 100, address(governor));
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       QUOTE IN                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_QuoteInWithoutSubsidy(uint256 multiplier, uint256 swapMultiplier) public {
        multiplier = bound(multiplier, 10, 10 ** 6);
        swapMultiplier = bound(swapMultiplier, 1, 100);
        // let's first load the reserves of the protocol
        _loadReserves(charlie, multiplier);
        // Here there are no fees, and oracles are all constant -> so any mint and burn should be an onpar
        // conversion for both tokens

        uint256 swapAmount = (multiplier * swapMultiplier * 10 ** IERC20Metadata(address(eurA)).decimals()) / 100;

        uint256 amountAgToken = transmuter.quoteIn(swapAmount, address(eurA), address(agToken));
        uint256 amountOut = transmuter.quoteIn(amountAgToken, address(agToken), address(eurB));

        assertEq(rebalancer.quoteIn(swapAmount, address(eurA), address(eurB)), amountOut);

        assertEq(
            rebalancer.quoteIn(swapAmount, address(eurA), address(eurB)),
            (multiplier * swapMultiplier * 10 ** IERC20Metadata(address(eurB)).decimals()) / 100
        );
        assertEq(
            rebalancer.quoteIn(swapAmount, address(eurA), address(eurY)),
            (multiplier * swapMultiplier * 10 ** IERC20Metadata(address(eurY)).decimals()) / 100
        );

        swapAmount = (multiplier * swapMultiplier * 10 ** IERC20Metadata(address(eurY)).decimals()) / 100;
        assertEq(
            rebalancer.quoteIn(swapAmount, address(eurY), address(eurB)),
            (multiplier * swapMultiplier * 10 ** IERC20Metadata(address(eurB)).decimals()) / 100
        );
        assertEq(
            rebalancer.quoteIn(swapAmount, address(eurY), address(eurA)),
            (multiplier * swapMultiplier * 10 ** IERC20Metadata(address(eurA)).decimals()) / 100
        );

        swapAmount = (multiplier * swapMultiplier * 10 ** IERC20Metadata(address(eurB)).decimals()) / 100;
        assertEq(
            rebalancer.quoteIn(swapAmount, address(eurB), address(eurA)),
            (multiplier * swapMultiplier * 10 ** IERC20Metadata(address(eurA)).decimals()) / 100
        );
        assertEq(
            rebalancer.quoteIn(swapAmount, address(eurB), address(eurY)),
            (multiplier * swapMultiplier * 10 ** IERC20Metadata(address(eurY)).decimals()) / 100
        );
    }

    function testFuzz_QuoteInWithSubsidyPartiallyFilled(
        uint256 multiplier,
        uint256 swapMultiplier,
        uint256 premium
    ) public {
        multiplier = bound(multiplier, 10, 10 ** 6);
        swapMultiplier = bound(swapMultiplier, 1, 100);
        premium = bound(premium, 0, BASE_9);
        // let's first load the reserves of the protocol
        _loadReserves(charlie, multiplier);
        // Here there are no fees, and oracles are all constant -> so any mint and burn should be an onpar
        // conversion for both tokens

        uint256 swapAmount = (multiplier * swapMultiplier * 10 ** IERC20Metadata(address(eurA)).decimals()) / 100;
        // This is the amount we'd normally obtain after the swap
        uint256 subsidyBudget = (multiplier * swapMultiplier * 10 ** IERC20Metadata(address(eurB)).decimals()) / 100;
        uint256 amountSubsidized = (subsidyBudget * premium) / BASE_9;

        deal(address(eurB), address(rebalancer), subsidyBudget);
        vm.startPrank(governor);
        rebalancer.setOrder(address(eurA), address(eurB), subsidyBudget, premium);
        vm.stopPrank();

        uint256 amountAgToken = transmuter.quoteIn(swapAmount, address(eurA), address(agToken));
        uint256 amountOut = transmuter.quoteIn(amountAgToken, address(agToken), address(eurB));
        assertEq(
            rebalancer.quoteIn(swapAmount, address(eurA), address(eurB)),
            amountOut + (amountOut * premium) / BASE_9
        );

        assertEq(rebalancer.quoteIn(swapAmount, address(eurA), address(eurB)), subsidyBudget + amountSubsidized);
        assertEq(
            rebalancer.quoteIn(swapAmount, address(eurA), address(eurY)),
            (multiplier * swapMultiplier * 10 ** IERC20Metadata(address(eurY)).decimals()) / 100
        );

        subsidyBudget = (multiplier * swapMultiplier * 10 ** IERC20Metadata(address(eurY)).decimals()) / 100;
        deal(address(eurY), address(rebalancer), subsidyBudget);
        vm.startPrank(governor);
        rebalancer.setOrder(address(eurA), address(eurY), subsidyBudget, premium);
        vm.stopPrank();
        assertEq(
            rebalancer.quoteIn(swapAmount, address(eurA), address(eurY)),
            subsidyBudget + (subsidyBudget * premium) / BASE_9
        );
    }

    function testFuzz_QuoteInWithSubsidyBudgetFullyFilled(
        uint256 multiplier,
        uint256 swapMultiplier,
        uint256 premium
    ) public {
        multiplier = bound(multiplier, 10, 10 ** 6);
        swapMultiplier = bound(swapMultiplier, 1, 100);
        premium = bound(premium, BASE_9, BASE_9 * 2);
        // let's first load the reserves of the protocol
        _loadReserves(charlie, multiplier);
        // Here there are no fees, and oracles are all constant -> so any mint and burn should be an onpar
        // conversion for both tokens

        uint256 swapAmount = (multiplier * swapMultiplier * 10 ** IERC20Metadata(address(eurA)).decimals()) / 100;
        // This is the amount we'd normally obtain after the swap
        uint256 subsidyBudget = (multiplier * swapMultiplier * 10 ** IERC20Metadata(address(eurB)).decimals()) / 100;

        deal(address(eurB), address(rebalancer), subsidyBudget);
        vm.startPrank(governor);
        rebalancer.setOrder(address(eurA), address(eurB), subsidyBudget, premium);
        vm.stopPrank();

        uint256 amountAgToken = transmuter.quoteIn(swapAmount, address(eurA), address(agToken));
        uint256 amountOut = transmuter.quoteIn(amountAgToken, address(agToken), address(eurB));
        assertEq(rebalancer.quoteIn(swapAmount, address(eurA), address(eurB)), amountOut + subsidyBudget);

        assertEq(rebalancer.quoteIn(swapAmount, address(eurA), address(eurB)), subsidyBudget * 2);
        assertEq(
            rebalancer.quoteIn(swapAmount, address(eurA), address(eurY)),
            (multiplier * swapMultiplier * 10 ** IERC20Metadata(address(eurY)).decimals()) / 100
        );

        subsidyBudget = (multiplier * swapMultiplier * 10 ** IERC20Metadata(address(eurY)).decimals()) / 100;
        deal(address(eurY), address(rebalancer), subsidyBudget);
        vm.startPrank(governor);
        rebalancer.setOrder(address(eurA), address(eurY), subsidyBudget, premium);
        vm.stopPrank();
        assertEq(rebalancer.quoteIn(swapAmount, address(eurA), address(eurY)), subsidyBudget * 2);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                   SWAP EXACT INPUT                                                 
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_SwapExactInput_Revert(uint256 multiplier, uint256 swapMultiplier) public {
        multiplier = bound(multiplier, 10, 10 ** 6);
        swapMultiplier = bound(swapMultiplier, 1, 100);
        // let's first load the reserves of the protocol
        _loadReserves(charlie, multiplier);
        uint256 swapAmount = (multiplier * swapMultiplier * 10 ** IERC20Metadata(address(eurA)).decimals()) / 100;
        deal(address(eurA), address(charlie), swapAmount);
        vm.startPrank(charlie);
        eurA.approve(address(rebalancer), swapAmount);
        vm.expectRevert(Errors.TooSmallAmountOut.selector);
        rebalancer.swapExactInput(
            swapAmount,
            type(uint256).max,
            address(eurA),
            address(eurB),
            address(bob),
            block.timestamp * 2
        );
        uint256 curTimestamp = block.timestamp;
        skip(curTimestamp + 1);
        vm.expectRevert(Errors.TooLate.selector);
        rebalancer.swapExactInput(swapAmount, 0, address(eurA), address(eurB), address(bob), block.timestamp - 1);

        vm.stopPrank();
    }

    function testFuzz_SwapExactInputWithoutSubsidy(uint256 multiplier, uint256 swapMultiplier) public {
        multiplier = bound(multiplier, 10, 10 ** 6);
        swapMultiplier = bound(swapMultiplier, 1, 100);
        // let's first load the reserves of the protocol
        _loadReserves(charlie, multiplier);
        // Here there are no fees, and oracles are all constant -> so any mint and burn should be an onpar
        // conversion for both tokens

        uint256 swapAmount = (multiplier * swapMultiplier * 10 ** IERC20Metadata(address(eurA)).decimals()) / 100;
        uint256 amountOut = (multiplier * swapMultiplier * 10 ** IERC20Metadata(address(eurB)).decimals()) / 100;
        assertEq(rebalancer.quoteIn(swapAmount, address(eurA), address(eurB)), amountOut);
        deal(address(eurA), address(charlie), swapAmount * 2);

        vm.startPrank(charlie);
        eurA.approve(address(rebalancer), swapAmount * 2);
        uint256 amountOut2 = rebalancer.swapExactInput(
            swapAmount,
            0,
            address(eurA),
            address(eurB),
            address(bob),
            block.timestamp * 2
        );
        vm.stopPrank();
        assertEq(amountOut2, amountOut);
        assertEq(eurB.balanceOf(address(bob)), amountOut);
        assertEq(eurA.allowance(address(rebalancer), address(transmuter)), type(uint256).max);

        amountOut = (multiplier * swapMultiplier * 10 ** IERC20Metadata(address(eurY)).decimals()) / 100;
        vm.startPrank(charlie);
        amountOut2 = rebalancer.swapExactInput(
            swapAmount,
            0,
            address(eurA),
            address(eurY),
            address(bob),
            block.timestamp * 2
        );
        vm.stopPrank();
        assertEq(amountOut2, amountOut);
        assertEq(eurY.balanceOf(address(bob)), amountOut);
        assertEq(eurA.allowance(address(rebalancer), address(transmuter)), type(uint256).max);
        assertEq(eurA.allowance(address(charlie), address(rebalancer)), 0);
    }

    function testFuzz_SwapExactInputWithPartialSubsidy(
        uint256 multiplier,
        uint256 swapMultiplier,
        uint256 premium
    ) public {
        multiplier = bound(multiplier, 10, 10 ** 6);
        swapMultiplier = bound(swapMultiplier, 1, 100);
        premium = bound(premium, 0, BASE_9);
        // let's first load the reserves of the protocol
        _loadReserves(charlie, multiplier);
        // Here there are no fees, and oracles are all constant -> so any mint and burn should be an onpar
        // conversion for both tokens

        uint256 swapAmount = (multiplier * swapMultiplier * 10 ** IERC20Metadata(address(eurA)).decimals()) / 100;
        uint256 amountOut = (multiplier * swapMultiplier * 10 ** IERC20Metadata(address(eurB)).decimals()) / 100;
        deal(address(eurA), address(charlie), swapAmount * 2);

        uint256 subsidyBudget = amountOut;
        uint256 amountSubsidized = (subsidyBudget * premium) / BASE_9;

        deal(address(eurB), address(rebalancer), subsidyBudget);
        vm.startPrank(governor);
        rebalancer.setOrder(address(eurA), address(eurB), subsidyBudget, premium);
        vm.stopPrank();

        assertEq(rebalancer.quoteIn(swapAmount, address(eurA), address(eurB)), amountOut + amountSubsidized);

        vm.startPrank(charlie);
        eurA.approve(address(rebalancer), swapAmount * 2);
        uint256 amountOut2 = rebalancer.swapExactInput(
            swapAmount,
            0,
            address(eurA),
            address(eurB),
            address(bob),
            block.timestamp * 2
        );
        vm.stopPrank();
        assertEq(amountOut2, amountOut + amountSubsidized);
        assertEq(eurB.balanceOf(address(bob)), amountOut + amountSubsidized);
        assertEq(eurA.allowance(address(rebalancer), address(transmuter)), type(uint256).max);
        assertEq(eurB.balanceOf(address(rebalancer)), subsidyBudget - amountSubsidized);
        assertEq(rebalancer.budget(address(eurB)), subsidyBudget - amountSubsidized);
        (uint256 subsidyBudgetLeft, ) = rebalancer.orders(address(eurA), address(eurB));
        assertEq(subsidyBudgetLeft, subsidyBudget - amountSubsidized);
    }

    function testFuzz_SwapExactInputWithMultiplePartialSubsidies(
        uint256 multiplier,
        uint256 swapMultiplier,
        uint256 premium,
        uint256[5] memory swapAmounts
    ) public {
        multiplier = bound(multiplier, 10, 10 ** 6);
        swapMultiplier = bound(swapMultiplier, 1, 100);
        premium = bound(premium, 0, BASE_9 / 5);
        // let's first load the reserves of the protocol
        _loadReserves(charlie, multiplier);
        // Here there are no fees, and oracles are all constant -> so any mint and burn should be an onpar
        // conversion for both tokens

        uint256 swapAmount = (multiplier * swapMultiplier * 10 ** IERC20Metadata(address(eurA)).decimals()) / 100;
        uint256 amountOut = (multiplier * swapMultiplier * 10 ** IERC20Metadata(address(eurB)).decimals()) / 100;
        deal(address(eurA), address(charlie), swapAmount * 2);

        uint256 subsidyBudget = amountOut;
        uint256 amountSubsidized = (subsidyBudget * premium) / BASE_9;

        deal(address(eurB), address(rebalancer), subsidyBudget);
        vm.startPrank(governor);
        rebalancer.setOrder(address(eurA), address(eurB), subsidyBudget, premium);
        vm.stopPrank();

        assertEq(rebalancer.quoteIn(swapAmount, address(eurA), address(eurB)), amountOut + amountSubsidized);

        vm.startPrank(charlie);
        eurA.approve(address(rebalancer), swapAmount * 2);
        vm.stopPrank();

        uint256 totalAmountForBob;
        uint256 totalSubsidyAmount;
        for (uint256 i = 0; i < swapAmounts.length; ++i) {
            swapAmounts[i] = bound(swapAmounts[i], 0, swapAmount / 5);
            vm.startPrank(charlie);
            uint256 amountOut2 = rebalancer.swapExactInput(
                swapAmounts[i],
                0,
                address(eurA),
                address(eurB),
                address(bob),
                block.timestamp * 2
            );
            vm.stopPrank();
            uint256 amountWithoutSubsidy = swapAmounts[i] * 10 ** 6;
            uint256 amountWithSubsidy = amountWithoutSubsidy + (amountWithoutSubsidy * premium) / BASE_9;
            totalAmountForBob += amountWithSubsidy;
            totalSubsidyAmount += (amountWithoutSubsidy * premium) / BASE_9;
            // There are 6 decimals difference between eurA and eurB
            assertEq(amountOut2, amountWithSubsidy);
            assertEq(eurB.balanceOf(address(bob)), totalAmountForBob);
            // assertEq(eurA.allowance(address(rebalancer), address(transmuter)), type(uint256).max);
            assertEq(eurB.balanceOf(address(rebalancer)), subsidyBudget - totalSubsidyAmount);
            assertEq(rebalancer.budget(address(eurB)), subsidyBudget - totalSubsidyAmount);
            (uint256 subsidyBudgetLeft, ) = rebalancer.orders(address(eurA), address(eurB));
            assertEq(subsidyBudgetLeft, subsidyBudget - totalSubsidyAmount);
        }
    }

    function testFuzz_SwapExactInputWithFullSubsidy(
        uint256 multiplier,
        uint256 swapMultiplier,
        uint256 premium
    ) public {
        multiplier = bound(multiplier, 10, 10 ** 6);
        swapMultiplier = bound(swapMultiplier, 1, 100);
        premium = bound(premium, BASE_9, BASE_9 * 2);
        // let's first load the reserves of the protocol
        _loadReserves(charlie, multiplier);
        // Here there are no fees, and oracles are all constant -> so any mint and burn should be an onpar
        // conversion for both tokens

        uint256 swapAmount = (multiplier * swapMultiplier * 10 ** IERC20Metadata(address(eurA)).decimals()) / 100;
        uint256 amountOut = (multiplier * swapMultiplier * 10 ** IERC20Metadata(address(eurB)).decimals()) / 100;
        deal(address(eurA), address(charlie), swapAmount * 2);

        uint256 subsidyBudget = amountOut;

        deal(address(eurB), address(rebalancer), subsidyBudget);
        vm.startPrank(governor);
        rebalancer.setOrder(address(eurA), address(eurB), subsidyBudget, premium);
        vm.stopPrank();

        assertEq(rebalancer.quoteIn(swapAmount, address(eurA), address(eurB)), amountOut + subsidyBudget);

        vm.startPrank(charlie);
        eurA.approve(address(rebalancer), swapAmount * 2);
        uint256 amountOut2 = rebalancer.swapExactInput(
            swapAmount,
            0,
            address(eurA),
            address(eurB),
            address(bob),
            block.timestamp * 2
        );
        vm.stopPrank();
        assertEq(amountOut2, amountOut + subsidyBudget);
        assertEq(eurB.balanceOf(address(bob)), amountOut + subsidyBudget);
        assertEq(eurA.allowance(address(rebalancer), address(transmuter)), type(uint256).max);
        assertEq(eurB.balanceOf(address(rebalancer)), 0);
        assertEq(rebalancer.budget(address(eurB)), 0);
        (uint256 subsidyBudgetLeft, ) = rebalancer.orders(address(eurA), address(eurB));
        assertEq(subsidyBudgetLeft, 0);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         UTILS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _loadReserves(
        address owner,
        uint256 multiplier
    ) internal returns (uint256 mintedStables, uint256[] memory collateralMintedStables) {
        collateralMintedStables = new uint256[](_collaterals.length);

        vm.startPrank(owner);
        for (uint256 i; i < _collaterals.length; i++) {
            uint256 amount = multiplier * 10 ** IERC20Metadata(_collaterals[i]).decimals();
            deal(_collaterals[i], owner, amount);
            IERC20(_collaterals[i]).approve(address(transmuter), amount);

            collateralMintedStables[i] = transmuter.swapExactInput(
                amount,
                0,
                _collaterals[i],
                address(agToken),
                owner,
                block.timestamp * 2
            );
            mintedStables += collateralMintedStables[i];
        }
        vm.stopPrank();
    }
}
