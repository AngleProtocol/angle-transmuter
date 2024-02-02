// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import { IAgToken } from "interfaces/IAgToken.sol";

import { console } from "forge-std/console.sol";

import { IMockFacet, MockPureFacet } from "mock/MockFacets.sol";

import { Layout } from "contracts/transmuter/Layout.sol";
import "contracts/transmuter/Storage.sol";
import { Test } from "contracts/transmuter/configs/Test.sol";
import { DiamondCut } from "contracts/transmuter/facets/DiamondCut.sol";
import "contracts/utils/Constants.sol";

import { Fixture } from "../Fixture.sol";

contract Test_Layout is Fixture {
    Layout layout;

    function setUp() public override {
        super.setUp();
        layout = Layout(address(transmuter));
    }

    function test_Layout() public {
        address agToken = address(transmuter.agToken());
        uint8 isRedemptionLive = transmuter.isPaused(address(0), ActionType.Redeem) ? 0 : 1;
        uint256 stablecoinsIssued = transmuter.getTotalIssued();
        address[] memory collateralList = transmuter.getCollateralList();
        (uint64[] memory xRedemptionCurve, int64[] memory yRedemptionCurve) = transmuter.getRedemptionFees();
        Collateral memory collateral = transmuter.getCollateralInfo(collateralList[0]);
        hoax(governor);
        transmuter.toggleTrusted(alice, TrustedType.Updater);
        hoax(governor);
        transmuter.toggleTrusted(alice, TrustedType.Seller);
        address accessControlManager = address(transmuter.accessControlManager());
        hoax(governor);
        transmuter.setDummyImplementation(address(alice));
        address implementation = transmuter.implementation();

        _etch();

        assertEq(layout.agToken(), agToken);
        assertEq(layout.isRedemptionLive(), isRedemptionLive);
        assertEq((layout.normalizedStables() * layout.normalizer()) / BASE_27, stablecoinsIssued);
        for (uint256 i; i < collateralList.length; i++) {
            assertEq(layout.collateralList(i), collateralList[i]);
        }
        for (uint256 i; i < xRedemptionCurve.length; i++) {
            assertEq(layout.xRedemptionCurve(i), xRedemptionCurve[i]);
        }
        for (uint256 i; i < yRedemptionCurve.length; i++) {
            assertEq(layout.yRedemptionCurve(i), yRedemptionCurve[i]);
        }
        (
            uint8 isManaged,
            uint8 isMintLive,
            uint8 isBurnLive,
            uint8 decimals,
            uint8 onlyWhitelisted,
            uint216 normalizedStables,
            bytes memory oracleConfig,
            bytes memory whitelistData,

        ) = layout.collaterals(collateralList[0]);

        assertEq(isManaged, collateral.isManaged);
        assertEq(isMintLive, collateral.isMintLive);
        assertEq(isBurnLive, collateral.isBurnLive);
        assertEq(decimals, collateral.decimals);
        assertEq(onlyWhitelisted, collateral.onlyWhitelisted);
        assertEq(normalizedStables, collateral.normalizedStables);
        assertEq(oracleConfig, collateral.oracleConfig);
        assertEq(whitelistData, collateral.whitelistData);
        assertEq(layout.isTrusted(alice), 1);
        assertEq(layout.isSellerTrusted(alice), 1);
        assertEq(layout.isTrusted(bob), 0);
        assertEq(layout.isSellerTrusted(bob), 0);

        bytes4[] memory selectors = _generateSelectors("ITransmuter");
        for (uint i = 0; i < selectors.length; ++i) {
            (address facetAddress, uint16 selectorPosition) = layout.selectorInfo(selectors[i]);
            assertNotEq(facetAddress, address(0));
            assertEq(layout.selectors(selectorPosition), selectors[i]);
        }

        assertEq(layout.accessControlManager(), accessControlManager);
        assertEq(layout.implementation(), implementation);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       INTERNAL                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _etch() internal {
        Layout tempLayout = new Layout();
        vm.etch(address(layout), address(tempLayout).code);
    }
}
