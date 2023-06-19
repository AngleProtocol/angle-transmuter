// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import { stdError } from "forge-std/Test.sol";

import "mock/MockManager.sol";

import "contracts/transmuter/Storage.sol";
import { Test } from "contracts/transmuter/configs/Test.sol";
import { DiamondCut } from "contracts/transmuter/facets/DiamondCut.sol";
import { LibSetters } from "contracts/transmuter/libraries/LibSetters.sol";
import "contracts/utils/Constants.sol";
import "contracts/utils/Errors.sol" as Errors;

import { Fixture } from "../Fixture.sol";

contract Test_Setters_TogglePause is Fixture {
    function test_RevertWhen_NonGovernorOrGuardian() public {
        vm.expectRevert(Errors.NotGovernorOrGuardian.selector);
        transmuter.togglePause(address(eurA), ActionType.Mint);

        vm.expectRevert(Errors.NotGovernorOrGuardian.selector);
        hoax(alice);
        transmuter.togglePause(address(eurA), ActionType.Mint);

        vm.expectRevert(Errors.NotGovernorOrGuardian.selector);
        hoax(bob);
        transmuter.togglePause(address(eurA), ActionType.Mint);
    }

    function test_RevertWhen_NotCollateral() public {
        vm.expectRevert(Errors.NotCollateral.selector);

        hoax(guardian);
        transmuter.togglePause(address(agToken), ActionType.Mint);
    }

    function test_PauseMint() public {
        vm.expectEmit(address(transmuter));
        emit LibSetters.PauseToggled(address(eurA), uint256(ActionType.Mint), true);

        hoax(guardian);
        transmuter.togglePause(address(eurA), ActionType.Mint);

        assert(transmuter.isPaused(address(eurA), ActionType.Mint));

        vm.expectRevert(Errors.Paused.selector);
        transmuter.swapExactInput(1 ether, 1 ether, address(eurA), address(agToken), alice, block.timestamp + 10);

        vm.expectRevert(Errors.Paused.selector);
        transmuter.swapExactOutput(1 ether, 1 ether, address(eurA), address(agToken), alice, block.timestamp + 10);
    }

    function test_PauseBurn() public {
        vm.expectEmit(address(transmuter));
        emit LibSetters.PauseToggled(address(eurA), uint256(ActionType.Burn), true);

        hoax(guardian);
        transmuter.togglePause(address(eurA), ActionType.Burn);

        assert(transmuter.isPaused(address(eurA), ActionType.Burn));

        vm.expectRevert(Errors.Paused.selector);
        transmuter.swapExactInput(1 ether, 1 ether, address(agToken), address(eurA), alice, block.timestamp + 10);

        vm.expectRevert(Errors.Paused.selector);
        transmuter.swapExactOutput(1 ether, 1 ether, address(agToken), address(eurA), alice, block.timestamp + 10);
    }

    function test_PauseRedeem() public {
        vm.expectEmit(address(transmuter));
        emit LibSetters.PauseToggled(address(eurA), uint256(ActionType.Redeem), true);

        hoax(guardian);
        transmuter.togglePause(address(eurA), ActionType.Redeem);

        assert(transmuter.isPaused(address(eurA), ActionType.Redeem));

        vm.expectRevert(Errors.Paused.selector);
        transmuter.redeem(1 ether, alice, block.timestamp + 10, new uint256[](3));

        vm.expectRevert(Errors.Paused.selector);
        transmuter.redeemWithForfeit(1 ether, alice, block.timestamp + 10, new uint256[](3), new address[](0));
    }
}

