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
import "contracts/helpers/MultiBlockHarvester.sol";

import "contracts/transmuter/Storage.sol";

import { IXEVT } from "interfaces/IXEVT.sol";

import { IERC4626 } from "oz/token/ERC20/extensions/ERC4626.sol";
import { IAccessControl } from "oz/access/IAccessControl.sol";

contract MultiBlockHarvestertTest is Fixture, FunctionUtils {
    using SafeERC20 for IERC20;

    MultiBlockHarvester public harvester;
    uint64 public targetExposure;
    uint64 public maxExposureYieldAsset;
    uint64 public minExposureYieldAsset;

    AggregatorV3Interface public oracleUSDC;
    AggregatorV3Interface public oracleEURC;
    AggregatorV3Interface public oracleXEVT;
    AggregatorV3Interface public oracleUSDM;

    address public receiver;

    function setUp() public override {
        super.setUp();

        receiver = makeAddr("receiver");

        vm.createSelectFork("mainnet");

        // set mint Fees to 0 on all collaterals
        uint64[] memory xFeeMint = new uint64[](1);
        xFeeMint[0] = uint64(0);
        uint64[] memory xFeeBurn = new uint64[](1);
        xFeeBurn[0] = uint64(BASE_9);
        int64[] memory yFeeMint = new int64[](1);
        yFeeMint[0] = 0;
        int64[] memory yFeeBurn = new int64[](1);
        yFeeBurn[0] = 0;
        int64[] memory yFeeRedemption = new int64[](1);
        yFeeRedemption[0] = int64(int256(BASE_9));
        vm.startPrank(governor);

        // remove fixture collateral
        transmuter.revokeCollateral(address(eurA));
        transmuter.revokeCollateral(address(eurB));
        transmuter.revokeCollateral(address(eurY));

        transmuter.addCollateral(XEVT);
        transmuter.addCollateral(USDM);
        transmuter.addCollateral(EURC);
        transmuter.addCollateral(USDC);

        AggregatorV3Interface[] memory circuitChainlink = new AggregatorV3Interface[](1);
        uint32[] memory stalePeriods = new uint32[](1);
        uint8[] memory circuitChainIsMultiplied = new uint8[](1);
        uint8[] memory chainlinkDecimals = new uint8[](1);
        stalePeriods[0] = 1 hours;
        circuitChainIsMultiplied[0] = 1;
        chainlinkDecimals[0] = 8;
        OracleQuoteType quoteType = OracleQuoteType.UNIT;
        bytes memory targetData;
        bytes memory readData;
        oracleEURC = AggregatorV3Interface(address(new MockChainlinkOracle()));
        circuitChainlink[0] = AggregatorV3Interface(oracleEURC);
        readData = abi.encode(circuitChainlink, stalePeriods, circuitChainIsMultiplied, chainlinkDecimals, quoteType);
        MockChainlinkOracle(address(oracleEURC)).setLatestAnswer(int256(BASE_8));
        transmuter.setOracle(
            EURC,
            abi.encode(
                OracleReadType.CHAINLINK_FEEDS,
                OracleReadType.STABLE,
                readData,
                targetData,
                abi.encode(uint128(0), uint128(0))
            )
        );

        oracleUSDC = AggregatorV3Interface(address(new MockChainlinkOracle()));
        circuitChainlink[0] = AggregatorV3Interface(oracleUSDC);
        readData = abi.encode(circuitChainlink, stalePeriods, circuitChainIsMultiplied, chainlinkDecimals, quoteType);
        MockChainlinkOracle(address(oracleUSDC)).setLatestAnswer(int256(BASE_8));
        transmuter.setOracle(
            USDC,
            abi.encode(
                OracleReadType.CHAINLINK_FEEDS,
                OracleReadType.STABLE,
                readData,
                targetData,
                abi.encode(uint128(0), uint128(0))
            )
        );

        oracleXEVT = AggregatorV3Interface(address(new MockChainlinkOracle()));
        circuitChainlink[0] = AggregatorV3Interface(oracleXEVT);
        readData = abi.encode(circuitChainlink, stalePeriods, circuitChainIsMultiplied, chainlinkDecimals, quoteType);
        MockChainlinkOracle(address(oracleXEVT)).setLatestAnswer(int256(BASE_8));
        transmuter.setOracle(
            XEVT,
            abi.encode(
                OracleReadType.CHAINLINK_FEEDS,
                OracleReadType.STABLE,
                readData,
                targetData,
                abi.encode(uint128(0), uint128(0))
            )
        );

        oracleUSDM = AggregatorV3Interface(address(new MockChainlinkOracle()));
        circuitChainlink[0] = AggregatorV3Interface(oracleUSDM);
        readData = abi.encode(circuitChainlink, stalePeriods, circuitChainIsMultiplied, chainlinkDecimals, quoteType);
        MockChainlinkOracle(address(oracleUSDM)).setLatestAnswer(int256(BASE_8));
        transmuter.setOracle(
            USDM,
            abi.encode(
                OracleReadType.CHAINLINK_FEEDS,
                OracleReadType.STABLE,
                readData,
                targetData,
                abi.encode(uint128(0), uint128(0))
            )
        );

        transmuter.togglePause(XEVT, ActionType.Mint);
        transmuter.togglePause(XEVT, ActionType.Burn);
        transmuter.setStablecoinCap(XEVT, type(uint256).max);
        transmuter.togglePause(EURC, ActionType.Mint);
        transmuter.togglePause(EURC, ActionType.Burn);
        transmuter.setStablecoinCap(EURC, type(uint256).max);
        transmuter.togglePause(USDM, ActionType.Mint);
        transmuter.togglePause(USDM, ActionType.Burn);
        transmuter.setStablecoinCap(USDM, type(uint256).max);
        transmuter.togglePause(USDC, ActionType.Mint);
        transmuter.togglePause(USDC, ActionType.Burn);
        transmuter.setStablecoinCap(USDC, type(uint256).max);

        // mock isAllowed(address) returns (bool) to transfer XEVT
        vm.mockCall(
            0x9019Fd383E490B4B045130707C9A1227F36F4636,
            abi.encodeWithSelector(IXEVT.isAllowed.selector),
            abi.encode(true)
        );

        transmuter.setFees(address(XEVT), xFeeMint, yFeeMint, true);
        transmuter.setFees(address(XEVT), xFeeBurn, yFeeBurn, false);
        transmuter.setFees(address(USDM), xFeeMint, yFeeMint, true);
        transmuter.setFees(address(USDM), xFeeBurn, yFeeBurn, false);
        transmuter.setFees(address(EURC), xFeeMint, yFeeMint, true);
        transmuter.setFees(address(EURC), xFeeBurn, yFeeBurn, false);
        transmuter.setFees(address(USDC), xFeeMint, yFeeMint, true);
        transmuter.setFees(address(USDC), xFeeBurn, yFeeBurn, false);
        transmuter.setRedemptionCurveParams(xFeeMint, yFeeRedemption);
        vm.stopPrank();

        targetExposure = uint64((15 * 1e9) / 100);
        maxExposureYieldAsset = uint64((90 * 1e9) / 100);
        minExposureYieldAsset = uint64((5 * 1e9) / 100);

        harvester = new MultiBlockHarvester(100_000e18, 1e8, accessControlManager, agToken, transmuter);
        vm.startPrank(governor);
        harvester.toggleTrusted(alice);
        harvester.setYieldBearingToDepositAddress(XEVT, XEVT);
        harvester.setYieldBearingToDepositAddress(USDM, receiver);

        transmuter.toggleTrusted(address(harvester), TrustedType.Seller);

        vm.stopPrank();

        vm.label(XEVT, "XEVT");
        vm.label(USDM, "USDM");
        vm.label(EURC, "EURC");
        vm.label(USDC, "USDC");
        vm.label(address(harvester), "Harvester");
    }

    function test_Initialization() public {
        assertEq(harvester.maxSlippage(), 1e8);
        assertEq(harvester.maxMintAmount(), 100_000e18);
        assertEq(address(harvester.accessControlManager()), address(accessControlManager));
        assertEq(address(harvester.agToken()), address(agToken));
        assertEq(address(harvester.transmuter()), address(transmuter));
    }

    function test_OnlyGuardian_RevertWhen_NotGuardian() public {
        vm.expectRevert(Errors.NotGovernorOrGuardian.selector);
        harvester.setYieldBearingAssetData(
            address(XEVT),
            address(EURC),
            targetExposure,
            1,
            maxExposureYieldAsset,
            minExposureYieldAsset
        );

        vm.expectRevert(Errors.NotGovernorOrGuardian.selector);
        harvester.setMaxSlippage(1e9);

        vm.expectRevert(Errors.NotGovernorOrGuardian.selector);
        harvester.toggleTrusted(alice);
    }

    function test_OnlyTrusted_RevertWhen_NotTrusted() public {
        vm.expectRevert(Errors.NotTrustedOrGuardian.selector);
        harvester.setTargetExposure(address(EURC), targetExposure);

        vm.expectRevert(Errors.NotTrusted.selector);
        harvester.harvest(XEVT, 1e9, new bytes(0));

        vm.expectRevert(Errors.NotTrusted.selector);
        harvester.finalizeRebalance(EURC, 1e6);
    }

    function test_SettersHarvester() public {
        vm.startPrank(governor);
        vm.expectRevert(Errors.InvalidParam.selector);
        harvester.setMaxSlippage(1e10);

        harvester.setMaxSlippage(123456);
        assertEq(harvester.maxSlippage(), 123456);

        harvester.setYieldBearingAssetData(
            address(XEVT),
            address(EURC),
            targetExposure + 10,
            minExposureYieldAsset - 1,
            maxExposureYieldAsset + 1,
            1
        );
        (address stablecoin, uint64 target, uint64 maxi, uint64 mini, uint64 overrideExp) = harvester.yieldBearingData(
            address(XEVT)
        );
        assertEq(stablecoin, address(EURC));
        assertEq(target, targetExposure + 10);
        assertEq(maxi, maxExposureYieldAsset + 1);
        assertEq(mini, minExposureYieldAsset - 1);
        assertEq(overrideExp, 1);

        harvester.setYieldBearingAssetData(
            address(XEVT),
            address(EURC),
            targetExposure + 10,
            minExposureYieldAsset - 1,
            maxExposureYieldAsset + 1,
            0
        );
        (stablecoin, target, maxi, mini, overrideExp) = harvester.yieldBearingData(address(XEVT));
        assertEq(stablecoin, address(EURC));
        assertEq(target, targetExposure + 10);
        assertEq(maxi, 1e9);
        assertEq(mini, 0);
        assertEq(overrideExp, 2);

        vm.stopPrank();
    }

    function test_UpdateLimitExposuresYieldAsset() public {
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
        transmuter.setFees(address(EURC), xFeeBurn, yFeeBurn, false);
        transmuter.setFees(address(EURC), xFeeMint, yFeeMint, true);
        harvester.setYieldBearingAssetData(
            address(XEVT),
            address(EURC),
            targetExposure,
            minExposureYieldAsset,
            maxExposureYieldAsset,
            0
        );
        harvester.updateLimitExposuresYieldAsset(address(XEVT));

        (, , uint64 maxi, uint64 mini, ) = harvester.yieldBearingData(address(XEVT));
        assertEq(maxi, (15 * BASE_9) / 100);
        assertEq(mini, BASE_9 / 10);
        vm.stopPrank();
    }

    function test_ToggleTrusted() public {
        vm.startPrank(governor);
        harvester.toggleTrusted(bob);
        assertEq(harvester.isTrusted(bob), true);

        harvester.toggleTrusted(bob);
        assertEq(harvester.isTrusted(bob), false);

        vm.stopPrank();
    }

    function test_SetTargetExposure() public {
        vm.prank(governor);
        harvester.setTargetExposure(address(EURC), targetExposure + 1);
        (, uint64 currentTargetExposure, , , ) = harvester.yieldBearingData(address(EURC));
        assertEq(currentTargetExposure, targetExposure + 1);
    }

    function test_harvest_TooBigMintedAmount() external {
        _loadReserve(EURC, 1e26);
        _loadReserve(XEVT, 1e6);
        _setYieldBearingData(XEVT, EURC);

        vm.expectRevert(TooBigAmountIn.selector);
        vm.prank(alice);
        harvester.harvest(XEVT, 1e9, new bytes(0));
    }

    function test_harvest_IncreaseExposureXEVT(uint256 amount) external {
        amount = bound(amount, 1e3, 1e11);
        _loadReserve(EURC, amount);
        _setYieldBearingData(XEVT, EURC);

        (uint256 issuedFromYieldBearingAssetBefore, ) = transmuter.getIssuedByCollateral(XEVT);
        (uint256 issuedFromStablecoinBefore, uint256 totalIssuedBefore) = transmuter.getIssuedByCollateral(EURC);
        (uint8 expectedIncrease, uint256 expectedAmount) = harvester.computeRebalanceAmount(XEVT);

        assertEq(expectedIncrease, 1);
        assertEq(expectedAmount, (amount * 1e12 * targetExposure) / 1e9);
        assertEq(issuedFromStablecoinBefore, amount * 1e12);
        assertEq(issuedFromYieldBearingAssetBefore, 0);
        assertEq(totalIssuedBefore, issuedFromStablecoinBefore);

        vm.prank(alice);
        harvester.harvest(XEVT, 1e9, new bytes(0));

        assertEq(IERC20(XEVT).balanceOf(address(harvester)), 0);
        assertEq(IERC20(EURC).balanceOf(address(harvester)), 0);
        assertEq(agToken.balanceOf(address(harvester)), 0);

        (uint256 issuedFromYieldBearingAsset, uint256 totalIssued) = transmuter.getIssuedByCollateral(XEVT);
        (uint256 issuedFromStablecoin, ) = transmuter.getIssuedByCollateral(EURC);
        assertEq(totalIssued, issuedFromStablecoin + issuedFromYieldBearingAsset);
        assertApproxEqRel(issuedFromStablecoin, (totalIssued * (1e9 - targetExposure)) / 1e9, 1e18);
        assertApproxEqRel(issuedFromYieldBearingAsset, (totalIssued * targetExposure) / 1e9, 1e18);

        (uint8 increase, uint256 amount) = harvester.computeRebalanceAmount(XEVT);
        assertEq(increase, 1); // There is still a small amount to mint because of the transmuter fees and slippage
    }

    function test_harvest_DecreaseExposureXEVT(uint256 amount) external {
        amount = bound(amount, 1e3, 1e11);
        _loadReserve(XEVT, amount);
        _setYieldBearingData(XEVT, EURC);

        (uint256 issuedFromYieldBearingAssetBefore, ) = transmuter.getIssuedByCollateral(XEVT);
        (uint256 issuedFromStablecoinBefore, uint256 totalIssuedBefore) = transmuter.getIssuedByCollateral(EURC);
        (uint8 expectedIncrease, uint256 expectedAmount) = harvester.computeRebalanceAmount(XEVT);

        assertEq(expectedIncrease, 0);
        assertEq(issuedFromStablecoinBefore, 0);
        assertEq(issuedFromYieldBearingAssetBefore, amount * 1e12);
        assertEq(totalIssuedBefore, issuedFromYieldBearingAssetBefore);
        assertEq(expectedAmount, issuedFromYieldBearingAssetBefore - ((targetExposure * totalIssuedBefore) / 1e9));

        vm.prank(alice);
        harvester.harvest(XEVT, 1e9, new bytes(0));

        assertEq(IERC20(EURC).balanceOf(address(harvester)), 0);
        assertApproxEqRel(IERC20(XEVT).balanceOf(address(harvester)), expectedAmount / 1e12, 1e18); // XEVT is stored in the harvester while the redemption is in progress
        assertEq(agToken.balanceOf(address(harvester)), 0);

        // fake semd EURC to harvester
        deal(EURC, address(harvester), amount);

        vm.prank(alice);
        harvester.finalizeRebalance(EURC, amount);

        assertEq(agToken.balanceOf(address(harvester)), 0);
        assertEq(IERC20(EURC).balanceOf(address(harvester)), 0);

        (uint256 issuedFromYieldBearingAsset, uint256 totalIssued) = transmuter.getIssuedByCollateral(XEVT);
        (uint256 issuedFromStablecoin, ) = transmuter.getIssuedByCollateral(EURC);
        assertEq(totalIssued, issuedFromStablecoin + issuedFromYieldBearingAsset);
        assertApproxEqRel(issuedFromStablecoin, (totalIssued * (1e9 - targetExposure)) / 1e9, 1e18);
        assertApproxEqRel(issuedFromYieldBearingAsset, (totalIssued * targetExposure) / 1e9, 1e18);

        (uint8 increase, uint256 amount) = harvester.computeRebalanceAmount(XEVT);
        assertEq(increase, 1); // There is still a small amount to mint because of the transmuter fees and slippage
    }

    function test_harvest_IncreaseExposureUSDM(uint256 amount) external {
        amount = bound(amount, 1e3, 1e11);
        _loadReserve(USDC, amount);
        _setYieldBearingData(USDM, USDC);

        (uint256 issuedFromYieldBearingAssetBefore, ) = transmuter.getIssuedByCollateral(USDM);
        (uint256 issuedFromStablecoinBefore, uint256 totalIssuedBefore) = transmuter.getIssuedByCollateral(USDC);
        (uint8 expectedIncrease, uint256 expectedAmount) = harvester.computeRebalanceAmount(USDM);

        assertEq(expectedIncrease, 1);
        assertEq(issuedFromStablecoinBefore, amount * 1e12);
        assertEq(issuedFromYieldBearingAssetBefore, 0);
        assertEq(totalIssuedBefore, issuedFromStablecoinBefore);
        assertEq(expectedAmount, (amount * 1e12 * targetExposure) / 1e9);

        vm.prank(alice);
        harvester.harvest(USDM, 1e9, new bytes(0));

        assertEq(IERC20(USDC).balanceOf(address(harvester)), 0);
        assertEq(IERC20(USDM).balanceOf(address(harvester)), 0);
        assertApproxEqRel(IERC20(USDM).balanceOf(address(receiver)), expectedAmount, 1e18);
        assertEq(agToken.balanceOf(address(harvester)), 0);

        // fake semd USDC to harvester
        deal(USDC, address(harvester), amount);

        vm.prank(alice);
        harvester.finalizeRebalance(USDC, amount);

        assertEq(agToken.balanceOf(address(harvester)), 0);
        assertEq(IERC20(USDC).balanceOf(address(harvester)), 0);

        (uint256 issuedFromYieldBearingAsset, uint256 totalIssued) = transmuter.getIssuedByCollateral(USDM);
        (uint256 issuedFromStablecoin, ) = transmuter.getIssuedByCollateral(USDC);
        assertEq(totalIssued, issuedFromStablecoin + issuedFromYieldBearingAsset);
        assertApproxEqRel(issuedFromStablecoin, (totalIssued * (1e9 - targetExposure)) / 1e9, 1e18);
        assertApproxEqRel(issuedFromYieldBearingAsset, (totalIssued * targetExposure) / 1e9, 1e18);

        (uint8 increase, uint256 amount) = harvester.computeRebalanceAmount(USDM);
        assertEq(increase, 1); // There is still a small amount to mint because of the transmuter fees and slippage
    }

    function test_harvest_DecreaseExposureUSDM(uint256 amount) external {
        amount = bound(amount, 1e15, 1e23);
        _loadReserve(USDM, amount);
        _setYieldBearingData(USDM, USDC);

        (uint256 issuedFromYieldBearingAssetBefore, ) = transmuter.getIssuedByCollateral(USDM);
        (uint256 issuedFromStablecoinBefore, uint256 totalIssuedBefore) = transmuter.getIssuedByCollateral(USDC);
        (uint8 expectedIncrease, uint256 expectedAmount) = harvester.computeRebalanceAmount(USDM);

        assertEq(expectedIncrease, 0);
        assertEq(issuedFromStablecoinBefore, 0);
        assertEq(issuedFromYieldBearingAssetBefore, amount);
        assertEq(totalIssuedBefore, issuedFromYieldBearingAssetBefore);
        assertEq(expectedAmount, issuedFromYieldBearingAssetBefore - ((targetExposure * totalIssuedBefore) / 1e9));

        vm.prank(alice);
        harvester.harvest(USDM, 1e9, new bytes(0));

        assertEq(IERC20(USDC).balanceOf(address(harvester)), 0);
        assertEq(IERC20(USDM).balanceOf(address(harvester)), 0);
        assertApproxEqRel(IERC20(USDM).balanceOf(address(receiver)), expectedAmount, 1e18);
        assertEq(agToken.balanceOf(address(harvester)), 0);

        // fake semd USDC to harvester
        deal(USDC, address(harvester), amount);

        vm.prank(alice);
        harvester.finalizeRebalance(USDC, amount);

        assertEq(agToken.balanceOf(address(harvester)), 0);
        assertEq(IERC20(USDC).balanceOf(address(harvester)), 0);

        (uint256 issuedFromYieldBearingAsset, uint256 totalIssued) = transmuter.getIssuedByCollateral(USDM);
        (uint256 issuedFromStablecoin, ) = transmuter.getIssuedByCollateral(USDC);
        assertEq(totalIssued, issuedFromStablecoin + issuedFromYieldBearingAsset);
        assertApproxEqRel(issuedFromStablecoin, (totalIssued * (1e9 - targetExposure)) / 1e9, 1e18);
        assertApproxEqRel(issuedFromYieldBearingAsset, (totalIssued * targetExposure) / 1e9, 1e18);

        (uint8 increase, uint256 amount) = harvester.computeRebalanceAmount(USDM);
        assertEq(increase, 1); // There is still a small amount to mint because of the transmuter fees and slippage
    }

    function test_ComputeRebalanceAmount_HigherThanMax() external {
        _loadReserve(XEVT, 1e11);
        _loadReserve(EURC, 1e11);
        uint64 minExposure = uint64((15 * 1e9) / 100);
        uint64 maxExposure = uint64((40 * 1e9) / 100);
        _setYieldBearingData(XEVT, EURC, minExposure, maxExposure);

        (uint8 increase, uint256 amount) = harvester.computeRebalanceAmount(XEVT);
        assertEq(amount, 0);
        assertEq(increase, 0);
    }

    function test_ComputeRebalanceAmount_HigherThanMaxWithHarvest() external {
        _loadReserve(XEVT, 1e11);
        _loadReserve(EURC, 1e11);
        uint64 minExposure = uint64((15 * 1e9) / 100);
        uint64 maxExposure = uint64((60 * 1e9) / 100);
        _setYieldBearingData(XEVT, EURC, minExposure, maxExposure);

        (uint8 increase, uint256 amount) = harvester.computeRebalanceAmount(XEVT);
        assertEq(amount, (2e23 * uint256(maxExposure)) / 1e9 - 1e23);
        assertEq(increase, 0);
    }

    function test_ComputeRebalanceAmount_LowerThanMin() external {
        _loadReserve(EURC, 9e10);
        _loadReserve(XEVT, 1e10);
        uint64 minExposure = uint64((99 * 1e9) / 100);
        uint64 maxExposure = uint64((999 * 1e9) / 1000);
        _setYieldBearingData(XEVT, EURC, minExposure, maxExposure);

        (uint8 increase, uint256 amount) = harvester.computeRebalanceAmount(XEVT);
        assertEq(amount, 0);
        assertEq(increase, 1);
    }

    function test_ComputeRebalanceAmount_LowerThanMinAfterHarvest() external {
        _loadReserve(EURC, 9e10);
        _loadReserve(XEVT, 1e10);
        uint64 minExposure = uint64((89 * 1e9) / 100);
        uint64 maxExposure = uint64((999 * 1e9) / 1000);
        _setYieldBearingData(XEVT, EURC, minExposure, maxExposure);

        (uint8 increase, uint256 amount) = harvester.computeRebalanceAmount(XEVT);
        assertEq(amount, 9e22 - (1e23 * uint256(minExposure)) / 1e9);
        assertEq(increase, 1);
    }

    function test_SlippageTooHighStablecoin(uint256 amount) external {
        // TODO
    }

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
