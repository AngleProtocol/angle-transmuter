// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";

import "forge-std/Test.sol";

import "contracts/utils/Errors.sol" as Errors;

import { IERC20Metadata } from "../mock/MockTokenPermit.sol";
import "../utils/FunctionUtils.sol";

import "contracts/savings/Savings.sol";
import "../mock/MockTokenPermit.sol";
import "contracts/helpers/GenericHarvester.sol";

import "contracts/transmuter/Storage.sol";
import "contracts/utils/Constants.sol";

import { IAccessControl } from "oz/access/IAccessControl.sol";

import { ContractType, CommonUtils, CHAIN_ETHEREUM } from "utils/src/CommonUtils.sol";

contract GenericHarvestertTest is Test, FunctionUtils, CommonUtils {
    using SafeERC20 for IERC20;

    GenericHarvester public harvester;
    uint64 public targetExposure;
    uint64 public maxExposureYieldAsset;
    uint64 public minExposureYieldAsset;
    address governor;
    IAgToken agToken;
    IERC3156FlashLender flashloan;
    ITransmuter transmuter;
    IAccessControlManager accessControlManager;

    address alice = vm.addr(1);

    function setUp() public {
        uint256 CHAIN_SOURCE = CHAIN_ETHEREUM;

        vm.createSelectFork("mainnet", 21_041_434);

        targetExposure = uint64((15 * 1e9) / 100);
        maxExposureYieldAsset = uint64((90 * 1e9) / 100);
        minExposureYieldAsset = uint64((5 * 1e9) / 100);

        flashloan = IERC3156FlashLender(_chainToContract(CHAIN_SOURCE, ContractType.FlashLoan));
        transmuter = ITransmuter(_chainToContract(CHAIN_SOURCE, ContractType.TransmuterAgUSD));
        agToken = IAgToken(_chainToContract(CHAIN_SOURCE, ContractType.AgUSD));
        accessControlManager = transmuter.accessControlManager();
        governor = _chainToContract(CHAIN_SOURCE, ContractType.GovernorMultisig);

        harvester = new GenericHarvester(
            1e8,
            ONEINCH_ROUTER,
            ONEINCH_ROUTER,
            100,
            agToken,
            transmuter,
            accessControlManager,
            flashloan
        );
        vm.startPrank(governor);
        harvester.toggleTrusted(alice);

        transmuter.toggleTrusted(address(harvester), TrustedType.Seller);
        vm.stopPrank();

        vm.label(STEAK_USDC, "STEAK_USDC");
        vm.label(USDC, "USDC");
        vm.label(address(harvester), "Harvester");
    }

    function test_Initialization() public {
        assertEq(harvester.maxSlippage(), 1e8);
        assertEq(address(harvester.accessControlManager()), address(accessControlManager));
        assertEq(address(harvester.agToken()), address(agToken));
        assertEq(address(harvester.transmuter()), address(transmuter));
        assertEq(address(harvester.flashloan()), address(flashloan));
        assertEq(harvester.maxSwapSlippage(), 100);
        assertEq(harvester.tokenTransferAddress(), ONEINCH_ROUTER);
        assertEq(harvester.swapRouter(), ONEINCH_ROUTER);
    }

    function test_Setters() public {
        vm.expectRevert(Errors.NotGovernorOrGuardian.selector);
        harvester.setTokenTransferAddress(alice);

        vm.startPrank(governor);
        harvester.setTokenTransferAddress(alice);
        assertEq(harvester.tokenTransferAddress(), alice);
        vm.stopPrank();

        vm.expectRevert(Errors.NotGovernorOrGuardian.selector);
        harvester.setSwapRouter(alice);

        vm.startPrank(governor);
        harvester.setSwapRouter(alice);
        assertEq(harvester.swapRouter(), alice);
        vm.stopPrank();

        vm.expectRevert(Errors.NotGovernorOrGuardian.selector);
        harvester.setMaxSlippage(1e9);

        vm.startPrank(governor);
        harvester.setMaxSlippage(1e9);
        assertEq(harvester.maxSlippage(), 1e9);
        vm.stopPrank();
    }

    function test_AddBudget(uint256 amount, address receiver) public {
        vm.assume(receiver != address(0));
        amount = bound(amount, 1e18, 1e21);

        deal(address(agToken), alice, amount);
        vm.startPrank(alice);
        agToken.approve(address(harvester), type(uint256).max);
        harvester.addBudget(amount, receiver);
        vm.stopPrank();

        assertEq(harvester.budget(receiver), amount);
        assertEq(agToken.balanceOf(address(harvester)), amount);
    }

    function test_RemoveBudget(uint256 amount) public {
        amount = bound(amount, 1e18, 1e21);

        deal(address(agToken), alice, amount);
        vm.startPrank(alice);
        agToken.approve(address(harvester), type(uint256).max);
        harvester.addBudget(amount, alice);
        vm.stopPrank();

        assertEq(harvester.budget(alice), amount);
        assertEq(agToken.balanceOf(address(harvester)), amount);

        vm.startPrank(alice);
        harvester.removeBudget(amount, alice);
        vm.stopPrank();

        assertEq(harvester.budget(alice), 0);
        assertEq(agToken.balanceOf(address(harvester)), 0);
        assertEq(agToken.balanceOf(alice), amount);
    }

    function test_Harvest_ZeroAmount() public {
        vm.expectRevert(Errors.ZeroAmount.selector);
        harvester.harvest(STEAK_USDC, 1e9, abi.encode(uint8(SwapType.VAULT), new bytes(0)));
    }

    function test_Harvest_NotEnoughBudget() public {
        _setYieldBearingData(STEAK_USDC, USDC);

        vm.expectRevert(stdError.arithmeticError);
        harvester.harvest(STEAK_USDC, 1e3, abi.encode(uint8(SwapType.VAULT), new bytes(0)));
    }

    function test_Harvest_DecreaseExposureSTEAK_USDC() public {}

    function test_Harvest_IncreaseExposureSTEAK_USDC() public {}

    function _loadReserve(address token, uint256 amount) internal {
        if (token == USDM) {
            vm.prank(0x48AEB395FB0E4ff8433e9f2fa6E0579838d33B62);
            IAgToken(USDM).mint(alice, amount);
        } else {
            deal(token, alice, amount);
        }

        vm.startPrank(alice);
        IERC20(token).approve(address(transmuter), type(uint256).max);
        transmuter.swapExactInput(amount, 0, token, address(agToken), alice, block.timestamp + 1);
        vm.stopPrank();
    }

    function _setYieldBearingData(address yieldBearingAsset, address stablecoin) internal {
        vm.prank(governor);
        harvester.setYieldBearingAssetData(
            yieldBearingAsset,
            stablecoin,
            targetExposure,
            minExposureYieldAsset,
            maxExposureYieldAsset,
            1
        );
    }

    function _setYieldBearingData(
        address yieldBearingAsset,
        address stablecoin,
        uint64 minExposure,
        uint64 maxExposure
    ) internal {
        vm.prank(governor);
        harvester.setYieldBearingAssetData(yieldBearingAsset, stablecoin, targetExposure, minExposure, maxExposure, 1);
    }
}