contract Test_Setters_SetFees is Fixture {
    function test_RevertWhen_NonGovernorOrGuardian() public {
        uint64[] memory xFee = new uint64[](3);
        int64[] memory yFee = new int64[](3);

        vm.expectRevert(Errors.NotGovernorOrGuardian.selector);
        transmuter.setFees(address(eurA), xFee, yFee, true);

        vm.expectRevert(Errors.NotGovernorOrGuardian.selector);
        hoax(alice);
        transmuter.setFees(address(eurA), xFee, yFee, true);

        vm.expectRevert(Errors.NotGovernorOrGuardian.selector);
        hoax(bob);
        transmuter.setFees(address(eurA), xFee, yFee, true);
    }

    function test_RevertWhen_NotCollateral() public {
        uint64[] memory xFee = new uint64[](3);
        int64[] memory yFee = new int64[](3);

        vm.expectRevert(Errors.NotCollateral.selector);
        hoax(guardian);
        transmuter.setFees(address(agToken), xFee, yFee, true);
    }

    function test_RevertWhen_InvalidParamsLength0() public {
        uint64[] memory xFee = new uint64[](0);
        int64[] memory yFee = new int64[](0);

        vm.expectRevert(Errors.InvalidParams.selector);
        hoax(guardian);
        transmuter.setFees(address(eurA), xFee, yFee, true);
    }

    function test_RevertWhen_InvalidParamsDifferentLength() public {
        uint64[] memory xFee = new uint64[](3);
        int64[] memory yFee = new int64[](4);

        vm.expectRevert(Errors.InvalidParams.selector);
        hoax(guardian);
        transmuter.setFees(address(eurA), xFee, yFee, true);
    }

    function test_RevertWhen_InvalidParamsMint() public {
        uint64[] memory xFee = new uint64[](4);
        int64[] memory yFee = new int64[](4);

        xFee[3] = uint64(BASE_9); // xFee[n - 1] >= BASE_9

        vm.expectRevert(Errors.InvalidParams.selector);
        hoax(guardian);
        transmuter.setFees(address(eurA), xFee, yFee, true);

        xFee[3] = uint64(BASE_9 - 1);
        xFee[0] = uint64(1); // xFee[0] != 0

        vm.expectRevert(Errors.InvalidParams.selector);
        hoax(guardian);
        transmuter.setFees(address(eurA), xFee, yFee, true);

        xFee[0] = 0;
        yFee[3] = int64(int256(BASE_12 + 1)); // yFee[n - 1] > BASE_12

        vm.expectRevert(Errors.InvalidParams.selector);
        hoax(guardian);
        transmuter.setFees(address(eurA), xFee, yFee, true);
    }

    function test_RevertWhen_InvalidParamsMintIncreases() public {
        uint64[] memory xFee = new uint64[](3);
        int64[] memory yFee = new int64[](3);

        xFee[0] = 0;
        xFee[1] = uint64((2 * BASE_9) / 10); // Not strictly increasing
        xFee[2] = uint64((2 * BASE_9) / 10);

        yFee[0] = int64(0);
        yFee[1] = int64(uint64(BASE_9 / 10));
        yFee[2] = int64(uint64((2 * BASE_9) / 10));

        vm.expectRevert(Errors.InvalidParams.selector);
        hoax(guardian);
        transmuter.setFees(address(eurA), xFee, yFee, true);

        xFee[0] = 0;
        xFee[1] = uint64(BASE_9 / 10);
        xFee[2] = uint64((2 * BASE_9) / 10);

        yFee[0] = int64(0);
        yFee[1] = int64(uint64((3 * BASE_9) / 10)); // Not increasing
        yFee[2] = int64(uint64((2 * BASE_9) / 10));

        vm.expectRevert(Errors.InvalidParams.selector);
        hoax(guardian);
        transmuter.setFees(address(eurA), xFee, yFee, true);
    }

    function test_RevertWhen_InvalidNegativeFeesMint() public {
        uint64[] memory xFee = new uint64[](3);
        int64[] memory yFee = new int64[](3);

        xFee[2] = 0;
        xFee[1] = uint64(BASE_9 / 10);
        xFee[0] = uint64(BASE_9);

        yFee[0] = int64(1);
        yFee[1] = int64(1);
        yFee[2] = int64(uint64(BASE_9 / 10));

        hoax(guardian);
        transmuter.setFees(address(eurB), xFee, yFee, false);

        xFee[0] = 0;
        xFee[1] = uint64(BASE_9 / 10);
        xFee[2] = uint64((2 * BASE_9) / 10);

        yFee[0] = int64(-2); // Negative Fees lower than the burn fees
        yFee[1] = int64(uint64(BASE_9 / 10));
        yFee[2] = int64(uint64((2 * BASE_9) / 10));

        vm.expectRevert(Errors.InvalidNegativeFees.selector);
        hoax(guardian);
        transmuter.setFees(address(eurA), xFee, yFee, true);
    }

    function test_RevertWhen_InvalidParamsBurn() public {
        uint64[] memory xFee = new uint64[](3);
        int64[] memory yFee = new int64[](3);

        xFee[0] = uint64(0); // xFee[0] != BASE_9
        xFee[1] = uint64(BASE_9 / 10);
        xFee[2] = 0;

        yFee[0] = int64(1);
        yFee[1] = int64(1);
        yFee[2] = int64(uint64(BASE_9 / 10));

        vm.expectRevert(Errors.InvalidParams.selector);
        hoax(guardian);
        transmuter.setFees(address(eurA), xFee, yFee, false);

        xFee[0] = uint64(BASE_9);
        xFee[1] = uint64(BASE_9 / 10);
        xFee[2] = 0;

        yFee[0] = int64(1);
        yFee[1] = int64(1);
        yFee[2] = int64(uint64(BASE_9 + 1)); // yFee[n - 1] > int256(BASE_9)

        vm.expectRevert(Errors.InvalidParams.selector);
        hoax(guardian);
        transmuter.setFees(address(eurA), xFee, yFee, false);

        xFee[0] = uint64(BASE_9);
        xFee[1] = uint64(BASE_9 / 10);
        xFee[2] = 0;

        yFee[0] = int64(1);
        yFee[1] = int64(2); // yFee[1] != yFee[0]
        yFee[2] = int64(uint64(BASE_9 / 10));

        vm.expectRevert(Errors.InvalidParams.selector);
        hoax(guardian);
        transmuter.setFees(address(eurA), xFee, yFee, false);
    }

    function test_RevertWhen_InvalidParamsBurnIncreases() public {
        uint64[] memory xFee = new uint64[](3);
        int64[] memory yFee = new int64[](3);

        xFee[0] = uint64(BASE_9);
        xFee[1] = uint64(BASE_9); // Not strictly decreasing
        xFee[2] = 0;

        yFee[0] = int64(1);
        yFee[1] = int64(1);
        yFee[2] = int64(uint64(BASE_9 / 10));

        vm.expectRevert(Errors.InvalidParams.selector);
        hoax(guardian);
        transmuter.setFees(address(eurA), xFee, yFee, false);

        xFee[0] = uint64(BASE_9);
        xFee[1] = uint64(BASE_9 / 10);
        xFee[2] = 0;

        yFee[0] = int64(2);
        yFee[1] = int64(2);
        yFee[2] = int64(1); // Not increasing

        vm.expectRevert(Errors.InvalidParams.selector);
        hoax(guardian);
        transmuter.setFees(address(eurA), xFee, yFee, false);
    }

    function test_RevertWhen_InvalidNegativeFeesBurn() public {
        uint64[] memory xFee = new uint64[](3);
        int64[] memory yFee = new int64[](3);

        xFee[0] = 0;
        xFee[1] = uint64(BASE_9 / 10);
        xFee[2] = uint64((2 * BASE_9) / 10);

        yFee[0] = int64(1);
        yFee[1] = int64(uint64(BASE_9 / 10));
        yFee[2] = int64(uint64((2 * BASE_9) / 10));

        hoax(guardian);
        transmuter.setFees(address(eurB), xFee, yFee, true);

        xFee[0] = uint64(BASE_9);
        xFee[1] = uint64(BASE_9 / 10);
        xFee[2] = 0;

        yFee[0] = int64(-2);
        yFee[1] = int64(-2);
        yFee[2] = int64(2);

        vm.expectRevert(Errors.InvalidNegativeFees.selector);
        hoax(guardian);
        transmuter.setFees(address(eurA), xFee, yFee, false);
    }

    function test_Mint() public {
        uint64[] memory xFee = new uint64[](3);
        int64[] memory yFee = new int64[](3);

        xFee[0] = 0;
        xFee[1] = uint64(BASE_9 / 10);
        xFee[2] = uint64((2 * BASE_9) / 10);

        yFee[0] = int64(1);
        yFee[1] = int64(uint64(BASE_9 / 10));
        yFee[2] = int64(uint64((2 * BASE_9) / 10));

        vm.expectEmit(address(transmuter));
        emit LibSetters.FeesSet(address(eurA), xFee, yFee, true);

        hoax(guardian);
        transmuter.setFees(address(eurA), xFee, yFee, true);

        (uint64[] memory xFeeMint, int64[] memory yFeeMint) = transmuter.getCollateralMintFees(address(eurA));
        for (uint256 i = 0; i < 3; ++i) {
            assertEq(xFeeMint[i], xFee[i]);
            assertEq(yFeeMint[i], yFee[i]);
        }
    }

    function test_Burn() public {
        uint64[] memory xFee = new uint64[](3);
        int64[] memory yFee = new int64[](3);

        xFee[0] = uint64(BASE_9);
        xFee[1] = uint64(BASE_9 / 10);
        xFee[2] = 0;

        yFee[0] = int64(1);
        yFee[1] = int64(1);
        yFee[2] = int64(uint64(BASE_9 / 10));

        vm.expectEmit(address(transmuter));
        emit LibSetters.FeesSet(address(eurA), xFee, yFee, false);

        hoax(guardian);
        transmuter.setFees(address(eurA), xFee, yFee, false);

        (uint64[] memory xFeeBurn, int64[] memory yFeeBurn) = transmuter.getCollateralBurnFees(address(eurA));
        for (uint256 i = 0; i < 3; ++i) {
            assertEq(xFeeBurn[i], xFee[i]);
            assertEq(yFeeBurn[i], yFee[i]);
        }
    }
}

