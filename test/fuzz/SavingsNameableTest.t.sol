// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "../mock/MockTokenPermit.sol";
import "../Fixture.sol";
import "../utils/FunctionUtils.sol";
import "contracts/utils/Errors.sol" as Errors;
import "contracts/savings/nameable/SavingsNameable.sol";
import { UD60x18, ud, pow, powu, unwrap } from "prb/math/UD60x18.sol";

import { stdError } from "forge-std/Test.sol";

contract SavingsNameableTest is Fixture, FunctionUtils {
    using SafeERC20 for IERC20;

    uint256 internal constant _initDeposit = 1e12;
    SavingsNameable internal _saving;
    Savings internal _savingImplementation;
    string internal _name;
    string internal _symbol;

    function setUp() public override {
        super.setUp();

        _savingImplementation = new SavingsNameable();
        bytes memory data;
        _saving = SavingsNameable(_deployUpgradeable(address(proxyAdmin), address(_savingImplementation), data));
        _name = "Staked EURA";
        _symbol = "stEUR";

        vm.startPrank(governor);
        agToken.addMinter(address(_saving));
        deal(address(agToken), governor, _initDeposit);
        agToken.approve(address(_saving), _initDeposit);
        _saving.initialize(
            accessControlManager,
            IERC20MetadataUpgradeable(address(agToken)),
            _name,
            _symbol,
            BASE_18 / _initDeposit
        );
        _saving.setMaxRate(type(uint256).max);
        vm.stopPrank();
    }

    function test_Initialization() public {
        assertEq(address(_saving.accessControlManager()), address(accessControlManager));
        assertEq(_saving.asset(), address(agToken));
        assertEq(_saving.name(), _name);
        assertEq(_saving.symbol(), _symbol);
        assertEq(_saving.totalAssets(), _initDeposit);
        assertEq(_saving.totalSupply(), _initDeposit);
        assertEq(agToken.balanceOf(address(_saving)), _initDeposit);
        assertEq(_saving.balanceOf(address(governor)), 0);
        assertEq(_saving.balanceOf(address(_saving)), _initDeposit);
    }

    function test_Initialize() public {
        // To have the test written at least once somewhere
        assert(accessControlManager.isGovernor(governor));
        assert(accessControlManager.isGovernorOrGuardian(guardian));
        assert(accessControlManager.isGovernorOrGuardian(governor));
        bytes memory data;
        Savings savingsContract = Savings(
            _deployUpgradeable(address(proxyAdmin), address(_savingImplementation), data)
        );
        Savings savingsContract2 = Savings(
            _deployUpgradeable(address(proxyAdmin), address(_savingImplementation), data)
        );

        vm.startPrank(governor);
        agToken.addMinter(address(savingsContract));
        deal(address(agToken), governor, _initDeposit * 10);
        agToken.approve(address(savingsContract), _initDeposit);
        agToken.approve(address(savingsContract2), _initDeposit);

        savingsContract.initialize(
            accessControlManager,
            IERC20MetadataUpgradeable(address(agToken)),
            _name,
            _symbol,
            BASE_18 / _initDeposit
        );

        vm.expectRevert();
        savingsContract.initialize(
            accessControlManager,
            IERC20MetadataUpgradeable(address(agToken)),
            _name,
            _symbol,
            BASE_18 / _initDeposit
        );

        vm.expectRevert(Errors.ZeroAddress.selector);
        savingsContract2.initialize(
            IAccessControlManager(address(0)),
            IERC20MetadataUpgradeable(address(agToken)),
            _name,
            _symbol,
            BASE_18 / _initDeposit
        );

        vm.stopPrank();

        assertEq(address(savingsContract.accessControlManager()), address(accessControlManager));
        assertEq(savingsContract.asset(), address(agToken));
        assertEq(savingsContract.name(), _name);
        assertEq(savingsContract.symbol(), _symbol);
        assertEq(savingsContract.totalAssets(), _initDeposit);
        assertEq(savingsContract.totalSupply(), _initDeposit);
        assertEq(agToken.balanceOf(address(savingsContract)), _initDeposit);
        assertEq(savingsContract.balanceOf(address(governor)), 0);
        assertEq(savingsContract.balanceOf(address(savingsContract)), _initDeposit);
    }

    function test_SetNameAndSymbol() public {
        vm.expectRevert(Errors.NotGovernor.selector);
        _saving.setNameAndSymbol("EURA Test", "EURA");

        vm.startPrank(governor);
        _saving.setNameAndSymbol("EURA Test", "EURA");
        assertEq(_saving.name(), "EURA Test");
        assertEq(_saving.symbol(), "EURA");
        vm.stopPrank();
    }
}
