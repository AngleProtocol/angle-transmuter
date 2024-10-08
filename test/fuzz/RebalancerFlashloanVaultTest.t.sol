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

contract RebalancerFlashloanVaultTest is Fixture, FunctionUtils {
    using SafeERC20 for IERC20;

    RebalancerFlashloanVault public rebalancer;
    Savings internal _saving;
    string internal _name;
    string internal _symbol;
    address public collat;

    function setUp() public override {
        super.setUp();

        MockTokenPermit token = new MockTokenPermit("EURC", "EURC", 6);
        collat = address(token);

        address _savingImplementation = address(new Savings());
        bytes memory data;
        _saving = Savings(_deployUpgradeable(address(proxyAdmin), address(_savingImplementation), data));
        _name = "savingAgEUR";
        _symbol = "SAGEUR";

        vm.startPrank(governor);
        token.mint(governor, 1e12);
        token.approve(address(_saving), 1e12);
        _saving.initialize(accessControlManager, IERC20MetadataUpgradeable(address(token)), _name, _symbol, BASE_6);
        vm.stopPrank();

        rebalancer = new RebalancerFlashloanVault(accessControlManager, transmuter, IERC3156FlashLender(governor));
    }

    function test_RebalancerInitialization() public {
        assertEq(address(rebalancer.accessControlManager()), address(accessControlManager));
        assertEq(address(rebalancer.AGTOKEN()), address(agToken));
        assertEq(address(rebalancer.TRANSMUTER()), address(transmuter));
        assertEq(address(rebalancer.FLASHLOAN()), governor);
        assertEq(IERC20Metadata(address(agToken)).allowance(address(rebalancer), address(governor)), type(uint256).max);
        assertEq(IERC20Metadata(address(collat)).allowance(address(rebalancer), address(_saving)), 0);
    }

    function test_Constructor_RevertWhen_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new RebalancerFlashloanVault(accessControlManager, transmuter, IERC3156FlashLender(address(0)));
    }

    function test_adjustYieldExposure_RevertWhen_NotTrusted() public {
        vm.expectRevert(Errors.NotTrusted.selector);
        rebalancer.adjustYieldExposure(1, 1, address(0), address(0), 0, new bytes(0));
    }

    function test_onFlashLoan_RevertWhen_NotTrusted() public {
        vm.expectRevert(Errors.NotTrusted.selector);
        rebalancer.onFlashLoan(address(rebalancer), address(0), 1, 0, abi.encode(1));

        vm.expectRevert(Errors.NotTrusted.selector);
        rebalancer.onFlashLoan(address(rebalancer), address(0), 1, 1, abi.encode(1));

        vm.expectRevert(Errors.NotTrusted.selector);
        vm.startPrank(governor);
        rebalancer.onFlashLoan(address(0), address(0), 1, 0, abi.encode(1));
        vm.stopPrank();

        vm.expectRevert(Errors.NotTrusted.selector);
        vm.startPrank(governor);
        rebalancer.onFlashLoan(address(rebalancer), address(0), 1, 1, abi.encode(1));
        vm.stopPrank();

        vm.expectRevert();
        vm.startPrank(governor);
        rebalancer.onFlashLoan(address(rebalancer), address(0), 1, 0, abi.encode(1, 2));
        vm.stopPrank();
    }
}