contract Test_Setters_SetRedemptionCurveParams is Fixture {
    event RedemptionCurveParamsSet(uint64[] xFee, int64[] yFee);

    function test_RevertWhen_NonGovernorOrGuardian() public {
        uint64[] memory xFee = new uint64[](3);
        int64[] memory yFee = new int64[](3);

        vm.expectRevert(Errors.NotGovernorOrGuardian.selector);
        transmuter.setRedemptionCurveParams(xFee, yFee);

        vm.expectRevert(Errors.NotGovernorOrGuardian.selector);
        hoax(alice);
        transmuter.setRedemptionCurveParams(xFee, yFee);

        vm.expectRevert(Errors.NotGovernorOrGuardian.selector);
        hoax(bob);
        transmuter.setRedemptionCurveParams(xFee, yFee);
    }

    function test_RevertWhen_InvalidParams() public {
        uint64[] memory xFee = new uint64[](3);
        int64[] memory yFee = new int64[](3);

        xFee[0] = uint64(0);
        xFee[1] = uint64(BASE_9 / 10);
        xFee[2] = uint64(BASE_9 + 1);

        yFee[0] = int64(1);
        yFee[1] = int64(2);
        yFee[2] = int64(uint64(BASE_9 / 10));

        vm.expectRevert(Errors.InvalidParams.selector);
        hoax(guardian);
        transmuter.setRedemptionCurveParams(xFee, yFee);
    }

    function test_RevertWhen_InvalidParamsWhenDecreases() public {
        uint64[] memory xFee = new uint64[](3);
        int64[] memory yFee = new int64[](3);

        xFee[0] = uint64(0);
        xFee[1] = uint64(0); // Not stricly increasing
        xFee[2] = uint64(BASE_9);

        yFee[0] = int64(1);
        yFee[1] = int64(1);
        yFee[2] = int64(uint64(BASE_9 / 10));

        vm.expectRevert(Errors.InvalidParams.selector);
        hoax(guardian);
        transmuter.setRedemptionCurveParams(xFee, yFee);

        xFee[0] = uint64(0);
        xFee[1] = uint64(1);
        xFee[2] = uint64(BASE_9);

        yFee[0] = int64(2);
        yFee[1] = int64(2);
        yFee[2] = int64(uint64(BASE_9 + 1)); // Not in bounds

        vm.expectRevert(Errors.InvalidParams.selector);
        hoax(guardian);
        transmuter.setRedemptionCurveParams(xFee, yFee);

        xFee[0] = uint64(0);
        xFee[1] = uint64(1);
        xFee[2] = uint64(BASE_9);

        yFee[0] = int64(2);
        yFee[1] = int64(2);
        yFee[2] = int64(-1); // Not in bounds

        vm.expectRevert(Errors.InvalidParams.selector);
        hoax(guardian);
        transmuter.setRedemptionCurveParams(xFee, yFee);
    }

    function test_Success() public {
        uint64[] memory xFee = new uint64[](3);
        int64[] memory yFee = new int64[](3);

        xFee[0] = uint64(0);
        xFee[1] = uint64(1);
        xFee[2] = uint64(BASE_9);

        yFee[0] = int64(1);
        yFee[1] = int64(2);
        yFee[2] = int64(3);

        vm.expectEmit(address(transmuter));
        emit RedemptionCurveParamsSet(xFee, yFee);

        hoax(guardian);
        transmuter.setRedemptionCurveParams(xFee, yFee);

        (uint64[] memory xRedemptionCurve, int64[] memory yRedemptionCurve) = transmuter.getRedemptionFees();
        for (uint256 i = 0; i < 3; ++i) {
            assertEq(xRedemptionCurve[i], xFee[i]);
            assertEq(yRedemptionCurve[i], yFee[i]);
        }
    }
}

contract Test_Setters_RecoverERC20 is Fixture {
    event Transfer(address from, address to, uint256 value);

    function test_RevertWhen_NonGovernor() public {
        vm.expectRevert(Errors.NotGovernor.selector);
        transmuter.recoverERC20(address(agToken), agToken, alice, 1 ether);

        vm.expectRevert(Errors.NotGovernor.selector);
        hoax(alice);
        transmuter.recoverERC20(address(agToken), agToken, alice, 1 ether);

        vm.expectRevert(Errors.NotGovernor.selector);
        hoax(guardian);
        transmuter.recoverERC20(address(agToken), agToken, alice, 1 ether);
    }

    function test_Success() public {
        deal(address(eurA), address(transmuter), 1 ether);

        hoax(governor);
        transmuter.recoverERC20(address(eurA), eurA, alice, 1 ether);

        assertEq(eurA.balanceOf(alice), 1 ether);
    }

    function test_SuccessWithManager() public {
        MockManager manager = new MockManager(address(eurA));
        IERC20[] memory subCollaterals = new IERC20[](2);
        subCollaterals[0] = eurA;
        subCollaterals[1] = eurB;
        ManagerStorage memory data = ManagerStorage({
            subCollaterals: subCollaterals,
            config: abi.encode(ManagerType.EXTERNAL, abi.encode(manager))
        });
        manager.setSubCollaterals(data.subCollaterals, data.config);

        hoax(governor);
        transmuter.setCollateralManager(address(eurA), data);

        deal(address(eurA), address(manager), 1 ether);

        hoax(governor);
        transmuter.recoverERC20(address(eurA), eurA, alice, 1 ether);

        assertEq(eurA.balanceOf(alice), 1 ether);

        deal(address(eurB), address(manager), 1 ether);

        hoax(governor);
        transmuter.recoverERC20(address(eurA), eurB, alice, 1 ether);

        assertEq(eurB.balanceOf(alice), 1 ether);
    }
}

