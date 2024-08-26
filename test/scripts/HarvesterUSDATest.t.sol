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
import { IERC20 } from "oz/interfaces/IERC20.sol";
import { IAgToken } from "interfaces/IAgToken.sol";
import { HarvesterVault } from "contracts/helpers/HarvesterVault.sol";

import { RebalancerFlashloanVault, IERC4626, IERC3156FlashLender } from "contracts/helpers/RebalancerFlashloanVault.sol";

interface IFlashAngle {
    function addStablecoinSupport(address _treasury) external;

    function setFlashLoanParameters(address stablecoin, uint64 _flashLoanFee, uint256 _maxBorrowable) external;
}

contract HarvesterUSDATest is Test {
    using stdJson for string;

    ITransmuter transmuter;
    IERC20 USDA;
    IAgToken treasuryUSDA;
    IFlashAngle FLASHLOAN;
    address governor;
    RebalancerFlashloanVault public rebalancer;
    uint256 ethereumFork;
    HarvesterVault harvester;
    uint64 public targetExposure;
    uint64 public maxExposureYieldAsset;
    uint64 public minExposureYieldAsset;

    function setUp() public {
        ethereumFork = vm.createSelectFork(vm.envString("ETH_NODE_URI_MAINNET"), 19939091);

        transmuter = ITransmuter(0x222222fD79264BBE280b4986F6FEfBC3524d0137);
        USDA = IERC20(0x0000206329b97DB379d5E1Bf586BbDB969C63274);
        FLASHLOAN = IFlashAngle(0x4A2FF9bC686A0A23DA13B6194C69939189506F7F);
        treasuryUSDA = IAgToken(0xf8588520E760BB0b3bDD62Ecb25186A28b0830ee);
        governor = 0xdC4e6DFe07EFCa50a197DF15D9200883eF4Eb1c8;
        // Setup rebalancer
        rebalancer = new RebalancerFlashloanVault(
            // Mock access control manager for USDA
            IAccessControlManager(0x3fc5a1bd4d0A435c55374208A6A81535A1923039),
            transmuter,
            IERC3156FlashLender(address(FLASHLOAN))
        );
        targetExposure = uint64((15 * 1e9) / 100);
        maxExposureYieldAsset = uint64((80 * 1e9) / 100);
        minExposureYieldAsset = uint64((5 * 1e9) / 100);

        harvester = new HarvesterVault(
            address(rebalancer),
            address(STEAK_USDC),
            targetExposure,
            1,
            maxExposureYieldAsset,
            minExposureYieldAsset,
            1e8
        );

        vm.startPrank(governor);
        deal(address(USDA), address(rebalancer), BASE_18 * 1000);
        rebalancer.setOrder(address(STEAK_USDC), address(USDC), BASE_18 * 500, 0);
        rebalancer.setOrder(address(USDC), address(STEAK_USDC), BASE_18 * 500, 0);
        transmuter.toggleWhitelist(Storage.WhitelistType.BACKED, NEW_DEPLOYER);
        transmuter.toggleTrusted(governor, Storage.TrustedType.Seller);
        transmuter.toggleTrusted(address(harvester), Storage.TrustedType.Seller);

        vm.stopPrank();
    }

    function testUnit_Harvest_IncreaseUSDCExposure() external {
        // At current block: USDC exposure = 7.63%, steakUSDC = 75.26%, bIB01 = 17.11%
        (uint256 fromUSDC, uint256 total) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        harvester.harvest(USDC, new bytes(0));
        (uint256 fromUSDC2, uint256 total2) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK2, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        assertGt(fromUSDC2, fromUSDC);
        assertGt(fromSTEAK, fromSTEAK2);
        assertGt(total, total2);
        assertApproxEqRel((fromUSDC2 * 1e9) / total2, targetExposure, 100 * BPS);
        assertApproxEqRel(fromUSDC2 * 1e9, targetExposure * total, 100 * BPS);

        harvester.harvest(USDC, new bytes(0));
        (uint256 fromUSDC3, uint256 total3) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK3, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        assertGt(fromUSDC3, fromUSDC2);
        assertGt(fromSTEAK2, fromSTEAK3);
        assertGt(total2, total3);
        assertGt((fromUSDC3 * 1e9) / total3, (fromUSDC2 * 1e9) / total2);
        assertApproxEqRel((fromUSDC3 * 1e9) / total3, (fromUSDC2 * 1e9) / total2, 10 * BPS);
        assertGt(targetExposure, (fromUSDC3 * 1e9) / total3);
    }

    function testUnit_Harvest_IncreaseUSDCExposureButMinValueYield() external {
        // At current block: USDC exposure = 7.63%, steakUSDC = 75.26%, bIB01 = 17.11% -> putting below
        // min exposure
        vm.startPrank(governor);
        harvester.setCollateralData(STEAK_USDC, targetExposure, (80 * 1e9) / 100, (90 * 1e9) / 100, 1);
        vm.stopPrank();
        (uint256 fromUSDC, uint256 total) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        harvester.harvest(USDC, new bytes(0));
        (uint256 fromUSDC2, uint256 total2) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK2, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        assertEq(fromUSDC2, fromUSDC);
        assertEq(fromSTEAK, fromSTEAK2);
        assertEq(total, total2);

        harvester.harvest(USDC, new bytes(0));
        (uint256 fromUSDC3, uint256 total3) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK3, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        assertEq(fromUSDC3, fromUSDC2);
        assertEq(fromSTEAK2, fromSTEAK3);
        assertEq(total2, total3);
    }

    function testUnit_Harvest_IncreaseUSDCExposureButMinValueThresholdReached() external {
        // At current block: USDC exposure = 7.63%, steakUSDC = 75.26%, bIB01 = 17.11% -> putting in between
        // min exposure and target exposure
        vm.startPrank(governor);
        harvester.setCollateralData(STEAK_USDC, targetExposure, (73 * 1e9) / 100, (90 * 1e9) / 100, 1);
        vm.stopPrank();

        (uint256 fromUSDC, uint256 total) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        harvester.harvest(USDC, new bytes(0));
        (uint256 fromUSDC2, uint256 total2) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK2, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        assertGt(fromUSDC2, fromUSDC);
        assertGt(fromSTEAK, fromSTEAK2);
        assertGt(total, total2);
        assertApproxEqRel((fromSTEAK2 * 1e9) / total2, (73 * 1e9) / 100, 100 * BPS);

        harvester.harvest(USDC, new bytes(0));
        (uint256 fromUSDC3, uint256 total3) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK3, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        assertGt(fromUSDC3, fromUSDC2);
        assertGt(fromSTEAK2, fromSTEAK3);
        assertGt(total2, total3);
        assertApproxEqRel((fromSTEAK3 * 1e9) / total3, (fromSTEAK2 * 1e9) / total2, 10 * BPS);
    }

    function testUnit_Harvest_DecreaseUSDCExposureClassical() external {
        // At current block: USDC exposure = 7.63%, steakUSDC = 75.26%, bIB01 = 17.11% -> putting below target
        vm.startPrank(governor);
        harvester.setCollateralData(STEAK_USDC, (5 * 1e9) / 100, (73 * 1e9) / 100, (90 * 1e9) / 100, 1);
        vm.stopPrank();

        (uint256 fromUSDC, uint256 total) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));

        harvester.harvest(USDC, new bytes(0));

        (uint256 fromUSDC2, uint256 total2) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK2, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        assertGt(fromUSDC, fromUSDC2);
        assertGt(fromSTEAK2, fromSTEAK);
        assertGt(total, total2);
        assertApproxEqRel((fromUSDC2 * 1e9) / total2, (5 * 1e9) / 100, 100 * BPS);

        harvester.harvest(USDC, new bytes(0));
        (uint256 fromUSDC3, uint256 total3) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK3, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        assertGt(fromUSDC2, fromUSDC3);
        assertGt(fromSTEAK3, fromSTEAK2);
        assertGt(total2, total3);
        assertGe((fromUSDC2 * 1e9) / total2, (fromUSDC3 * 1e9) / total3);
        assertGe((fromUSDC3 * 1e9) / total3, (5 * 1e9) / 100);
    }

    function testUnit_Harvest_DecreaseUSDCExposureAlreadyMaxThreshold() external {
        // At current block: USDC exposure = 7.63%, steakUSDC = 75.26%, bIB01 = 17.11% -> putting below target
        vm.startPrank(governor);
        harvester.setCollateralData(STEAK_USDC, (5 * 1e9) / 100, (73 * 1e9) / 100, (74 * 1e9) / 100, 1);
        vm.stopPrank();

        (uint256 fromUSDC, uint256 total) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));

        harvester.harvest(USDC, new bytes(0));

        (uint256 fromUSDC2, uint256 total2) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK2, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        assertEq(fromUSDC, fromUSDC2);
        assertEq(fromSTEAK2, fromSTEAK);
        assertEq(total, total2);

        harvester.harvest(USDC, new bytes(0));
        (uint256 fromUSDC3, uint256 total3) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK3, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        assertEq(fromUSDC2, fromUSDC3);
        assertEq(fromSTEAK3, fromSTEAK2);
        assertEq(total2, total3);
    }

    function testUnit_Harvest_DecreaseUSDCExposureTillMaxThreshold() external {
        // At current block: USDC exposure = 7.63%, steakUSDC = 75.26%, bIB01 = 17.11% -> putting below target
        vm.startPrank(governor);
        harvester.setCollateralData(STEAK_USDC, (5 * 1e9) / 100, (73 * 1e9) / 100, (755 * 1e9) / 1000, 1);
        vm.stopPrank();

        (uint256 fromUSDC, uint256 total) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));

        harvester.harvest(USDC, new bytes(0));

        (uint256 fromUSDC2, uint256 total2) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK2, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        assertGt(fromUSDC, fromUSDC2);
        assertGt(fromSTEAK2, fromSTEAK);
        assertGt(total, total2);
        assertLe((fromSTEAK2 * 1e9) / total2, (755 * 1e9) / 1000);
        assertApproxEqRel((fromSTEAK2 * 1e9) / total2, (755 * 1e9) / 1000, 100 * BPS);

        harvester.harvest(USDC, new bytes(0));

        (uint256 fromUSDC3, uint256 total3) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK3, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        assertGt(fromUSDC2, fromUSDC3);
        assertGt(fromSTEAK3, fromSTEAK2);
        assertGt(total2, total3);
        assertApproxEqRel((fromSTEAK3 * 1e9) / total3, (fromSTEAK2 * 1e9) / total2, 10 * BPS);
    }
}
