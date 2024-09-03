// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";

import { stdError } from "forge-std/Test.sol";

import "contracts/utils/Errors.sol" as Errors;

import "../Fixture.sol";
import { IERC20Metadata } from "../mock/MockTokenPermit.sol";
import "../utils/FunctionUtils.sol";

import "contracts/savings/Savings.sol";
import "../mock/MockTokenPermit.sol";
import "contracts/helpers/RebalancerFlashloanVault.sol";
import "contracts/helpers/HarvesterVault.sol";

contract HarvesterTest is Fixture, FunctionUtils {
    using SafeERC20 for IERC20;

    RebalancerFlashloanVault public rebalancer;
    HarvesterVault public harvester;
    Savings internal _saving;
    address internal _savingImplementation;
    string internal _name;
    string internal _symbol;
    address public collat;
    uint64 public targetExposure;
    uint64 public maxExposureYieldAsset;
    uint64 public minExposureYieldAsset;

    function setUp() public override {
        super.setUp();

        MockTokenPermit token = new MockTokenPermit("EURC", "EURC", 6);
        collat = address(token);

        _savingImplementation = address(new Savings());
        bytes memory data;
        _saving = Savings(_deployUpgradeable(address(proxyAdmin), _savingImplementation, data));
        _name = "savingAgEUR";
        _symbol = "SAGEUR";

        vm.startPrank(governor);
        token.mint(governor, 1e12);
        token.approve(address(_saving), 1e12);
        _saving.initialize(accessControlManager, IERC20MetadataUpgradeable(address(token)), _name, _symbol, BASE_6);
        vm.stopPrank();
        targetExposure = uint64((15 * 1e9) / 100);
        maxExposureYieldAsset = uint64((80 * 1e9) / 100);
        minExposureYieldAsset = uint64((5 * 1e9) / 100);
        rebalancer = new RebalancerFlashloanVault(accessControlManager, transmuter, IERC3156FlashLender(governor));
        harvester = new HarvesterVault(
            address(rebalancer),
            address(_saving),
            targetExposure,
            1,
            maxExposureYieldAsset,
            minExposureYieldAsset,
            1e8
        );
    }

    function test_RebalancerInitialization() public {
        assertEq(address(harvester.rebalancer()), address(rebalancer));
        assertEq(address(harvester.TRANSMUTER()), address(transmuter));
        assertEq(address(harvester.accessControlManager()), address(accessControlManager));
        (address vault, uint64 target, uint64 maxi, uint64 mini, uint64 overrideExp) = harvester.collateralData(collat);
        assertEq(vault, address(_saving));
        assertEq(target, targetExposure);
        assertEq(maxi, maxExposureYieldAsset);
        assertEq(mini, minExposureYieldAsset);
        assertEq(overrideExp, 1);
    }

    function test_Constructor_RevertWhen_InvalidParams() public {
        vm.expectRevert();
        new HarvesterVault(
            address(0),
            address(_saving),
            targetExposure,
            1,
            maxExposureYieldAsset,
            minExposureYieldAsset,
            1e8
        );

        vm.expectRevert();
        new HarvesterVault(
            address(rebalancer),
            address(0),
            targetExposure,
            1,
            maxExposureYieldAsset,
            minExposureYieldAsset,
            1e8
        );

        vm.expectRevert(Errors.InvalidParam.selector);
        harvester = new HarvesterVault(
            address(rebalancer),
            address(_saving),
            1e10,
            1,
            maxExposureYieldAsset,
            minExposureYieldAsset,
            1e8
        );

        vm.expectRevert(Errors.InvalidParam.selector);
        harvester = new HarvesterVault(
            address(rebalancer),
            address(_saving),
            1e10,
            0,
            maxExposureYieldAsset,
            minExposureYieldAsset,
            1e8
        );

        vm.expectRevert(Errors.InvalidParam.selector);
        harvester = new HarvesterVault(
            address(rebalancer),
            address(_saving),
            1e9 / 10,
            1,
            1e10,
            minExposureYieldAsset,
            1e8
        );

        vm.expectRevert(Errors.InvalidParam.selector);
        harvester = new HarvesterVault(address(rebalancer), address(_saving), 1e9 / 10, 1, 1e8, 2e8, 1e8);

        vm.expectRevert(Errors.InvalidParam.selector);
        harvester = new HarvesterVault(
            address(rebalancer),
            address(_saving),
            targetExposure,
            1,
            maxExposureYieldAsset,
            minExposureYieldAsset,
            1e10
        );
    }

    function test_OnlyGuardian_RevertWhen_NotGuardian() public {
        vm.expectRevert(Errors.NotGovernorOrGuardian.selector);
        harvester.setRebalancer(alice);

        vm.expectRevert(Errors.NotGovernorOrGuardian.selector);
        harvester.setCollateralData(address(_saving), targetExposure, 1, maxExposureYieldAsset, minExposureYieldAsset);

        vm.expectRevert(Errors.NotGovernorOrGuardian.selector);
        harvester.setMaxSlippage(1e9);

        harvester.updateLimitExposuresYieldAsset(collat);
    }

    function test_SettersHarvester() public {
        vm.startPrank(governor);
        vm.expectRevert(Errors.InvalidParam.selector);
        harvester.setMaxSlippage(1e10);

        harvester.setMaxSlippage(123456);
        assertEq(harvester.maxSlippage(), 123456);

        vm.expectRevert(Errors.ZeroAddress.selector);
        harvester.setRebalancer(address(0));

        harvester.setRebalancer(address(harvester));
        assertEq(address(harvester.rebalancer()), address(harvester));

        harvester.setCollateralData(
            address(_saving),
            targetExposure + 10,
            minExposureYieldAsset - 1,
            maxExposureYieldAsset + 1,
            1
        );
        (address vault, uint64 target, uint64 maxi, uint64 mini, uint64 overrideExp) = harvester.collateralData(collat);
        assertEq(vault, address(_saving));
        assertEq(target, targetExposure + 10);
        assertEq(maxi, maxExposureYieldAsset + 1);
        assertEq(mini, minExposureYieldAsset - 1);
        assertEq(overrideExp, 1);

        harvester.setCollateralData(
            address(_saving),
            targetExposure + 10,
            minExposureYieldAsset - 1,
            maxExposureYieldAsset + 1,
            0
        );
        (vault, target, maxi, mini, overrideExp) = harvester.collateralData(collat);
        assertEq(vault, address(_saving));
        assertEq(target, targetExposure + 10);
        assertEq(maxi, 1e9);
        assertEq(mini, 0);
        assertEq(overrideExp, 2);

        vm.stopPrank();
    }

    function test_UpdateLimitExposuresYieldAsset() public {
        bytes memory data;
        Savings newVault = Savings(_deployUpgradeable(address(proxyAdmin), _savingImplementation, data));
        _name = "savingAgEUR";
        _symbol = "SAGEUR";

        vm.startPrank(governor);
        MockTokenPermit(address(eurA)).mint(governor, 1e12);
        eurA.approve(address(newVault), 1e12);
        newVault.initialize(accessControlManager, IERC20MetadataUpgradeable(address(eurA)), _name, _symbol, BASE_6);
        transmuter.addCollateral(address(newVault));
        vm.stopPrank();

        uint64[] memory xFeeMint = new uint64[](3);
        int64[] memory yFeeMint = new int64[](3);

        xFeeMint[0] = 0;
        xFeeMint[1] = uint64((15 * BASE_9) / 100);
        xFeeMint[2] = uint64((2 * BASE_9) / 10);

        yFeeMint[0] = int64(1);
        yFeeMint[1] = int64(uint64(BASE_9 / 10));
        yFeeMint[2] = int64(uint64((2 * BASE_9) / 10));

        uint64[] memory xFeeBurn = new uint64[](3);
        int64[] memory yFeeBurn = new int64[](3);

        xFeeBurn[0] = uint64(BASE_9);
        xFeeBurn[1] = uint64(BASE_9 / 10);
        xFeeBurn[2] = 0;

        yFeeBurn[0] = int64(1);
        yFeeBurn[1] = int64(1);
        yFeeBurn[2] = int64(uint64(BASE_9 / 10));

        vm.startPrank(governor);
        transmuter.setFees(address(newVault), xFeeBurn, yFeeBurn, false);
        transmuter.setFees(address(newVault), xFeeMint, yFeeMint, true);
        harvester.setCollateralData(address(newVault), targetExposure, minExposureYieldAsset, maxExposureYieldAsset, 0);
        harvester.updateLimitExposuresYieldAsset(address(eurA));

        (, , uint64 maxi, uint64 mini, ) = harvester.collateralData(address(eurA));
        assertEq(maxi, (15 * BASE_9) / 100);
        assertEq(mini, BASE_9 / 10);
        vm.stopPrank();
    }
}