contract Test_Setters_SetAccessControlManager is Fixture {
    function test_RevertWhen_NonGovernor() public {
        vm.expectRevert(Errors.NotGovernor.selector);
        transmuter.setAccessControlManager(alice);

        vm.expectRevert(Errors.NotGovernor.selector);
        hoax(alice);
        transmuter.setAccessControlManager(alice);

        vm.expectRevert(Errors.NotGovernor.selector);
        hoax(guardian);
        transmuter.setAccessControlManager(alice);
    }

    function test_Success() public {
        address oldAccessControlManager = address(transmuter.accessControlManager());

        vm.expectEmit(address(transmuter));
        emit LibSetters.OwnershipTransferred(oldAccessControlManager, alice);

        hoax(governor);
        transmuter.setAccessControlManager(alice);

        assertEq(address(transmuter.accessControlManager()), alice);
    }
}

contract Test_Setters_ToggleTrusted is Fixture {
    event TrustedToggled(address indexed sender, bool isTrusted, TrustedType trustedType);

    function test_RevertWhen_NonGovernor() public {
        vm.expectRevert(Errors.NotGovernor.selector);
        transmuter.toggleTrusted(alice, TrustedType.Seller);

        vm.expectRevert(Errors.NotGovernor.selector);
        hoax(alice);
        transmuter.toggleTrusted(alice, TrustedType.Seller);

        vm.expectRevert(Errors.NotGovernor.selector);
        hoax(guardian);
        transmuter.toggleTrusted(alice, TrustedType.Seller);
    }

    function test_Seller() public {
        vm.expectEmit(address(transmuter));
        emit TrustedToggled(alice, true, TrustedType.Seller);

        hoax(governor);
        transmuter.toggleTrusted(alice, TrustedType.Seller);

        assert(transmuter.isTrustedSeller(alice));

        vm.expectEmit(address(transmuter));
        emit TrustedToggled(alice, false, TrustedType.Seller);

        hoax(governor);
        transmuter.toggleTrusted(alice, TrustedType.Seller);

        assert(!transmuter.isTrustedSeller(alice));
    }

    function test_Updater() public {
        vm.expectEmit(address(transmuter));
        emit TrustedToggled(alice, true, TrustedType.Updater);

        hoax(governor);
        transmuter.toggleTrusted(alice, TrustedType.Updater);

        assert(transmuter.isTrusted(alice));

        vm.expectEmit(address(transmuter));
        emit TrustedToggled(alice, false, TrustedType.Updater);

        hoax(governor);
        transmuter.toggleTrusted(alice, TrustedType.Updater);

        assert(!transmuter.isTrusted(alice));
    }
}

contract Test_Setters_SetWhitelistStatus is Fixture {
    function test_RevertWhen_NonGovernor() public {
        bytes memory whitelistData = abi.encode(WhitelistType.BACKED, abi.encode(address(transmuter)));
        vm.expectRevert(Errors.NotGovernor.selector);
        transmuter.setWhitelistStatus(address(eurA), 1, whitelistData);

        vm.expectRevert(Errors.NotGovernor.selector);
        hoax(alice);
        transmuter.setWhitelistStatus(address(eurA), 1, whitelistData);

        vm.expectRevert(Errors.NotGovernor.selector);
        hoax(guardian);
        transmuter.setWhitelistStatus(address(eurA), 1, whitelistData);
    }

    function test_RevertWhen_NotCollateral() public {
        bytes memory whitelistData = abi.encode(WhitelistType.BACKED, abi.encode(address(transmuter)));
        vm.expectRevert(Errors.NotCollateral.selector);
        hoax(governor);
        transmuter.setWhitelistStatus(address(this), 1, whitelistData);
    }

    function test_RevertWhen_InvalidWhitelistData() public {
        bytes memory whitelistData = abi.encode(3, 4);
        vm.expectRevert();
        hoax(governor);
        transmuter.setWhitelistStatus(address(this), 1, whitelistData);
    }

    function test_SetPositiveStatus() public {
        bytes memory whitelistData = abi.encode(WhitelistType.BACKED, abi.encode(address(transmuter)));
        bytes memory emptyData;
        assert(!transmuter.isWhitelistedCollateral(address(eurA)));
        assertEq(transmuter.getCollateralWhitelistData(address(eurA)), emptyData);

        vm.expectEmit(address(transmuter));
        emit LibSetters.CollateralWhitelistStatusUpdated(address(eurA), whitelistData, 1);

        hoax(governor);
        transmuter.setWhitelistStatus(address(eurA), 1, whitelistData);

        assert(transmuter.isWhitelistedCollateral(address(eurA)));
        assertEq(transmuter.getCollateralWhitelistData(address(eurA)), whitelistData);
    }

    function test_SetNegativeStatus() public {
        bytes memory whitelistData = abi.encode(WhitelistType.BACKED, abi.encode(address(transmuter)));
        bytes memory emptyData;
        assert(!transmuter.isWhitelistedCollateral(address(eurA)));
        assertEq(transmuter.getCollateralWhitelistData(address(eurA)), emptyData);

        vm.expectEmit(address(transmuter));
        emit LibSetters.CollateralWhitelistStatusUpdated(address(eurA), whitelistData, 1);

        hoax(governor);
        transmuter.setWhitelistStatus(address(eurA), 1, whitelistData);

        assert(transmuter.isWhitelistedCollateral(address(eurA)));
        assertEq(transmuter.getCollateralWhitelistData(address(eurA)), whitelistData);

        bytes memory whitelistData2 = abi.encode(WhitelistType.BACKED, abi.encode(address(alice)));
        vm.expectEmit(address(transmuter));
        emit LibSetters.CollateralWhitelistStatusUpdated(address(eurA), whitelistData2, 0);

        hoax(governor);
        transmuter.setWhitelistStatus(address(eurA), 0, whitelistData2);

        assert(!transmuter.isWhitelistedCollateral(address(eurA)));
        assertEq(transmuter.getCollateralWhitelistData(address(eurA)), whitelistData);
    }
}

