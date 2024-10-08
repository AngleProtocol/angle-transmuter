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
        MockChainlinkOracle(address(oracleXEVT)).setLatestAnswer(int256(IERC4626(XEVT).convertToAssets(BASE_8)));
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

        // mock isAllowed(address) returns (bool)
        vm.mockCall(
            0x9019Fd383E490B4B045130707C9A1227F36F4636,
            abi.encodeWithSelector(Wow.isAllowed.selector),
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
        maxExposureYieldAsset = uint64((80 * 1e9) / 100);
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
        harvester.updateLimitExposuresYieldAsset(address(XEVT));
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
        bytes memory data;
        address _savingImplementation = address(new Savings());
        Savings newVault = Savings(_deployUpgradeable(address(proxyAdmin), _savingImplementation, data));
        string memory _name = "savingAgEUR";
        string memory _symbol = "SAGEUR";

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
        harvester.setYieldBearingAssetData(
            address(newVault),
            address(eurA),
            targetExposure,
            minExposureYieldAsset,
            maxExposureYieldAsset,
            0
        );
        harvester.updateLimitExposuresYieldAsset(address(newVault));

        (, , uint64 maxi, uint64 mini, ) = harvester.yieldBearingData(address(newVault));
        assertEq(maxi, (15 * BASE_9) / 100);
        assertEq(mini, BASE_9 / 10);
        vm.stopPrank();
    }

    function test_FinalizeRebalance_IncreaseExposureXEVT(uint256 amount) external {
        _loadReserve(XEVT, 1e26);
        amount = bound(amount, 1e18, 1e24);
        deal(XEVT, address(harvester), amount);

        vm.prank(alice);
        harvester.finalizeRebalance(XEVT, amount);

        assertEq(agToken.balanceOf(address(harvester)), 0);
        assertEq(IERC20(XEVT).balanceOf(address(harvester)), 0);
    }

    function test_FinalizeRebalance_DecreaseExposureEURC(uint256 amount) external {
        _loadReserve(EURC, 1e26);
        amount = bound(amount, 1e18, 1e24);
        deal(EURC, address(harvester), amount);

        vm.prank(alice);
        harvester.finalizeRebalance(EURC, amount);

        assertEq(agToken.balanceOf(address(harvester)), 0);
        assertEq(IERC20(EURC).balanceOf(address(harvester)), 0);
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
        _loadReserve(EURC, 1e11);
        _loadReserve(XEVT, 1e6);
        _setYieldBearingData(XEVT, EURC);

        vm.prank(alice);
        harvester.harvest(XEVT, 1e9, new bytes(0));
    }

    function test_harvest_DecreaseExposureXEVT(uint256 amount) external {
        _loadReserve(EURC, 1e11);
        _loadReserve(XEVT, 1e8);
        _setYieldBearingData(XEVT, EURC);

        vm.prank(alice);
        harvester.harvest(XEVT, 1e9, new bytes(0));
    }

    function test_harvest_IncreaseExposureUSDM(uint256 amount) external {
        _loadReserve(USDC, 1e11);
        _loadReserve(USDM, 1e6);
        _setYieldBearingData(USDM, USDC);

        vm.prank(alice);
        harvester.harvest(USDM, 1e9, new bytes(0));
    }

    function test_harvest_DecreaseExposureUSDM(uint256 amount) external {
        _loadReserve(USDC, 1e11);
        _loadReserve(USDM, 1e8);
        _setYieldBearingData(USDM, USDC);

        vm.prank(alice);
        harvester.harvest(USDM, 1e9, new bytes(0));
    }

    function test_FinalizeRebalance_SlippageTooHigh(uint256 amount) external {
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
}

interface Wow {
    function isAllowed(address) external returns (bool);
}
