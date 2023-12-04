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
    uint256 public decimalsA;
    uint256 public decimalsB;
    uint256 public decimalsY;

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

        decimalsA = 10 ** IERC20Metadata(address(eurA)).decimals();
        decimalsB = 10 ** IERC20Metadata(address(eurB)).decimals();
        decimalsY = 10 ** IERC20Metadata(address(eurY)).decimals();
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    INITIALIZATION                                                  
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function test_RebalancerInitialization() public {
        assertEq(address(rebalancer.accessControlManager()), address(accessControlManager));
        assertEq(address(rebalancer.AGTOKEN()), address(agToken));
        assertEq(address(rebalancer.TRANSMUTER()), address(transmuter));
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

    function test_SetOrder_RevertWhen_NotCollateral() public {
        vm.startPrank(governor);
        vm.expectRevert(Errors.NotCollateral.selector);
        rebalancer.setOrder(address(eurA), address(agToken), 100, 1);

        vm.expectRevert(Errors.NotCollateral.selector);
        rebalancer.setOrder(address(agToken), address(eurB), 100, 1);

        vm.expectRevert(Errors.NotCollateral.selector);
        rebalancer.setOrder(address(agToken), address(agToken), 100, 1);
        vm.stopPrank();
    }

    function testFuzz_SetOrder(
        uint256 subsidyBudget,
        uint256 guaranteedRate,
        uint256 subsidyBudget1,
        uint256 guaranteedRate1
    ) public {
        uint256 a;
        uint256 b;
        subsidyBudget = bound(subsidyBudget, 10 ** 9, 10 ** 27);
        guaranteedRate = bound(guaranteedRate, 10 ** 15, 10 ** 21);
        subsidyBudget1 = bound(subsidyBudget1, 10 ** 9, 10 ** 27);
        guaranteedRate1 = bound(guaranteedRate1, 10 ** 15, 10 ** 21);
        deal(address(agToken), address(rebalancer), subsidyBudget);
        vm.startPrank(governor);
        rebalancer.setOrder(address(eurA), address(eurB), subsidyBudget, guaranteedRate);
        vm.stopPrank();
        uint256 _decimalsA;
        uint256 _decimalsB;
        (a, _decimalsA, _decimalsB, b) = rebalancer.orders(address(eurA), address(eurB));
        assertEq(10 ** _decimalsA, decimalsA);
        assertEq(10 ** _decimalsB, decimalsB);
        assertEq(a, subsidyBudget);
        assertEq(b, guaranteedRate);
        assertEq(rebalancer.budget(), subsidyBudget);
        assertEq(
            rebalancer.getGuaranteedAmountOut(address(eurA), address(eurB), decimalsA),
            (guaranteedRate * decimalsB) / 1e18
        );

        vm.startPrank(governor);
        vm.expectRevert(Errors.InvalidParam.selector);
        rebalancer.setOrder(address(eurA), address(eurB), subsidyBudget + 1, guaranteedRate + 1);
        vm.stopPrank();

        vm.startPrank(governor);
        rebalancer.setOrder(address(eurA), address(eurB), subsidyBudget / 3, guaranteedRate);
        vm.stopPrank();
        (a, , , b) = rebalancer.orders(address(eurA), address(eurB));
        assertEq(a, subsidyBudget / 3);
        assertEq(b, guaranteedRate);
        assertEq(rebalancer.budget(), subsidyBudget / 3);

        assertEq(
            rebalancer.getGuaranteedAmountOut(address(eurA), address(eurB), decimalsA),
            (guaranteedRate * decimalsB) / 1e18
        );
        vm.startPrank(governor);
        rebalancer.setOrder(address(eurA), address(eurB), subsidyBudget, guaranteedRate / 2);
        vm.stopPrank();
        (a, , , b) = rebalancer.orders(address(eurA), address(eurB));
        assertEq(a, subsidyBudget);
        assertEq(b, guaranteedRate / 2);
        assertEq(rebalancer.budget(), subsidyBudget);
        assertEq(
            rebalancer.getGuaranteedAmountOut(address(eurA), address(eurB), decimalsA),
            ((guaranteedRate / 2) * decimalsB) / 1e18
        );
        // Resetting to normal
        vm.startPrank(governor);
        rebalancer.setOrder(address(eurA), address(eurB), subsidyBudget, guaranteedRate);
        vm.stopPrank();

        // Now checking with multi token budget

        vm.startPrank(governor);
        if (guaranteedRate1 > 0) {
            vm.expectRevert(Errors.InvalidParam.selector);
            rebalancer.setOrder(address(eurY), address(eurB), subsidyBudget1, guaranteedRate1);
        }
        deal(address(agToken), address(rebalancer), subsidyBudget1 + subsidyBudget);

        rebalancer.setOrder(address(eurY), address(eurB), subsidyBudget1, guaranteedRate1);
        vm.stopPrank();
        (a, , , b) = rebalancer.orders(address(eurY), address(eurB));
        assertEq(a, subsidyBudget1);
        assertEq(b, guaranteedRate1);
        assertEq(rebalancer.budget(), subsidyBudget + subsidyBudget1);
        assertEq(
            rebalancer.getGuaranteedAmountOut(address(eurY), address(eurB), decimalsY),
            (guaranteedRate1 * decimalsB) / 1e18
        );
        vm.startPrank(governor);
        if (guaranteedRate1 > 0) {
            vm.expectRevert(Errors.InvalidParam.selector);
            rebalancer.setOrder(address(eurY), address(eurB), subsidyBudget1 + 1, guaranteedRate1 + 1);
        }

        rebalancer.setOrder(address(eurY), address(eurB), subsidyBudget1, guaranteedRate1 / 2);
        vm.stopPrank();
        (a, , , b) = rebalancer.orders(address(eurY), address(eurB));
        assertEq(a, subsidyBudget1);
        assertEq(b, guaranteedRate1 / 2);
        assertEq(rebalancer.budget(), subsidyBudget + subsidyBudget1);
        assertEq(
            rebalancer.getGuaranteedAmountOut(address(eurY), address(eurB), decimalsY),
            ((guaranteedRate1 / 2) * decimalsB) / 1e18
        );

        vm.startPrank(governor);
        rebalancer.setOrder(address(eurY), address(eurB), subsidyBudget1 / 3, guaranteedRate1);
        vm.stopPrank();
        (a, , , b) = rebalancer.orders(address(eurY), address(eurB));
        assertEq(a, subsidyBudget1 / 3);
        assertEq(b, guaranteedRate1);
        assertEq(rebalancer.budget(), subsidyBudget + subsidyBudget1 / 3);
        assertEq(
            rebalancer.getGuaranteedAmountOut(address(eurY), address(eurB), decimalsY),
            (guaranteedRate1 * decimalsB) / 1e18
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
        vm.expectRevert();
        rebalancer.recover(address(eurA), 100, address(governor));
        vm.expectRevert(Errors.InvalidParam.selector);
        rebalancer.recover(address(agToken), 100, address(governor));
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
        deal(address(agToken), address(rebalancer), amount);
        rebalancer.setOrder(address(eurA), address(eurB), amount / 2, BASE_18 / 100);
        vm.stopPrank();
        (uint256 a, , , uint256 b) = rebalancer.orders(address(eurA), address(eurB));
        assertEq(a, amount / 2);
        assertEq(b, BASE_18 / 100);
        vm.startPrank(governor);
        vm.expectRevert(Errors.InvalidParam.selector);
        rebalancer.recover(address(agToken), amount - 1, address(governor));
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

        uint256 swapAmount = (multiplier * swapMultiplier * decimalsA) / 100;

        uint256 amountAgToken = transmuter.quoteIn(swapAmount, address(eurA), address(agToken));
        uint256 amountOut = transmuter.quoteIn(amountAgToken, address(agToken), address(eurB));

        assertEq(rebalancer.quoteIn(swapAmount, address(eurA), address(eurB)), amountOut);

        assertEq(
            rebalancer.quoteIn(swapAmount, address(eurA), address(eurB)),
            (multiplier * swapMultiplier * decimalsB) / 100
        );
        assertEq(
            rebalancer.quoteIn(swapAmount, address(eurA), address(eurY)),
            (multiplier * swapMultiplier * decimalsY) / 100
        );

        swapAmount = (multiplier * swapMultiplier * decimalsY) / 100;
        assertEq(
            rebalancer.quoteIn(swapAmount, address(eurY), address(eurB)),
            (multiplier * swapMultiplier * decimalsB) / 100
        );
        assertEq(
            rebalancer.quoteIn(swapAmount, address(eurY), address(eurA)),
            (multiplier * swapMultiplier * decimalsA) / 100
        );

        swapAmount = (multiplier * swapMultiplier * decimalsB) / 100;
        assertEq(
            rebalancer.quoteIn(swapAmount, address(eurB), address(eurA)),
            (multiplier * swapMultiplier * decimalsA) / 100
        );
        assertEq(
            rebalancer.quoteIn(swapAmount, address(eurB), address(eurY)),
            (multiplier * swapMultiplier * decimalsY) / 100
        );
    }

    function testFuzz_QuoteInWithSubsidy(uint256 multiplier, uint256 swapMultiplier, uint256 guaranteedRate) public {
        multiplier = bound(multiplier, 10, 10 ** 6);
        swapMultiplier = bound(swapMultiplier, 1, 100);
        guaranteedRate = bound(guaranteedRate, 10 ** 15, 10 ** 21);
        // let's first load the reserves of the protocol
        _loadReserves(charlie, multiplier);
        // Here there are no fees, and oracles are all constant -> so any mint and burn should be an onpar
        // conversion for both tokens

        uint256 swapAmount = (multiplier * swapMultiplier * decimalsA) / 100;

        uint256 guaranteedAmountOut = (swapAmount * guaranteedRate * decimalsB) / (1e18 * decimalsA);

        // This is the amount we'd normally obtain after the swap
        uint256 subsidyBudget = multiplier * swapMultiplier * 1e18;

        deal(address(agToken), address(rebalancer), subsidyBudget);
        vm.startPrank(governor);
        rebalancer.setOrder(address(eurA), address(eurB), subsidyBudget, guaranteedRate);
        vm.stopPrank();

        assertEq(rebalancer.getGuaranteedAmountOut(address(eurA), address(eurB), swapAmount), guaranteedAmountOut);

        uint256 amountAgToken = transmuter.quoteIn(swapAmount, address(eurA), address(agToken));
        uint256 amountAgTokenNeeded = transmuter.quoteOut(guaranteedAmountOut, address(agToken), address(eurB));
        uint256 subsidy;
        if (amountAgTokenNeeded > amountAgToken) {
            subsidy = amountAgTokenNeeded - amountAgToken;
            if (subsidy > subsidyBudget) subsidy = subsidyBudget;
        }

        amountAgToken += subsidy;
        uint256 amountOut = transmuter.quoteIn(amountAgToken, address(agToken), address(eurB));
        assertEq(rebalancer.quoteIn(swapAmount, address(eurA), address(eurB)), amountOut);
    }

    function test_QuoteInWithSubsidy() public {
        // let's first load the reserves of the protocol
        _loadReserves(charlie, 100);
        // Here there are no fees, and oracles are all constant -> so any mint and burn should be an onpar
        // conversion for both tokens
        uint256 swapAmount = decimalsA;

        // 1 eurB = 10^(-2)*eurA;
        uint256 guaranteedRate = 10 ** 16;

        uint256 guaranteedAmountOut = (swapAmount * guaranteedRate * decimalsB) / (1e18 * decimalsA);

        // This is the amount we'd normally obtain after the swap
        uint256 subsidyBudget = 1e19;

        deal(address(agToken), address(rebalancer), 1000 * 10 ** 18);
        vm.startPrank(governor);
        rebalancer.setOrder(address(eurA), address(eurB), subsidyBudget, guaranteedRate);
        vm.stopPrank();

        assertEq(rebalancer.getGuaranteedAmountOut(address(eurA), address(eurB), swapAmount), guaranteedAmountOut);

        // Here we're better than the exchange rate -> so get normal value and does not consume the subsidy budget
        assertEq(rebalancer.quoteIn(swapAmount, address(eurA), address(eurB)), decimalsB);

        guaranteedRate = 10 ** 19;
        guaranteedAmountOut = (swapAmount * guaranteedRate * decimalsB) / (1e18 * decimalsA);
        vm.startPrank(governor);
        rebalancer.setOrder(address(eurA), address(eurB), subsidyBudget, guaranteedRate);
        vm.stopPrank();

        assertEq(rebalancer.quoteIn(swapAmount, address(eurA), address(eurB)), 10 * decimalsB);

        assertEq(rebalancer.quoteIn(swapAmount / 2, address(eurA), address(eurB)), (10 * decimalsB) / 2);
        // Now if the swap amount is too big and empties the reserves
        // You need to put in the whole budget to cover for this but cannot get the guaranteed rate
        assertEq(rebalancer.quoteIn(swapAmount * 2, address(eurA), address(eurB)), 10 * decimalsB + 2 * decimalsB);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                   SWAP EXACT INPUT                                                 
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_SwapExactInput_Revert(uint256 multiplier, uint256 swapMultiplier) public {
        multiplier = bound(multiplier, 10, 10 ** 6);
        swapMultiplier = bound(swapMultiplier, 1, 100);
        // let's first load the reserves of the protocol
        _loadReserves(charlie, multiplier);
        uint256 swapAmount = (multiplier * swapMultiplier * decimalsA) / 100;
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

        uint256 swapAmount = (multiplier * swapMultiplier * decimalsA) / 100;
        uint256 amountOut = (multiplier * swapMultiplier * decimalsB) / 100;
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

        amountOut = (multiplier * swapMultiplier * decimalsY) / 100;
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

    function testFuzz_SwapExactInputWithSubsidy(
        uint256 multiplier,
        uint256 swapMultiplier,
        uint256 guaranteedRate
    ) public {
        multiplier = bound(multiplier, 10, 10 ** 6);
        swapMultiplier = bound(swapMultiplier, 1, 100);
        guaranteedRate = bound(guaranteedRate, 10 ** 15, 10 ** 21);
        // let's first load the reserves of the protocol
        _loadReserves(charlie, multiplier);
        // Here there are no fees, and oracles are all constant -> so any mint and burn should be an onpar
        // conversion for both tokens

        uint256 swapAmount = (multiplier * swapMultiplier * decimalsA) / 100;

        uint256 guaranteedAmountOut = (swapAmount * guaranteedRate * decimalsB) / (1e18 * decimalsA);

        deal(address(eurA), address(charlie), swapAmount * 2);

        // This is the amount we'd normally obtain after the swap
        uint256 subsidyBudget = multiplier * swapMultiplier * 1e18;

        deal(address(agToken), address(rebalancer), subsidyBudget);
        vm.startPrank(governor);
        rebalancer.setOrder(address(eurA), address(eurB), subsidyBudget, guaranteedRate);
        vm.stopPrank();

        assertEq(rebalancer.getGuaranteedAmountOut(address(eurA), address(eurB), swapAmount), guaranteedAmountOut);

        uint256 amountAgToken = transmuter.quoteIn(swapAmount, address(eurA), address(agToken));
        uint256 amountAgTokenNeeded = transmuter.quoteOut(guaranteedAmountOut, address(agToken), address(eurB));
        uint256 subsidy;
        if (amountAgTokenNeeded > amountAgToken) {
            subsidy = amountAgTokenNeeded - amountAgToken;
            if (subsidy > subsidyBudget) subsidy = subsidyBudget;
        }

        amountAgToken += subsidy;
        uint256 amountOut = transmuter.quoteIn(amountAgToken, address(agToken), address(eurB));
        assertEq(rebalancer.quoteIn(swapAmount, address(eurA), address(eurB)), amountOut);

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
        assertEq(eurB.balanceOf(address(rebalancer)), 0);
        assertEq(IERC20(address(agToken)).balanceOf(address(rebalancer)), subsidyBudget - subsidy);
        assertEq(rebalancer.budget(), subsidyBudget - subsidy);
        (uint112 subsidyBudgetLeft, , , ) = rebalancer.orders(address(eurA), address(eurB));
        assertEq(subsidyBudgetLeft, subsidyBudget - subsidy);
    }

    function test_SwapExactInputWithMultiplePartialSubsidies() public {
        // let's first load the reserves of the protocol
        _loadReserves(charlie, 100);
        // Here there are no fees, and oracles are all constant -> so any mint and burn should be an onpar
        // conversion for both tokens
        uint256 swapAmount = decimalsA;

        // 1 eurB = 10^(-2)*eurA;
        uint256 guaranteedRate = 10 ** 16;

        uint256 guaranteedAmountOut = (swapAmount * guaranteedRate * decimalsB) / (1e18 * decimalsA);

        // This is the amount we'd normally obtain after the swap
        uint256 subsidyBudget = 1e19;

        deal(address(eurA), address(charlie), swapAmount * 3);

        deal(address(agToken), address(rebalancer), subsidyBudget);
        vm.startPrank(governor);
        rebalancer.setOrder(address(eurA), address(eurB), subsidyBudget, guaranteedRate);
        vm.stopPrank();

        assertEq(rebalancer.getGuaranteedAmountOut(address(eurA), address(eurB), swapAmount), guaranteedAmountOut);

        uint256 amountOut = decimalsB;

        // Here we're better than the exchange rate -> so get normal value and does not consume the subsidy budget
        assertEq(rebalancer.quoteIn(swapAmount, address(eurA), address(eurB)), decimalsB);
        vm.startPrank(charlie);
        eurA.approve(address(rebalancer), swapAmount * 4);
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
        assertEq(eurA.allowance(address(rebalancer), address(transmuter)), type(uint256).max);
        assertEq(eurA.balanceOf(address(charlie)), swapAmount * 2);
        assertEq(eurB.balanceOf(address(bob)), amountOut);
        assertEq(eurB.balanceOf(address(rebalancer)), 0);
        assertEq(IERC20(address(agToken)).balanceOf(address(rebalancer)), subsidyBudget);
        assertEq(rebalancer.budget(), subsidyBudget);
        (uint112 subsidyBudgetLeft, , , ) = rebalancer.orders(address(eurA), address(eurB));
        assertEq(subsidyBudgetLeft, subsidyBudget);

        guaranteedRate = 10 ** 19;
        guaranteedAmountOut = (swapAmount * guaranteedRate * decimalsB) / (1e18 * decimalsA);
        vm.startPrank(governor);
        rebalancer.setOrder(address(eurA), address(eurB), subsidyBudget, guaranteedRate);
        vm.stopPrank();
        amountOut = (10 * decimalsB) / 2;

        assertEq(rebalancer.quoteIn(swapAmount / 2, address(eurA), address(eurB)), amountOut);
        assertEq(rebalancer.quoteIn(swapAmount, address(eurA), address(eurB)), 10 * decimalsB);
        assertEq(rebalancer.quoteIn(swapAmount * 2, address(eurA), address(eurB)), 10 * decimalsB + 2 * decimalsB);

        vm.startPrank(charlie);
        amountOut2 = rebalancer.swapExactInput(
            swapAmount / 2,
            0,
            address(eurA),
            address(eurB),
            address(bob),
            block.timestamp * 2
        );
        vm.stopPrank();
        // This should yield decimalsB * 10 / 2, and sponsorship for this should be decimalsB * 9 / 2 because swap
        // gives decimals / 2

        assertEq(amountOut2, amountOut);
        assertEq(eurA.allowance(address(rebalancer), address(transmuter)), type(uint256).max);
        assertEq(eurA.balanceOf(address(charlie)), (swapAmount * 3) / 2);
        assertEq(eurB.balanceOf(address(bob)), decimalsB + (10 * decimalsB) / 2);
        assertEq(eurB.balanceOf(address(rebalancer)), 0);
        assertEq(IERC20(address(agToken)).balanceOf(address(rebalancer)), (subsidyBudget * 55) / 100);
        assertEq(rebalancer.budget(), (subsidyBudget * 55) / 100);
        (subsidyBudgetLeft, , , ) = rebalancer.orders(address(eurA), address(eurB));
        assertEq(subsidyBudgetLeft, (subsidyBudget * 55) / 100);

        vm.startPrank(charlie);
        amountOut2 = rebalancer.swapExactInput(
            (swapAmount * 3) / 2,
            0,
            address(eurA),
            address(eurB),
            address(bob),
            block.timestamp * 2
        );
        vm.stopPrank();
        amountOut = (3 * decimalsB) / 2 + (decimalsB * 55) / 10;

        assertEq(amountOut2, amountOut);
        assertEq(eurA.allowance(address(rebalancer), address(transmuter)), type(uint256).max);
        assertEq(eurA.balanceOf(address(charlie)), 0);
        assertEq(eurB.balanceOf(address(bob)), decimalsB + (10 * decimalsB) / 2 + amountOut);
        assertEq(eurB.balanceOf(address(rebalancer)), 0);
        assertEq(IERC20(address(agToken)).balanceOf(address(rebalancer)), 0);
        assertEq(rebalancer.budget(), 0);
        (subsidyBudgetLeft, , , ) = rebalancer.orders(address(eurA), address(eurB));
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
            uint256 amount = multiplier * 100000 * 10 ** IERC20Metadata(_collaterals[i]).decimals();
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