contract Test_Setters_ToggleWhitelist is Fixture {
    event WhitelistStatusToggled(WhitelistType whitelistType, address indexed who, uint256 whitelistStatus);

    function test_RevertWhen_NonGuardian() public {
        vm.expectRevert(Errors.NotGovernorOrGuardian.selector);
        transmuter.toggleWhitelist(WhitelistType.BACKED, address(alice));

        vm.expectRevert(Errors.NotGovernorOrGuardian.selector);
        hoax(alice);
        transmuter.toggleWhitelist(WhitelistType.BACKED, address(alice));
    }

    function test_WhitelistSet() public {
        vm.expectEmit(address(transmuter));
        emit WhitelistStatusToggled(WhitelistType.BACKED, address(alice), 1);
        hoax(guardian);
        transmuter.toggleWhitelist(WhitelistType.BACKED, address(alice));

        assert(transmuter.isWhitelistedForType(WhitelistType.BACKED, address(alice)));
    }

    function test_WhitelistUnset() public {
        vm.expectEmit(address(transmuter));
        emit WhitelistStatusToggled(WhitelistType.BACKED, address(alice), 1);
        hoax(guardian);
        transmuter.toggleWhitelist(WhitelistType.BACKED, address(alice));

        assert(transmuter.isWhitelistedForType(WhitelistType.BACKED, address(alice)));

        vm.expectEmit(address(transmuter));
        emit WhitelistStatusToggled(WhitelistType.BACKED, address(alice), 0);
        hoax(guardian);
        transmuter.toggleWhitelist(WhitelistType.BACKED, address(alice));

        assert(!transmuter.isWhitelistedForType(WhitelistType.BACKED, address(alice)));
    }

    function test_WhitelistSetOnCollateral() public {
        assert(transmuter.isWhitelistedForCollateral(address(eurA), address(alice)));
        vm.expectEmit(address(transmuter));
        emit WhitelistStatusToggled(WhitelistType.BACKED, address(alice), 1);
        hoax(guardian);
        transmuter.toggleWhitelist(WhitelistType.BACKED, address(alice));

        assert(transmuter.isWhitelistedForType(WhitelistType.BACKED, address(alice)));
        assert(transmuter.isWhitelistedForCollateral(address(eurA), address(alice)));

        bytes memory whitelistData = abi.encode(WhitelistType.BACKED, abi.encode(address(transmuter)));
        hoax(governor);
        transmuter.setWhitelistStatus(address(eurA), 1, whitelistData);

        assert(transmuter.isWhitelistedForCollateral(address(eurA), address(alice)));

        hoax(guardian);
        transmuter.toggleWhitelist(WhitelistType.BACKED, address(alice));
        assert(!transmuter.isWhitelistedForCollateral(address(eurA), address(alice)));
    }
}

