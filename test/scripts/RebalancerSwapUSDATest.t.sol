// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { stdJson } from "forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";

import "../../scripts/Constants.s.sol";

import "contracts/utils/Errors.sol" as Errors;
import "contracts/transmuter/Storage.sol" as Storage;
import "contracts/transmuter/libraries/LibHelpers.sol";
import { CollateralSetupProd } from "contracts/transmuter/configs/ProductionTypes.sol";
import { ITransmuter } from "interfaces/ITransmuter.sol";
import "utils/src/Constants.sol";
import "utils/src/CommonUtils.sol";
import { IERC20 } from "oz/interfaces/IERC20.sol";
import { IAgToken } from "interfaces/IAgToken.sol";
import { MockRouter } from "../mock/MockRouter.sol";

import { RebalancerFlashloanSwap, IERC3156FlashLender } from "contracts/helpers/RebalancerFlashloanSwap.sol";

interface IFlashAngle {
    function addStablecoinSupport(address _treasury) external;

    function setFlashLoanParameters(address stablecoin, uint64 _flashLoanFee, uint256 _maxBorrowable) external;
}

contract RebalancerSwapUSDATest is Test, CommonUtils {
    using stdJson for string;

    ITransmuter transmuter;
    IERC20 USDA;
    IAgToken treasuryUSDA;
    IFlashAngle FLASHLOAN;
    address governor;
    RebalancerFlashloanSwap public rebalancer;
    MockRouter public router;

    address constant WHALE = 0x54D7aE423Edb07282645e740C046B9373970a168;

    function setUp() public {
        ethereumFork = vm.createSelectFork(vm.envString("ETH_NODE_URI_MAINNET"), 20590478);

        transmuter = ITransmuter(_chainToContract(CHAIN_ETHEREUM, ContractType.TransmuterAgUSD));
        USDA = IERC20(_chainToContract(CHAIN_ETHEREUM, ContractType.AgUSD));
        FLASHLOAN = IFlashAngle(_chainToContract(CHAIN_ETHEREUM, ContractType.FlashLoan));
        treasuryUSDA = IAgToken(_chainToContract(CHAIN_ETHEREUM, ContractType.TreasuryAgUSD));
        governor = _chainToContract(CHAIN_ETHEREUM, ContractType.GovernorMultisig);

        vm.startPrank(governor);
        transmuter.toggleWhitelist(Storage.WhitelistType.BACKED, NEW_DEPLOYER);
        transmuter.toggleTrusted(governor, Storage.TrustedType.Seller);
        IAgToken(treasuryUSDA).addMinter(address(FLASHLOAN));
        vm.stopPrank();

        // Setup rebalancer
        router = new MockRouter();
        rebalancer = new RebalancerFlashloanSwap(
            // Mock access control manager for USDA
            IAccessControlManager(0x3fc5a1bd4d0A435c55374208A6A81535A1923039),
            transmuter,
            IERC3156FlashLender(address(FLASHLOAN)),
            address(router),
            address(router),
            50
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
        deal(USDC, NEW_DEPLOYER, 100000 * BASE_18);
        vm.startPrank(NEW_DEPLOYER);
        IERC20(USDC).approve(address(transmuter), type(uint256).max);
        transmuter.swapExactOutput(
            1200 * 10 ** 21,
            type(uint256).max,
            USDC,
            address(USDA),
            NEW_DEPLOYER,
            block.timestamp
        );
        vm.stopPrank();
        vm.startPrank(WHALE);
        IERC20(USDM).approve(address(transmuter), type(uint256).max);
        transmuter.swapExactOutput(1200 * 10 ** 21, type(uint256).max, USDM, address(USDA), WHALE, block.timestamp);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        GETTERS
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testUnit_RebalancerSetup() external {
        assertEq(address(transmuter.agToken()), 0x0000206329b97DB379d5E1Bf586BbDB969C63274);
        // Revert when no order has been setup
        vm.startPrank(governor);
        vm.expectRevert();
        rebalancer.adjustYieldExposure(BASE_18, 1, USDC, USDM, 0, new bytes(0));

        vm.expectRevert();
        rebalancer.adjustYieldExposure(BASE_18, 0, USDC, USDM, 0, new bytes(0));
        vm.stopPrank();
    }

    function testFuzz_adjustYieldExposure_SuccessIncrease(uint256 amount) external {
        amount = bound(amount, BASE_18, BASE_18 * 100);

        uint256 quoteAmount = transmuter.quoteIn(amount, address(USDA), USDC);
        vm.prank(WHALE);
        IERC20(USDM).transfer(address(router), amount);
        deal(address(USDA), address(rebalancer), BASE_18 * 1000);

        (uint256 fromUSDC, uint256 total) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromUSDM, ) = transmuter.getIssuedByCollateral(address(USDM));

        vm.startPrank(governor);
        rebalancer.setOrder(address(USDM), address(USDC), BASE_18 * 500, 0);
        rebalancer.setOrder(address(USDC), address(USDM), BASE_18 * 500, 0);

        uint256 budget = rebalancer.budget();
        (uint112 orderBudget0, , , ) = rebalancer.orders(address(USDC), address(USDM));
        (uint112 orderBudget1, , , ) = rebalancer.orders(address(USDM), address(USDC));

        bytes memory data = abi.encodeWithSelector(
            MockRouter.swap.selector,
            quoteAmount,
            USDC,
            quoteAmount * 1e12,
            USDM
        );
        rebalancer.adjustYieldExposure(amount, 1, USDC, USDM, 0, data);

        vm.stopPrank();

        (uint256 fromUSDCPost, uint256 totalPost) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromUSDMPost, ) = transmuter.getIssuedByCollateral(address(USDM));
        assertLe(totalPost, total);
        assertEq(fromUSDCPost, fromUSDC - amount);
        assertLe(fromUSDMPost, fromUSDM + amount);
        assertGe(fromUSDMPost, fromUSDM);
        assertLe(rebalancer.budget(), budget);
        (uint112 newOrder0, , , ) = rebalancer.orders(address(USDC), address(USDM));
        (uint112 newOrder1, , , ) = rebalancer.orders(address(USDM), address(USDC));
        assertEq(newOrder0, orderBudget0);
        assertLe(newOrder1, orderBudget1);
    }

    function testFuzz_adjustYieldExposure_RevertMinAmountOut(uint256 amount) external {
        amount = bound(amount, BASE_18, BASE_18 * 100);

        uint256 quoteAmount = transmuter.quoteIn(amount, address(USDA), USDC);
        vm.prank(WHALE);
        IERC20(USDM).transfer(address(router), amount);

        deal(address(USDA), address(rebalancer), BASE_18 * 1000);
        vm.startPrank(governor);
        rebalancer.setOrder(address(USDM), address(USDC), BASE_18 * 500, 0);
        rebalancer.setOrder(address(USDC), address(USDM), BASE_18 * 500, 0);

        bytes memory data = abi.encodeWithSelector(
            MockRouter.swap.selector,
            quoteAmount,
            USDC,
            quoteAmount * 1e12,
            USDM
        );
        vm.expectRevert();
        rebalancer.adjustYieldExposure(amount, 1, USDC, USDM, type(uint256).max, data);

        vm.stopPrank();
    }

    function testFuzz_adjustYieldExposure_SuccessDecrease(uint256 amount) external {
        amount = bound(amount, BASE_18, BASE_18 * 100);

        uint256 quoteAmount = transmuter.quoteIn(amount, address(USDA), USDM);
        deal(USDC, address(router), amount);

        deal(address(USDA), address(rebalancer), BASE_18 * 1000);
        (uint256 fromUSDC, uint256 total) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromUSDM, ) = transmuter.getIssuedByCollateral(address(USDM));

        vm.startPrank(governor);
        rebalancer.setOrder(address(USDM), address(USDC), BASE_18 * 500, 0);
        rebalancer.setOrder(address(USDC), address(USDM), BASE_18 * 500, 0);
        uint256 budget = rebalancer.budget();
        (uint112 orderBudget0, , , ) = rebalancer.orders(address(USDC), address(USDM));
        (uint112 orderBudget1, , , ) = rebalancer.orders(address(USDM), address(USDC));

        bytes memory data = abi.encodeWithSelector(
            MockRouter.swap.selector,
            quoteAmount,
            USDM,
            quoteAmount / 1e12,
            USDC
        );
        rebalancer.adjustYieldExposure(amount, 0, USDC, USDM, 0, data);
        vm.stopPrank();

        (uint256 fromUSDCPost, uint256 totalPost) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromUSDMPost, ) = transmuter.getIssuedByCollateral(address(USDM));
        assertLe(totalPost, total);
        assertLe(fromUSDCPost, fromUSDC + amount);
        assertGe(fromUSDCPost, fromUSDC);
        assertEq(fromUSDMPost, fromUSDM - amount);
        assertLe(rebalancer.budget(), budget);
        (uint112 newOrder0, , , ) = rebalancer.orders(address(USDC), address(USDM));
        (uint112 newOrder1, , , ) = rebalancer.orders(address(USDM), address(USDC));
        assertLe(newOrder0, orderBudget0);
        assertEq(newOrder1, orderBudget1);
    }

    function testFuzz_adjustYieldExposure_TooHighSlipage(uint256 amount) external {
        amount = bound(amount, BASE_18, BASE_18 * 100);

        uint256 quoteAmount = transmuter.quoteIn(amount, address(USDA), USDC);
        vm.prank(WHALE);
        IERC20(USDM).transfer(address(router), amount);
        deal(address(USDA), address(rebalancer), BASE_18 * 1000);

        (uint256 fromUSDC, uint256 total) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromUSDM, ) = transmuter.getIssuedByCollateral(address(USDM));

        vm.startPrank(governor);
        rebalancer.setOrder(address(USDM), address(USDC), BASE_18 * 500, 0);
        rebalancer.setOrder(address(USDC), address(USDM), BASE_18 * 500, 0);

        uint256 budget = rebalancer.budget();
        (uint112 orderBudget0, , , ) = rebalancer.orders(address(USDC), address(USDM));
        (uint112 orderBudget1, , , ) = rebalancer.orders(address(USDM), address(USDC));

        bytes memory data = abi.encodeWithSelector(
            MockRouter.swap.selector,
            quoteAmount,
            USDC,
            quoteAmount - ((quoteAmount * rebalancer.maxSlippage()) / BPS) * 1e12,
            USDM
        );
        vm.expectRevert();
        rebalancer.adjustYieldExposure(amount, 1, USDC, USDM, 0, data);

        vm.stopPrank();
    }

    function testFuzz_adjustYieldExposure_SuccessDecreaseSplit(uint256 amount, uint256 split) external {
        amount = bound(amount, BASE_18, BASE_18 * 100);

        deal(USDC, address(router), amount);

        split = bound(split, BASE_9 / 4, (BASE_9 * 3) / 4);
        deal(address(USDA), address(rebalancer), BASE_18 * 1000);
        (uint256 fromUSDC, uint256 total) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromUSDM, ) = transmuter.getIssuedByCollateral(address(USDM));
        vm.startPrank(governor);
        rebalancer.setOrder(address(USDM), address(USDC), BASE_18 * 500, 0);
        rebalancer.setOrder(address(USDC), address(USDM), BASE_18 * 500, 0);
        uint256 budget = rebalancer.budget();
        (uint112 orderBudget0, , , ) = rebalancer.orders(address(USDC), address(USDM));
        (uint112 orderBudget1, , , ) = rebalancer.orders(address(USDM), address(USDC));

        {
            uint256 quoteAmount = transmuter.quoteIn((amount * split) / BASE_9, address(USDA), USDM);
            bytes memory data = abi.encodeWithSelector(
                MockRouter.swap.selector,
                quoteAmount,
                USDM,
                quoteAmount / 1e12,
                USDC
            );
            rebalancer.adjustYieldExposure((amount * split) / BASE_9, 0, USDC, USDM, 0, data);
        }

        (uint256 fromUSDCPost, uint256 totalPost) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromUSDMPost, ) = transmuter.getIssuedByCollateral(address(USDM));
        assertLe(totalPost, total);
        assertLe(fromUSDCPost, fromUSDC + (amount * split) / BASE_9);
        assertGe(fromUSDCPost, fromUSDC);
        assertEq(fromUSDMPost, fromUSDM - (amount * split) / BASE_9);
        assertLe(rebalancer.budget(), budget);

        {
            uint256 finalAmount = amount - (amount * split) / BASE_9;
            uint256 quoteAmount = transmuter.quoteIn(finalAmount, address(USDA), USDM);
            bytes memory data = abi.encodeWithSelector(
                MockRouter.swap.selector,
                quoteAmount,
                USDM,
                quoteAmount / 1e12,
                USDC
            );
            rebalancer.adjustYieldExposure(finalAmount, 0, USDC, USDM, 0, data);
        }

        (fromUSDCPost, totalPost) = transmuter.getIssuedByCollateral(address(USDC));
        (fromUSDMPost, ) = transmuter.getIssuedByCollateral(address(USDM));
        assertLe(totalPost, total);
        assertLe(fromUSDCPost, fromUSDC + amount);
        assertGe(fromUSDCPost, fromUSDC);
        assertEq(fromUSDMPost, fromUSDM - amount);
        assertLe(rebalancer.budget(), budget);
        (uint112 newOrder0, , , ) = rebalancer.orders(address(USDC), address(USDM));
        (uint112 newOrder1, , , ) = rebalancer.orders(address(USDM), address(USDC));
        assertLe(newOrder0, orderBudget0);
        assertEq(newOrder1, orderBudget1);

        vm.stopPrank();
    }

    function testFuzz_adjustYieldExposure_SuccessIncreaseSplit(uint256 amount, uint256 split) external {
        amount = bound(amount, BASE_18, BASE_18 * 100);

        vm.prank(WHALE);
        IERC20(USDM).transfer(address(router), amount);

        split = bound(split, BASE_9 / 4, (BASE_9 * 3) / 4);
        deal(address(USDA), address(rebalancer), BASE_18 * 1000);
        (uint256 fromUSDC, uint256 total) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromUSDM, ) = transmuter.getIssuedByCollateral(address(USDM));
        vm.startPrank(governor);
        rebalancer.setOrder(address(USDM), address(USDC), BASE_18 * 500, 0);
        rebalancer.setOrder(address(USDC), address(USDM), BASE_18 * 500, 0);
        uint256 budget = rebalancer.budget();
        (uint112 orderBudget0, , , ) = rebalancer.orders(address(USDC), address(USDM));
        (uint112 orderBudget1, , , ) = rebalancer.orders(address(USDM), address(USDC));

        {
            uint256 quoteAmount = transmuter.quoteIn((amount * split) / BASE_9, address(USDA), USDC);
            bytes memory data = abi.encodeWithSelector(
                MockRouter.swap.selector,
                quoteAmount,
                USDC,
                quoteAmount * 1e12,
                USDM
            );
            rebalancer.adjustYieldExposure((amount * split) / BASE_9, 1, USDC, USDM, 0, data);
        }

        (uint256 fromUSDCPost, uint256 totalPost) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromUSDMPost, ) = transmuter.getIssuedByCollateral(address(USDM));
        assertLe(totalPost, total);
        assertEq(fromUSDCPost, fromUSDC - (amount * split) / BASE_9);
        assertLe(fromUSDMPost, fromUSDM + (amount * split) / BASE_9);
        assertGe(fromUSDMPost, fromUSDM);
        assertLe(rebalancer.budget(), budget);

        {
            uint256 finalAmount = amount - (amount * split) / BASE_9;
            uint256 quoteAmount = transmuter.quoteIn(finalAmount, address(USDA), USDC);
            bytes memory data = abi.encodeWithSelector(
                MockRouter.swap.selector,
                quoteAmount,
                USDC,
                quoteAmount * 1e12,
                USDM
            );
            rebalancer.adjustYieldExposure(finalAmount, 1, USDC, USDM, 0, data);
        }

        (fromUSDCPost, totalPost) = transmuter.getIssuedByCollateral(address(USDC));
        (fromUSDMPost, ) = transmuter.getIssuedByCollateral(address(USDM));
        assertLe(totalPost, total);
        assertEq(fromUSDCPost, fromUSDC - amount);
        assertLe(fromUSDMPost, fromUSDM + amount);
        assertGe(fromUSDMPost, fromUSDM);
        assertLe(rebalancer.budget(), budget);
        (uint112 newOrder0, , , ) = rebalancer.orders(address(USDC), address(USDM));
        (uint112 newOrder1, , , ) = rebalancer.orders(address(USDM), address(USDC));
        assertEq(newOrder0, orderBudget0);
        assertLe(newOrder1, orderBudget1);

        vm.stopPrank();
    }

    function testFuzz_adjustYieldExposure_SuccessAltern(uint256 amount) external {
        amount = bound(amount, BASE_18, BASE_18 * 100);

        vm.prank(WHALE);
        IERC20(USDM).transfer(address(router), amount);

        deal(address(USDA), address(rebalancer), BASE_18 * 1000);
        (uint256 fromUSDC, uint256 total) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromUSDM, ) = transmuter.getIssuedByCollateral(address(USDM));
        vm.startPrank(governor);
        rebalancer.setOrder(address(USDM), address(USDC), BASE_18 * 500, 0);
        rebalancer.setOrder(address(USDC), address(USDM), BASE_18 * 500, 0);
        uint256 budget = rebalancer.budget();
        (uint112 orderBudget0, , , ) = rebalancer.orders(address(USDC), address(USDM));
        (uint112 orderBudget1, , , ) = rebalancer.orders(address(USDM), address(USDC));

        {
            uint256 quoteAmount = transmuter.quoteIn(amount, address(USDA), USDC);
            bytes memory data = abi.encodeWithSelector(
                MockRouter.swap.selector,
                quoteAmount,
                USDC,
                quoteAmount * 1e12,
                USDM
            );
            rebalancer.adjustYieldExposure(amount, 1, USDC, USDM, 0, data);
        }

        (uint256 fromUSDCPost, uint256 totalPost) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromUSDMPost, ) = transmuter.getIssuedByCollateral(address(USDM));
        assertLe(totalPost, total);
        assertEq(fromUSDCPost, fromUSDC - amount);
        assertLe(fromUSDMPost, fromUSDM + amount);
        assertGe(fromUSDMPost, fromUSDM);
        assertLe(rebalancer.budget(), budget);
        (uint112 newOrder0, , , ) = rebalancer.orders(address(USDC), address(USDM));
        (uint112 newOrder1, , , ) = rebalancer.orders(address(USDM), address(USDC));
        assertEq(newOrder0, orderBudget0);
        assertLe(newOrder1, orderBudget1);

        {
            uint256 quoteAmount = transmuter.quoteIn(amount, address(USDA), USDM);
            bytes memory data = abi.encodeWithSelector(
                MockRouter.swap.selector,
                quoteAmount,
                USDM,
                quoteAmount / 1e12,
                USDC
            );
            rebalancer.adjustYieldExposure(amount, 0, USDC, USDM, 0, data);
        }

        (orderBudget0, , , ) = rebalancer.orders(address(USDC), address(USDM));
        (orderBudget1, , , ) = rebalancer.orders(address(USDM), address(USDC));
        assertLe(orderBudget0, newOrder0);
        assertEq(orderBudget1, newOrder1);

        (uint256 fromUSDCPost2, uint256 totalPost2) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromUSDMPost2, ) = transmuter.getIssuedByCollateral(address(USDM));

        assertLe(totalPost2, totalPost);
        assertLe(fromUSDCPost2, fromUSDC);
        assertLe(fromUSDMPost2, fromUSDM);
        assertLe(fromUSDMPost2, fromUSDMPost);
        assertGe(fromUSDCPost2, fromUSDCPost);
        assertLe(rebalancer.budget(), budget);

        vm.stopPrank();
    }
}
