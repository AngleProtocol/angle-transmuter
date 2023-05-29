// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";

import "contracts/transmuter/Storage.sol";
import { Test } from "contracts/transmuter/configs/Test.sol";
import { Setters } from "contracts/transmuter/facets/Setters.sol";
import { DiamondCut } from "contracts/transmuter/facets/DiamondCut.sol";
import { LibSetters } from "contracts/transmuter/libraries/LibSetters.sol";
import "contracts/utils/Constants.sol";
import "contracts/utils/Errors.sol" as Errors;

import { Fixture } from "../../Fixture.sol";

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

    function test_RevertWhen_ZeroAmount() public {
        vm.expectRevert(Errors.ZeroAmount.selector);

        hoax(governor);
        transmuter.recoverERC20(address(agToken), agToken, alice, 0);
    }

    // TODO Tests with manager
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

contract Test_Setters_SetCollateralManager is Fixture {}