contract Test_Setters_UpdateNormalizer is Fixture {
    event NormalizerUpdated(uint256 newNormalizerValue);

    function test_RevertWhen_NotTrusted() public {
        vm.expectRevert(Errors.NotTrusted.selector);
        transmuter.updateNormalizer(1 ether, true);

        vm.expectRevert(Errors.NotTrusted.selector);
        hoax(alice);
        transmuter.updateNormalizer(1 ether, true);

        vm.expectRevert(Errors.NotTrusted.selector);
        hoax(guardian);
        transmuter.updateNormalizer(1 ether, true);
    }

    function test_RevertWhen_ZeroAmountNormalizedStables() public {
        vm.expectRevert(); // Should be a division by 0
        hoax(governor);
        transmuter.updateNormalizer(1, true);
    }

    function test_RevertWhen_InvalidUpdate() public {
        _mintExactOutput(alice, address(eurA), 1 ether, 1 ether);
        _mintExactOutput(alice, address(eurB), 1 ether, 1 ether);

        vm.expectRevert(stdError.arithmeticError); // Should be an underflow
        hoax(governor);
        transmuter.updateNormalizer(4 ether, false);
    }

    function test_UpdateByGovernor() public {
        _mintExactOutput(alice, address(eurA), 1 ether, 1 ether);

        vm.expectEmit(address(transmuter));
        emit NormalizerUpdated(2 * BASE_27);

        hoax(governor);
        transmuter.updateNormalizer(1 ether, true);

        (uint256 stablecoinsFromCollateral, uint256 stablecoinsIssued) = transmuter.getIssuedByCollateral(
            address(eurA)
        );
        assertEq(stablecoinsFromCollateral, 2 ether);
        assertEq(stablecoinsIssued, 2 ether);

        uint256 normalizer = uint256(vm.load(address(transmuter), bytes32(uint256(TRANSMUTER_STORAGE_POSITION) + 1))) >>
            128;
        uint256 normalizedStables = (uint256(
            vm.load(address(transmuter), bytes32(uint256(TRANSMUTER_STORAGE_POSITION) + 1))
        ) << 128) >> 128;
        assertEq(normalizer, 2 * BASE_27);
        assertEq(normalizedStables, 1 ether);
    }

    function test_UpdateByWhitelisted() public {
        _mintExactOutput(alice, address(eurA), 1 ether, 1 ether);
        _mintExactOutput(alice, address(eurB), 1 ether, 1 ether);

        hoax(governor);
        transmuter.toggleTrusted(alice, TrustedType.Updater);

        vm.expectEmit(address(transmuter));
        emit NormalizerUpdated(2 * BASE_27);

        hoax(alice);
        // Increase of 2 with 2 in the system -> x2
        transmuter.updateNormalizer(2 ether, true);

        (uint256 stablecoinsFromCollateral, uint256 stablecoinsIssued) = transmuter.getIssuedByCollateral(
            address(eurA)
        );
        assertEq(stablecoinsFromCollateral, 2 ether);
        assertEq(stablecoinsIssued, 4 ether);
        (stablecoinsFromCollateral, stablecoinsIssued) = transmuter.getIssuedByCollateral(address(eurB));
        assertEq(stablecoinsFromCollateral, 2 ether);
        assertEq(stablecoinsIssued, 4 ether);

        uint256 normalizer = uint256(vm.load(address(transmuter), bytes32(uint256(TRANSMUTER_STORAGE_POSITION) + 1))) >>
            128;
        uint256 normalizedStables = (uint256(
            vm.load(address(transmuter), bytes32(uint256(TRANSMUTER_STORAGE_POSITION) + 1))
        ) << 128) >> 128;
        assertEq(normalizer, 2 * BASE_27); // 2x increase via the function call
        assertEq(normalizedStables, 2 ether);
    }

    function test_Decrease() public {
        _mintExactOutput(alice, address(eurA), 1 ether, 1 ether);
        _mintExactOutput(alice, address(eurB), 1 ether, 1 ether);

        vm.expectEmit(address(transmuter));
        emit NormalizerUpdated(BASE_27 / 2);

        hoax(governor);
        // Decrease of 1 with 2 in the system -> /2
        transmuter.updateNormalizer(1 ether, false);

        (uint256 stablecoinsFromCollateral, uint256 stablecoinsIssued) = transmuter.getIssuedByCollateral(
            address(eurA)
        );
        assertEq(stablecoinsFromCollateral, 1 ether / 2);
        assertEq(stablecoinsIssued, 1 ether);
        (stablecoinsFromCollateral, stablecoinsIssued) = transmuter.getIssuedByCollateral(address(eurB));
        assertEq(stablecoinsFromCollateral, 1 ether / 2);
        assertEq(stablecoinsIssued, 1 ether);

        uint256 normalizer = uint256(vm.load(address(transmuter), bytes32(uint256(TRANSMUTER_STORAGE_POSITION) + 1))) >>
            128;
        uint256 normalizedStables = (uint256(
            vm.load(address(transmuter), bytes32(uint256(TRANSMUTER_STORAGE_POSITION) + 1))
        ) << 128) >> 128;
        assertEq(normalizer, BASE_27 / 2);
        assertEq(normalizedStables, 2 ether);
    }

    function test_LargeIncrease() public {
        _mintExactOutput(alice, address(eurA), 1 ether, 1 ether);
        _mintExactOutput(alice, address(eurB), 1 ether, 1 ether);
        // normalizer -> 1e27, normalizedStables -> 2e18

        hoax(governor);
        transmuter.updateNormalizer(2 * (BASE_27 - 1 ether), true);
        // normalizer should do 1e27 -> 1e27 + 1e36 - 1e27 = 1e36

        (uint256 stablecoinsFromCollateral, uint256 stablecoinsIssued) = transmuter.getIssuedByCollateral(
            address(eurA)
        );
        assertEq(stablecoinsFromCollateral, BASE_27); // 1e27 stable backed by eurA
        assertEq(stablecoinsIssued, 2 * BASE_27);
        (stablecoinsFromCollateral, stablecoinsIssued) = transmuter.getIssuedByCollateral(address(eurB));
        assertEq(stablecoinsFromCollateral, BASE_27); // 1e27 stable backed by eurB
        assertEq(stablecoinsIssued, 2 * BASE_27);

        uint256 normalizer = uint256(vm.load(address(transmuter), bytes32(uint256(TRANSMUTER_STORAGE_POSITION) + 1))) >>
            128;
        uint256 normalizedStables = (uint256(
            vm.load(address(transmuter), bytes32(uint256(TRANSMUTER_STORAGE_POSITION) + 1))
        ) << 128) >> 128;
        assertEq(normalizer, BASE_27); // RENORMALIZED
        assertEq(normalizedStables, 2 * BASE_27);
    }
}

contract Test_Setters_SetCollateralManager is Fixture {
    event CollateralManagerSet(address indexed collateral, ManagerStorage managerData);

    function test_RevertWhen_NotGovernor() public {
        ManagerStorage memory data = ManagerStorage(new IERC20[](0), abi.encode(ManagerType.EXTERNAL, address(0)));

        vm.expectRevert(Errors.NotGovernor.selector);
        transmuter.setCollateralManager(address(eurA), data);

        vm.expectRevert(Errors.NotGovernor.selector);
        hoax(alice);
        transmuter.setCollateralManager(address(eurA), data);

        vm.expectRevert(Errors.NotGovernor.selector);
        hoax(guardian);
        transmuter.setCollateralManager(address(eurA), data);
    }

    function test_RevertWhen_NotCollateral() public {
        ManagerStorage memory data = ManagerStorage(new IERC20[](0), abi.encode(ManagerType.EXTERNAL, address(0)));

        vm.expectRevert(Errors.NotCollateral.selector);
        hoax(governor);
        transmuter.setCollateralManager(address(this), data);
    }

    function test_RevertWhen_InvalidParams() public {
        MockManager manager = new MockManager(address(eurA)); // Deploy a mock manager for eurA
        IERC20[] memory subCollaterals = new IERC20[](1);
        subCollaterals[0] = eurB;
        ManagerStorage memory data = ManagerStorage({
            subCollaterals: subCollaterals,
            config: abi.encode(ManagerType.EXTERNAL, abi.encode(manager))
        });

        vm.expectRevert(Errors.InvalidParams.selector);
        hoax(governor);
        transmuter.setCollateralManager(address(eurA), data);
    }

    function test_AddManager() public {
        MockManager manager = new MockManager(address(eurA)); // Deploy a mock manager for eurA
        IERC20[] memory subCollaterals = new IERC20[](1);
        subCollaterals[0] = eurA;
        ManagerStorage memory data = ManagerStorage({
            subCollaterals: subCollaterals,
            config: abi.encode(ManagerType.EXTERNAL, abi.encode(address(manager)))
        });

        (bool isManaged, IERC20[] memory fetchedSubCollaterals, bytes memory config) = transmuter.getManagerData(
            address(eurA)
        );
        assertEq(isManaged, false);
        assertEq(fetchedSubCollaterals.length, 0);
        assertEq(config.length, 0);

        vm.expectEmit(address(transmuter));
        emit CollateralManagerSet(address(eurA), data);

        hoax(governor);
        transmuter.setCollateralManager(address(eurA), data);

        // Refetch storage to check the update
        (isManaged, fetchedSubCollaterals, config) = transmuter.getManagerData(address(eurA));
        (, bytes memory aux) = abi.decode(config, (ManagerType, bytes));
        address fetched = abi.decode(aux, (address));

        assertEq(isManaged, true);
        assertEq(fetchedSubCollaterals.length, 1);
        assertEq(address(fetchedSubCollaterals[0]), address(eurA));
        assertEq(fetched, address(manager));
    }

    function test_RemoveManager() public {
        MockManager manager = new MockManager(address(eurA)); // Deploy a mock manager for eurA
        IERC20[] memory subCollaterals = new IERC20[](1);
        subCollaterals[0] = eurA;
        ManagerStorage memory data = ManagerStorage({
            subCollaterals: subCollaterals,
            config: abi.encode(ManagerType.EXTERNAL, abi.encode(manager))
        });

        hoax(governor);
        transmuter.setCollateralManager(address(eurA), data);

        data = ManagerStorage({ subCollaterals: new IERC20[](0), config: "" });
        hoax(governor);
        transmuter.setCollateralManager(address(eurA), data);

        (bool isManaged, IERC20[] memory fetchedSubCollaterals, bytes memory config) = transmuter.getManagerData(
            address(eurA)
        );
        assertEq(isManaged, false);
        assertEq(fetchedSubCollaterals.length, 0);
        assertEq(config.length, 0);
    }
}

