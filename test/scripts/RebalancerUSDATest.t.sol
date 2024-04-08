// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { stdJson } from "forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";

import "../../scripts/Constants.s.sol";

import { Helpers } from "../../scripts/Helpers.s.sol";
import "contracts/utils/Errors.sol" as Errors;
import "contracts/transmuter/Storage.sol" as Storage;
import "contracts/transmuter/libraries/LibHelpers.sol";
import { CollateralSetupProd } from "contracts/transmuter/configs/ProductionTypes.sol";
import { ITransmuter } from "interfaces/ITransmuter.sol";
import "utils/src/Constants.sol";
import { IERC20 } from "oz/interfaces/IERC20.sol";
import { IAgToken } from "interfaces/IAgToken.sol";

import { RebalancerFlashloan, IERC4626, IERC3156FlashLender } from "contracts/helpers/RebalancerFlashloan.sol";

interface IFlashAngle {
    function addStablecoinSupport(address _treasury) external;
    function setFlashLoanParameters(address stablecoin, uint64 _flashLoanFee, uint256 _maxBorrowable) external;
}

contract RebalancerUSDATest is Helpers, Test {
    using stdJson for string;

    ITransmuter transmuter;
    IERC20 USDA;
    IAgToken treasuryUSDA;
    IFlashAngle FLASHLOAN;
    address governor;
    RebalancerFlashloan public rebalancer;

    function setUp() public override {
        super.setUp();

        ethereumFork = vm.createFork(vm.envString("ETH_NODE_URI_MAINNET"), 19610333);
        vm.selectFork(ethereumFork);

        transmuter = ITransmuter(0x222222fD79264BBE280b4986F6FEfBC3524d0137);
        USDA = IERC20(0x0000206329b97DB379d5E1Bf586BbDB969C63274);
        FLASHLOAN = IFlashAngle(0x4A2FF9bC686A0A23DA13B6194C69939189506F7F);
        treasuryUSDA = IAgToken(0xf8588520E760BB0b3bDD62Ecb25186A28b0830ee);
        governor = 0xdC4e6DFe07EFCa50a197DF15D9200883eF4Eb1c8;

        vm.startPrank(governor);
        transmuter.toggleWhitelist(Storage.WhitelistType.BACKED, NEW_DEPLOYER);
        transmuter.toggleTrusted(governor, Storage.TrustedType.Seller);
        IAgToken(treasuryUSDA).addMinter(address(FLASHLOAN));
        vm.stopPrank();

        // Setup rebalancer
        rebalancer = new RebalancerFlashloan(
            // Mock access control manager for USDA
            IAccessControlManager(0x3fc5a1bd4d0A435c55374208A6A81535A1923039),
            transmuter,
            IERC3156FlashLender(address(FLASHLOAN))
        );

        // Setup flashloan
        // Core contract
        vm.startPrank(0x5bc6BEf80DA563EBf6Df6D6913513fa9A7ec89BE);
        FLASHLOAN.addStablecoinSupport(address(treasuryUSDA));
        vm.stopPrank();
        // Governor address
        vm.startPrank(governor);
        FLASHLOAN.setFlashLoanParameters(address(USDA), 0, type(uint256).max);
        vm.stopPrank();

        // Initialize Transmuter reserves
        deal(BIB01, NEW_DEPLOYER, 100000 * BASE_18);
        vm.startPrank(NEW_DEPLOYER);
        IERC20(BIB01).approve(address(transmuter), type(uint256).max);
        transmuter.swapExactOutput(
            1200 * 10 ** 21,
            type(uint256).max,
            BIB01,
            address(USDA),
            NEW_DEPLOYER,
            block.timestamp
        );
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        GETTERS
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testUnit_RebalancerSetup() external {
        assertEq(address(transmuter.agToken()), 0x0000206329b97DB379d5E1Bf586BbDB969C63274);
        // Revert when no order has been setup
        vm.startPrank(NEW_DEPLOYER);
        vm.expectRevert();
        rebalancer.adjustYieldExposure(BASE_18, 1, USDC, STEAK_USDC);

        vm.expectRevert();
        rebalancer.adjustYieldExposure(BASE_18, 0, USDC, STEAK_USDC);
        vm.stopPrank();
    }

    function testFuzz_adjustYieldExposure_SuccessIncrease(uint256 amount) external {
        amount = bound(amount, BASE_18, BASE_18 * 100);
        deal(address(USDA), address(rebalancer), BASE_18 * 1000);
        (uint256 fromUSDC, uint256 total) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        vm.startPrank(governor);
        rebalancer.setOrder(address(STEAK_USDC), address(USDC), BASE_18 * 500, 0);
        rebalancer.setOrder(address(USDC), address(STEAK_USDC), BASE_18 * 500, 0);

        uint256 budget = rebalancer.budget();
        (uint112 orderBudget0, , , ) = rebalancer.orders(address(USDC), address(STEAK_USDC));
        (uint112 orderBudget1, , , ) = rebalancer.orders(address(STEAK_USDC), address(USDC));
        rebalancer.adjustYieldExposure(amount, 1, USDC, STEAK_USDC);

        vm.stopPrank();

        (uint256 fromUSDCPost, uint256 totalPost) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAKPost, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        assertLe(totalPost, total);
        assertEq(fromUSDCPost, fromUSDC - amount);
        assertLe(fromSTEAKPost, fromSTEAK + amount);
        assertGe(fromSTEAKPost, fromSTEAK);
        assertLe(rebalancer.budget(), budget);
        (uint112 newOrder0, , , ) = rebalancer.orders(address(USDC), address(STEAK_USDC));
        (uint112 newOrder1, , , ) = rebalancer.orders(address(STEAK_USDC), address(USDC));
        assertEq(newOrder0, orderBudget0);
        assertLe(newOrder1, orderBudget1);
    }

    function testFuzz_adjustYieldExposure_SuccessDecrease(uint256 amount) external {
        amount = bound(amount, BASE_18, BASE_18 * 100);
        deal(address(USDA), address(rebalancer), BASE_18 * 1000);
        (uint256 fromUSDC, uint256 total) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        vm.startPrank(governor);
        rebalancer.setOrder(address(STEAK_USDC), address(USDC), BASE_18 * 500, 0);
        rebalancer.setOrder(address(USDC), address(STEAK_USDC), BASE_18 * 500, 0);
        uint256 budget = rebalancer.budget();
        (uint112 orderBudget0, , , ) = rebalancer.orders(address(USDC), address(STEAK_USDC));
        (uint112 orderBudget1, , , ) = rebalancer.orders(address(STEAK_USDC), address(USDC));
        rebalancer.adjustYieldExposure(amount, 0, USDC, STEAK_USDC);
        vm.stopPrank();
        (uint256 fromUSDCPost, uint256 totalPost) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAKPost, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        assertLe(totalPost, total);
        assertLe(fromUSDCPost, fromUSDC + amount);
        assertGe(fromUSDCPost, fromUSDC);
        assertEq(fromSTEAKPost, fromSTEAK - amount);
        assertLe(rebalancer.budget(), budget);
        (uint112 newOrder0, , , ) = rebalancer.orders(address(USDC), address(STEAK_USDC));
        (uint112 newOrder1, , , ) = rebalancer.orders(address(STEAK_USDC), address(USDC));
        assertLe(newOrder0, orderBudget0);
        assertEq(newOrder1, orderBudget1);
    }

    function testFuzz_adjustYieldExposure_SuccessNoBudgetIncrease(uint256 amount) external {
        amount = bound(amount, BASE_18, BASE_18 * 100);
        deal(address(USDA), address(rebalancer), BASE_18 * 1000);
        (uint256 fromUSDC, uint256 total) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        vm.startPrank(governor);
        uint64[] memory xMintFee = new uint64[](1);
        xMintFee[0] = uint64(0);
        int64[] memory yMintFee = new int64[](1);
        yMintFee[0] = int64(0);
        uint64[] memory xBurnFee = new uint64[](1);
        xBurnFee[0] = uint64(BASE_9);
        int64[] memory yBurnFee = new int64[](1);
        yBurnFee[0] = int64(uint64(0));
        transmuter.setFees(STEAK_USDC, xMintFee, yMintFee, true);
        transmuter.setFees(STEAK_USDC, xBurnFee, yBurnFee, false);
        assertEq(rebalancer.budget(), 0);

        transmuter.setFees(STEAK_USDC, xMintFee, yMintFee, true);
        transmuter.updateOracle(STEAK_USDC);
        rebalancer.adjustYieldExposure(amount, 1, USDC, STEAK_USDC);
        vm.stopPrank();
        (uint256 fromUSDCPost, uint256 totalPost) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAKPost, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        assertGe(totalPost, total);
        assertEq(fromUSDCPost, fromUSDC - amount);
        assertGe(fromSTEAKPost, fromSTEAK + amount);
    }

    function testFuzz_adjustYieldExposure_SuccessDecreaseSplit(uint256 amount, uint256 split) external {
        amount = bound(amount, BASE_18, BASE_18 * 100);
        split = bound(split, BASE_9 / 4, (BASE_9 * 3) / 4);
        deal(address(USDA), address(rebalancer), BASE_18 * 1000);
        (uint256 fromUSDC, uint256 total) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        vm.startPrank(governor);
        rebalancer.setOrder(address(STEAK_USDC), address(USDC), BASE_18 * 500, 0);
        rebalancer.setOrder(address(USDC), address(STEAK_USDC), BASE_18 * 500, 0);
        uint256 budget = rebalancer.budget();
        (uint112 orderBudget0, , , ) = rebalancer.orders(address(USDC), address(STEAK_USDC));
        (uint112 orderBudget1, , , ) = rebalancer.orders(address(STEAK_USDC), address(USDC));

        rebalancer.adjustYieldExposure((amount * split) / BASE_9, 0, USDC, STEAK_USDC);

        (uint256 fromUSDCPost, uint256 totalPost) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAKPost, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        assertLe(totalPost, total);
        assertLe(fromUSDCPost, fromUSDC + (amount * split) / BASE_9);
        assertGe(fromUSDCPost, fromUSDC);
        assertEq(fromSTEAKPost, fromSTEAK - (amount * split) / BASE_9);
        assertLe(rebalancer.budget(), budget);

        rebalancer.adjustYieldExposure(amount - (amount * split) / BASE_9, 0, USDC, STEAK_USDC);

        (fromUSDCPost, totalPost) = transmuter.getIssuedByCollateral(address(USDC));
        (fromSTEAKPost, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        assertLe(totalPost, total);
        assertLe(fromUSDCPost, fromUSDC + amount);
        assertGe(fromUSDCPost, fromUSDC);
        assertEq(fromSTEAKPost, fromSTEAK - amount);
        assertLe(rebalancer.budget(), budget);
        (uint112 newOrder0, , , ) = rebalancer.orders(address(USDC), address(STEAK_USDC));
        (uint112 newOrder1, , , ) = rebalancer.orders(address(STEAK_USDC), address(USDC));
        assertLe(newOrder0, orderBudget0);
        assertEq(newOrder1, orderBudget1);

        vm.stopPrank();
    }

    function testFuzz_adjustYieldExposure_SuccessIncreaseSplit(uint256 amount, uint256 split) external {
        amount = bound(amount, BASE_18, BASE_18 * 100);
        split = bound(split, BASE_9 / 4, (BASE_9 * 3) / 4);
        deal(address(USDA), address(rebalancer), BASE_18 * 1000);
        (uint256 fromUSDC, uint256 total) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        vm.startPrank(governor);
        rebalancer.setOrder(address(STEAK_USDC), address(USDC), BASE_18 * 500, 0);
        rebalancer.setOrder(address(USDC), address(STEAK_USDC), BASE_18 * 500, 0);
        uint256 budget = rebalancer.budget();
        (uint112 orderBudget0, , , ) = rebalancer.orders(address(USDC), address(STEAK_USDC));
        (uint112 orderBudget1, , , ) = rebalancer.orders(address(STEAK_USDC), address(USDC));

        rebalancer.adjustYieldExposure((amount * split) / BASE_9, 1, USDC, STEAK_USDC);

        (uint256 fromUSDCPost, uint256 totalPost) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAKPost, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        assertLe(totalPost, total);
        assertEq(fromUSDCPost, fromUSDC - (amount * split) / BASE_9);
        assertLe(fromSTEAKPost, fromSTEAK + (amount * split) / BASE_9);
        assertGe(fromSTEAKPost, fromSTEAK);
        assertLe(rebalancer.budget(), budget);

        rebalancer.adjustYieldExposure(amount - (amount * split) / BASE_9, 1, USDC, STEAK_USDC);

        (fromUSDCPost, totalPost) = transmuter.getIssuedByCollateral(address(USDC));
        (fromSTEAKPost, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        assertLe(totalPost, total);
        assertEq(fromUSDCPost, fromUSDC - amount);
        assertLe(fromSTEAKPost, fromSTEAK + amount);
        assertGe(fromSTEAKPost, fromSTEAK);
        assertLe(rebalancer.budget(), budget);
        (uint112 newOrder0, , , ) = rebalancer.orders(address(USDC), address(STEAK_USDC));
        (uint112 newOrder1, , , ) = rebalancer.orders(address(STEAK_USDC), address(USDC));
        assertEq(newOrder0, orderBudget0);
        assertLe(newOrder1, orderBudget1);

        vm.stopPrank();
    }

    function testFuzz_adjustYieldExposure_SuccessAltern(uint256 amount) external {
        amount = bound(amount, BASE_18, BASE_18 * 100);
        deal(address(USDA), address(rebalancer), BASE_18 * 1000);
        (uint256 fromUSDC, uint256 total) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        vm.startPrank(governor);
        rebalancer.setOrder(address(STEAK_USDC), address(USDC), BASE_18 * 500, 0);
        rebalancer.setOrder(address(USDC), address(STEAK_USDC), BASE_18 * 500, 0);
        uint256 budget = rebalancer.budget();
        (uint112 orderBudget0, , , ) = rebalancer.orders(address(USDC), address(STEAK_USDC));
        (uint112 orderBudget1, , , ) = rebalancer.orders(address(STEAK_USDC), address(USDC));

        rebalancer.adjustYieldExposure(amount, 1, USDC, STEAK_USDC);

        (uint256 fromUSDCPost, uint256 totalPost) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAKPost, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        assertLe(totalPost, total);
        assertEq(fromUSDCPost, fromUSDC - amount);
        assertLe(fromSTEAKPost, fromSTEAK + amount);
        assertGe(fromSTEAKPost, fromSTEAK);
        assertLe(rebalancer.budget(), budget);
        (uint112 newOrder0, , , ) = rebalancer.orders(address(USDC), address(STEAK_USDC));
        (uint112 newOrder1, , , ) = rebalancer.orders(address(STEAK_USDC), address(USDC));
        assertEq(newOrder0, orderBudget0);
        assertLe(newOrder1, orderBudget1);

        rebalancer.adjustYieldExposure(amount, 0, USDC, STEAK_USDC);

        (orderBudget0, , , ) = rebalancer.orders(address(USDC), address(STEAK_USDC));
        (orderBudget1, , , ) = rebalancer.orders(address(STEAK_USDC), address(USDC));
        assertLe(orderBudget0, newOrder0);
        assertEq(orderBudget1, newOrder1);

        (uint256 fromUSDCPost2, uint256 totalPost2) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAKPost2, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));

        assertLe(totalPost2, totalPost);
        assertLe(fromUSDCPost2, fromUSDC);
        assertLe(fromSTEAKPost2, fromSTEAK);
        assertLe(fromSTEAKPost2, fromSTEAKPost);
        assertGe(fromUSDCPost2, fromUSDCPost);
        assertLe(rebalancer.budget(), budget);

        vm.stopPrank();
    }
}