contract Test_Setters_ChangeAllowance is Fixture {
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function test_RevertWhen_NotGovernor() public {
        vm.expectRevert(Errors.NotGovernor.selector);
        transmuter.changeAllowance(eurA, alice, 1 ether);

        vm.expectRevert(Errors.NotGovernor.selector);
        hoax(alice);
        transmuter.changeAllowance(eurA, alice, 1 ether);

        vm.expectRevert(Errors.NotGovernor.selector);
        hoax(guardian);
        transmuter.changeAllowance(eurA, alice, 1 ether);
    }

    function test_SafeIncreaseFrom0() public {
        vm.expectEmit(address(eurA));

        emit Approval(address(transmuter), alice, 1 ether);

        hoax(governor);
        transmuter.changeAllowance(eurA, alice, 1 ether);

        assertEq(eurA.allowance(address(transmuter), alice), 1 ether);
    }

    function test_SafeIncreaseFromNon0() public {
        hoax(governor);
        transmuter.changeAllowance(eurA, alice, 1 ether);

        vm.expectEmit(address(eurA));
        emit Approval(address(transmuter), alice, 2 ether);

        hoax(governor);
        transmuter.changeAllowance(eurA, alice, 2 ether);

        assertEq(eurA.allowance(address(transmuter), alice), 2 ether);
    }

    function test_SafeDecrease() public {
        hoax(governor);
        transmuter.changeAllowance(eurA, alice, 1 ether);

        vm.expectEmit(address(eurA));
        emit Approval(address(transmuter), alice, 0);

        hoax(governor);
        transmuter.changeAllowance(eurA, alice, 0);

        assertEq(eurA.allowance(address(transmuter), alice), 0);
    }
}

contract Test_Setters_AddCollateral is Fixture {
    event CollateralAdded(address indexed collateral);

    function test_RevertWhen_NonGovernor() public {
        vm.expectRevert(Errors.NotGovernor.selector);
        transmuter.addCollateral(address(eurA));

        vm.expectRevert(Errors.NotGovernor.selector);
        hoax(alice);
        transmuter.addCollateral(address(eurA));

        vm.expectRevert(Errors.NotGovernor.selector);
        hoax(guardian);
        transmuter.addCollateral(address(eurA));
    }

    function test_RevertWhen_AlreadyAdded() public {
        vm.expectRevert(Errors.AlreadyAdded.selector);
        hoax(governor);
        transmuter.addCollateral(address(eurA));
    }

    function test_Success() public {
        uint256 length = transmuter.getCollateralList().length;

        vm.expectEmit(address(transmuter));
        emit CollateralAdded(address(agToken));

        hoax(governor);
        transmuter.addCollateral(address(agToken));

        address[] memory list = transmuter.getCollateralList();
        assertEq(list.length, length + 1);
        assertEq(address(agToken), list[list.length - 1]);
        assertEq(transmuter.getCollateralDecimals(address(agToken)), agToken.decimals());
    }
}

contract Test_Setters_AdjustNormalizedStablecoins is Fixture {
    event ReservesAdjusted(address indexed collateral, uint256 amount, bool increase);

    function test_RevertWhen_NonGovernor() public {
        vm.expectRevert(Errors.NotGovernor.selector);
        transmuter.adjustStablecoins(address(eurA), 1 ether, true);

        vm.expectRevert(Errors.NotGovernor.selector);
        hoax(alice);
        transmuter.adjustStablecoins(address(eurA), 1 ether, true);

        vm.expectRevert(Errors.NotGovernor.selector);
        hoax(guardian);
        transmuter.adjustStablecoins(address(eurA), 1 ether, true);
    }

    function test_RevertWhen_NotCollateral() public {
        vm.expectRevert(Errors.NotCollateral.selector);
        hoax(governor);
        transmuter.adjustStablecoins(address(this), 1 ether, true);
    }

    function test_Decrease() public {
        _mintExactOutput(alice, address(eurA), 1 ether, 1 ether);
        _mintExactOutput(alice, address(eurB), 1 ether, 1 ether);

        vm.expectEmit(address(transmuter));
        emit ReservesAdjusted(address(eurA), 1 ether / 2, false);

        hoax(governor);
        transmuter.adjustStablecoins(address(eurA), 1 ether / 2, false);

        (uint256 stablecoinsFromCollateral, uint256 stablecoinsIssued) = transmuter.getIssuedByCollateral(
            address(eurA)
        );
        assertEq(stablecoinsFromCollateral, 1 ether / 2);
        assertEq(stablecoinsIssued, 3 ether / 2);

        uint256 normalizer = uint256(vm.load(address(transmuter), bytes32(uint256(TRANSMUTER_STORAGE_POSITION) + 1))) >>
            128;
        uint256 normalizedStables = (uint256(
            vm.load(address(transmuter), bytes32(uint256(TRANSMUTER_STORAGE_POSITION) + 1))
        ) << 128) >> 128;
        assertEq(normalizer, BASE_27);
        assertEq(normalizedStables, 3 ether / 2);
    }

    function test_Increase() public {
        _mintExactOutput(alice, address(eurA), 1 ether, 1 ether);
        _mintExactOutput(alice, address(eurB), 1 ether, 1 ether);

        vm.expectEmit(address(transmuter));
        emit ReservesAdjusted(address(eurA), 1 ether / 2, true);

        hoax(governor);
        transmuter.adjustStablecoins(address(eurA), 1 ether / 2, true);

        (uint256 stablecoinsFromCollateral, uint256 stablecoinsIssued) = transmuter.getIssuedByCollateral(
            address(eurA)
        );
        assertEq(stablecoinsFromCollateral, 3 ether / 2);
        assertEq(stablecoinsIssued, 5 ether / 2);

        uint256 normalizer = uint256(vm.load(address(transmuter), bytes32(uint256(TRANSMUTER_STORAGE_POSITION) + 1))) >>
            128;
        uint256 normalizedStables = (uint256(
            vm.load(address(transmuter), bytes32(uint256(TRANSMUTER_STORAGE_POSITION) + 1))
        ) << 128) >> 128;
        assertEq(normalizer, BASE_27);
        assertEq(normalizedStables, 5 ether / 2);
    }
}

contract Test_Setters_RevokeCollateral is Fixture {
    event CollateralRevoked(address indexed collateral);

    function test_RevertWhen_NonGovernor() public {
        vm.expectRevert(Errors.NotGovernor.selector);
        transmuter.adjustStablecoins(address(eurA), 1 ether, true);

        vm.expectRevert(Errors.NotGovernor.selector);
        hoax(alice);
        transmuter.adjustStablecoins(address(eurA), 1 ether, true);

        vm.expectRevert(Errors.NotGovernor.selector);
        hoax(guardian);
        transmuter.adjustStablecoins(address(eurA), 1 ether, true);
    }

    function test_RevertWhen_NotCollateral() public {
        vm.expectRevert(Errors.NotCollateral.selector);
        hoax(governor);
        transmuter.adjustStablecoins(address(this), 1 ether, true);
    }

    function test_RevertWhen_StillBacked() public {
        _mintExactOutput(alice, address(eurA), 1 ether, 1 ether);

        vm.expectRevert(Errors.NotCollateral.selector);
        hoax(governor);
        transmuter.adjustStablecoins(address(this), 1 ether, true);
    }

    function test_RevertWhen_ManagerHasAssets() public {
        MockManager manager = new MockManager(address(eurA));
        IERC20[] memory subCollaterals = new IERC20[](2);
        subCollaterals[0] = eurA;
        subCollaterals[1] = eurB;
        ManagerStorage memory data = ManagerStorage({
            subCollaterals: subCollaterals,
            config: abi.encode(ManagerType.EXTERNAL, abi.encode(manager))
        });
        manager.setSubCollaterals(data.subCollaterals, "");

        hoax(governor);
        transmuter.setCollateralManager(address(eurA), data);

        deal(address(eurA), address(manager), 1 ether);

        vm.expectRevert(Errors.ManagerHasAssets.selector);

        hoax(governor);
        transmuter.revokeCollateral(address(eurA));
    }

    function test_Success() public {
        address[] memory prevlist = transmuter.getCollateralList();

        vm.expectEmit(address(transmuter));
        emit CollateralRevoked(address(eurA));

        hoax(governor);
        transmuter.revokeCollateral(address(eurA));

        address[] memory list = transmuter.getCollateralList();
        assertEq(list.length, prevlist.length - 1);

        for (uint256 i = 0; i < list.length; i++) {
            assertNotEq(address(list[i]), address(eurA));
        }

        assertEq(0, transmuter.getCollateralDecimals(address(eurA)));

        (uint64[] memory xFeeMint, int64[] memory yFeeMint) = transmuter.getCollateralMintFees(address(eurA));
        assertEq(0, xFeeMint.length);
        assertEq(0, yFeeMint.length);

        (uint64[] memory xFeeBurn, int64[] memory yFeeBurn) = transmuter.getCollateralMintFees(address(eurA));
        assertEq(0, xFeeBurn.length);
        assertEq(0, yFeeBurn.length);

        vm.expectRevert(Errors.NotCollateral.selector);
        transmuter.isPaused(address(eurA), ActionType.Mint);
        vm.expectRevert(Errors.NotCollateral.selector);
        transmuter.isPaused(address(eurA), ActionType.Burn);
        vm.expectRevert();
        transmuter.getOracle(address(eurA));
        vm.expectRevert();
        transmuter.getOracleValues(address(eurA));
        (bool managed, , ) = transmuter.getManagerData(address(eurA));
        assert(!managed);
        (uint256 issued, ) = transmuter.getIssuedByCollateral(address(eurA));
        assertEq(0, issued);
        assert(transmuter.isWhitelistedForCollateral(address(eurA), address(this)));
    }

    function test_SuccessWithManager() public {
        MockManager manager = new MockManager(address(eurA));
        IERC20[] memory subCollaterals = new IERC20[](2);
        subCollaterals[0] = eurA;
        subCollaterals[1] = eurB;
        ManagerStorage memory data = ManagerStorage({
            subCollaterals: subCollaterals,
            config: abi.encode(ManagerType.EXTERNAL, abi.encode(manager))
        });
        manager.setSubCollaterals(data.subCollaterals, "");

        hoax(governor);
        transmuter.setCollateralManager(address(eurA), data);

        address[] memory prevlist = transmuter.getCollateralList();

        vm.expectEmit(address(transmuter));
        emit CollateralRevoked(address(eurA));

        hoax(governor);
        transmuter.revokeCollateral(address(eurA));

        address[] memory list = transmuter.getCollateralList();
        assertEq(list.length, prevlist.length - 1);

        for (uint256 i = 0; i < list.length; i++) {
            assertNotEq(address(list[i]), address(eurA));
        }

        assertEq(0, transmuter.getCollateralDecimals(address(eurA)));
        assertEq(0, eurA.balanceOf(address(manager)));
        assertEq(0, eurA.balanceOf(address(transmuter)));

        (bool managed, , ) = transmuter.getManagerData(address(eurA));
        assert(!managed);
    }
}
