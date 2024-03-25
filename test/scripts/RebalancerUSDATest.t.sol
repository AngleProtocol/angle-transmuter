// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { stdJson } from "forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";

import "../../scripts/Constants.s.sol";

import { Helpers } from "../../scripts/Helpers.s.sol";
import "contracts/utils/Errors.sol" as Errors;
import "contracts/transmuter/Storage.sol" as Storage;
import { Getters } from "contracts/transmuter/facets/Getters.sol";
import { Redeemer } from "contracts/transmuter/facets/Redeemer.sol";
import { SettersGovernor } from "contracts/transmuter/facets/SettersGovernor.sol";
import { SettersGuardian } from "contracts/transmuter/facets/SettersGuardian.sol";
import { Swapper } from "contracts/transmuter/facets/Swapper.sol";
import "contracts/transmuter/libraries/LibHelpers.sol";
import "interfaces/external/chainlink/AggregatorV3Interface.sol";
import { CollateralSetupProd } from "contracts/transmuter/configs/ProductionTypes.sol";
import { ITransmuter } from "interfaces/ITransmuter.sol";
import "utils/src/Constants.sol";
import { IERC20 } from "oz/interfaces/IERC20.sol";
import { IAgToken } from "interfaces/IAgToken.sol";

import { RebalancerFlashloan, IERC4626, IERC3156FlashLender } from "contracts/helpers/RebalancerFlashloan.sol";

interface IFlashAngle {
    function addStablecoinSupport(address _treasury) external;
    function setFlashLoanParameters(address stablecoin, uint64 _flashLoanFee, uint256 _maxBorrowable) external;
}

contract RebalancerUSDATest is Helpers, Test {
    using stdJson for string;

    uint256 public CHAIN_SOURCE;

    string[] replaceFacetNames;
    string[] addFacetNames;
    address[] facetAddressList;
    address[] addFacetAddressList;

    ITransmuter transmuter;
    IERC20 USDA;
    IAgToken treasuryUSDA;
    IFlashAngle FLASHLOAN;
    address governor;
    RebalancerFlashloan public rebalancer;
    bytes public oracleConfigUSDC;
    bytes public oracleConfigIB01;
    bytes public oracleConfigSTEAK;

    function setUp() public override {
        super.setUp();

        CHAIN_SOURCE = CHAIN_ETHEREUM;

        ethereumFork = vm.createFork(vm.envString("ETH_NODE_URI_MAINNET"), 19483530);
        vm.selectFork(forkIdentifier[CHAIN_SOURCE]);

        // Setup Transmuter

        transmuter = ITransmuter(0x222222fD79264BBE280b4986F6FEfBC3524d0137);
        USDA = IERC20(0x0000206329b97DB379d5E1Bf586BbDB969C63274);
        FLASHLOAN = IFlashAngle(0x4A2FF9bC686A0A23DA13B6194C69939189506F7F);
        treasuryUSDA = IAgToken(0xf8588520E760BB0b3bDD62Ecb25186A28b0830ee);

        Storage.FacetCut[] memory replaceCut;
        Storage.FacetCut[] memory addCut;

        replaceFacetNames.push("Getters");
        facetAddressList.push(address(new Getters()));
        console.log("Getters deployed at: ", facetAddressList[facetAddressList.length - 1]);

        replaceFacetNames.push("Redeemer");
        facetAddressList.push(address(new Redeemer()));
        console.log("Redeemer deployed at: ", facetAddressList[facetAddressList.length - 1]);

        replaceFacetNames.push("SettersGovernor");
        address settersGovernor = address(new SettersGovernor());
        facetAddressList.push(settersGovernor);
        console.log("SettersGovernor deployed at: ", facetAddressList[facetAddressList.length - 1]);

        replaceFacetNames.push("Swapper");
        facetAddressList.push(address(new Swapper()));
        console.log("Swapper deployed at: ", facetAddressList[facetAddressList.length - 1]);

        addFacetNames.push("SettersGovernor");
        addFacetAddressList.push(settersGovernor);

        string memory jsonReplace = vm.readFile(JSON_SELECTOR_PATH_REPLACE);
        {
            // Build appropriate payload
            uint256 n = replaceFacetNames.length;
            replaceCut = new Storage.FacetCut[](n);
            for (uint256 i = 0; i < n; ++i) {
                // Get Selectors from json
                bytes4[] memory selectors = _arrayBytes32ToBytes4(
                    jsonReplace.readBytes32Array(string.concat("$.", replaceFacetNames[i]))
                );

                replaceCut[i] = Storage.FacetCut({
                    facetAddress: facetAddressList[i],
                    action: Storage.FacetCutAction.Replace,
                    functionSelectors: selectors
                });
            }
        }

        string memory jsonAdd = vm.readFile(JSON_SELECTOR_PATH_ADD);
        {
            // Build appropriate payload
            uint256 n = addFacetNames.length;
            addCut = new Storage.FacetCut[](n);
            for (uint256 i = 0; i < n; ++i) {
                // Get Selectors from json
                bytes4[] memory selectors = _arrayBytes32ToBytes4(
                    jsonAdd.readBytes32Array(string.concat("$.", addFacetNames[i]))
                );
                addCut[i] = Storage.FacetCut({
                    facetAddress: addFacetAddressList[i],
                    action: Storage.FacetCutAction.Add,
                    functionSelectors: selectors
                });
            }
        }

        vm.startPrank(DEPLOYER);

        bytes memory callData;
        // set the right implementations
        transmuter.diamondCut(replaceCut, address(0), callData);
        transmuter.diamondCut(addCut, address(0), callData);

        {
            bytes memory oracleConfig;
            bytes memory readData;
            {
                AggregatorV3Interface[] memory circuitChainlink = new AggregatorV3Interface[](1);
                uint32[] memory stalePeriods = new uint32[](1);
                uint8[] memory circuitChainIsMultiplied = new uint8[](1);
                uint8[] memory chainlinkDecimals = new uint8[](1);

                // Chainlink USDC/USD oracle
                circuitChainlink[0] = AggregatorV3Interface(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);
                stalePeriods[0] = ((1 days) * 3) / 2;
                circuitChainIsMultiplied[0] = 1;
                chainlinkDecimals[0] = 8;
                Storage.OracleQuoteType quoteType = Storage.OracleQuoteType.UNIT;
                readData = abi.encode(
                    circuitChainlink,
                    stalePeriods,
                    circuitChainIsMultiplied,
                    chainlinkDecimals,
                    quoteType
                );
            }
            bytes memory targetData;
            oracleConfig = abi.encode(
                Storage.OracleReadType.CHAINLINK_FEEDS,
                Storage.OracleReadType.STABLE,
                readData,
                targetData,
                abi.encode(uint80(5 * BPS), uint80(0), uint80(0))
            );
            oracleConfigUSDC = oracleConfig;
            transmuter.setOracle(USDC, oracleConfig);
        }

        // Set Collaterals
        CollateralSetupProd[] memory collaterals = new CollateralSetupProd[](2);

        // IB01
        {
            uint64[] memory xMintFeeIB01 = new uint64[](3);
            xMintFeeIB01[0] = uint64(0);
            xMintFeeIB01[1] = uint64((49 * BASE_9) / 100);
            xMintFeeIB01[2] = uint64((50 * BASE_9) / 100);

            int64[] memory yMintFeeIB01 = new int64[](3);
            yMintFeeIB01[0] = int64(0);
            yMintFeeIB01[1] = int64(0);
            yMintFeeIB01[2] = int64(uint64(MAX_MINT_FEE));

            uint64[] memory xBurnFeeIB01 = new uint64[](3);
            xBurnFeeIB01[0] = uint64(BASE_9);
            xBurnFeeIB01[1] = uint64((16 * BASE_9) / 100);
            xBurnFeeIB01[2] = uint64((15 * BASE_9) / 100);

            int64[] memory yBurnFeeIB01 = new int64[](3);
            yBurnFeeIB01[0] = int64(uint64((50 * BASE_9) / 10000));
            yBurnFeeIB01[1] = int64(uint64((50 * BASE_9) / 10000));
            yBurnFeeIB01[2] = int64(uint64(MAX_BURN_FEE));

            bytes memory oracleConfig;
            {
                bytes memory readData;
                {
                    AggregatorV3Interface[] memory circuitChainlink = new AggregatorV3Interface[](1);
                    uint32[] memory stalePeriods = new uint32[](1);
                    uint8[] memory circuitChainIsMultiplied = new uint8[](1);
                    uint8[] memory chainlinkDecimals = new uint8[](1);
                    // Chainlink IB01/USD oracle
                    circuitChainlink[0] = AggregatorV3Interface(0x32d1463EB53b73C095625719Afa544D5426354cB);
                    stalePeriods[0] = ((1 days) * 3) / 2;
                    circuitChainIsMultiplied[0] = 1;
                    chainlinkDecimals[0] = 8;
                    Storage.OracleQuoteType quoteType = Storage.OracleQuoteType.UNIT;
                    readData = abi.encode(
                        circuitChainlink,
                        stalePeriods,
                        circuitChainIsMultiplied,
                        chainlinkDecimals,
                        quoteType
                    );
                }

                // Current value is 109.43, but we need to update it now otherwise we'll have to wait for a week
                // before we can update it
                (, int256 answer, , , ) = AggregatorV3Interface(0x32d1463EB53b73C095625719Afa544D5426354cB)
                    .latestRoundData();
                uint256 initTarget = uint256(answer) * 1e10;
                bytes memory targetData = abi.encode(
                    initTarget,
                    uint96(DEVIATION_THRESHOLD_IB01),
                    uint96(block.timestamp),
                    HEARTBEAT
                );

                oracleConfig = abi.encode(
                    Storage.OracleReadType.CHAINLINK_FEEDS,
                    Storage.OracleReadType.MAX,
                    readData,
                    targetData,
                    abi.encode(USER_PROTECTION_IB01, FIREWALL_MINT_IB01, FIREWALL_BURN_RATIO_IB01)
                );
                oracleConfigIB01 = oracleConfig;
            }
            collaterals[0] = CollateralSetupProd(
                BIB01,
                oracleConfig,
                xMintFeeIB01,
                yMintFeeIB01,
                xBurnFeeIB01,
                yBurnFeeIB01
            );
        }

        // steakUSDC -> max oracle or target oracle
        {
            uint64[] memory xMintFeeSteak = new uint64[](3);
            xMintFeeSteak[0] = uint64(0);
            xMintFeeSteak[1] = uint64((79 * BASE_9) / 100);
            xMintFeeSteak[2] = uint64((80 * BASE_9) / 100);

            int64[] memory yMintFeeSteak = new int64[](3);
            yMintFeeSteak[0] = int64(uint64((5 * BASE_9) / 10000));
            yMintFeeSteak[1] = int64(uint64((5 * BASE_9) / 10000));
            yMintFeeSteak[2] = int64(uint64(MAX_MINT_FEE));

            uint64[] memory xBurnFeeSteak = new uint64[](3);
            xBurnFeeSteak[0] = uint64(BASE_9);
            xBurnFeeSteak[1] = uint64((31 * BASE_9) / 100);
            xBurnFeeSteak[2] = uint64((30 * BASE_9) / 100);

            int64[] memory yBurnFeeSteak = new int64[](3);
            yBurnFeeSteak[0] = int64(uint64((5 * BASE_9) / 10000));
            yBurnFeeSteak[1] = int64(uint64((5 * BASE_9) / 10000));
            yBurnFeeSteak[2] = int64(uint64(MAX_BURN_FEE));

            bytes memory oracleConfig;
            {
                bytes memory readData = abi.encode(0x025106374196586E8BC91eE8818dD7B0Efd2B78B, BASE_18);
                // Current price is 1.012534 -> we take a small margin
                bytes memory targetData = abi.encode(
                    1013000000000000000,
                    uint96(DEVIATION_THRESHOLD_STEAKUSDC),
                    uint96(block.timestamp),
                    HEARTBEAT
                );
                oracleConfig = abi.encode(
                    Storage.OracleReadType.MORPHO_ORACLE,
                    Storage.OracleReadType.MAX,
                    readData,
                    targetData,
                    abi.encode(USER_PROTECTION_STEAK_USDC, uint80(50 * BPS), FIREWALL_BURN_RATIO_STEAK_USDC)
                );
                oracleConfigSTEAK = oracleConfig;
            }
            collaterals[1] = CollateralSetupProd(
                STEAK_USDC,
                oracleConfig,
                xMintFeeSteak,
                yMintFeeSteak,
                xBurnFeeSteak,
                yBurnFeeSteak
            );
        }

        // Setup each collateral
        uint256 collateralsLength = collaterals.length;
        for (uint256 i; i < collateralsLength; i++) {
            CollateralSetupProd memory collateral = collaterals[i];
            transmuter.addCollateral(collateral.token);
            transmuter.setOracle(collateral.token, collateral.oracleConfig);
            // Mint fees
            transmuter.setFees(collateral.token, collateral.xMintFee, collateral.yMintFee, true);
            // Burn fees
            transmuter.setFees(collateral.token, collateral.xBurnFee, collateral.yBurnFee, false);
            transmuter.togglePause(collateral.token, Storage.ActionType.Mint);
            transmuter.togglePause(collateral.token, Storage.ActionType.Burn);
        }

        // Set whitelist status for bIB01
        bytes memory whitelistData = abi.encode(
            WhitelistType.BACKED,
            // Keyring whitelist check
            abi.encode(address(0x9391B14dB2d43687Ea1f6E546390ED4b20766c46))
        );
        transmuter.setWhitelistStatus(BIB01, 1, whitelistData);
        transmuter.toggleWhitelist(Storage.WhitelistType.BACKED, NEW_DEPLOYER);
        transmuter.toggleTrusted(NEW_DEPLOYER, Storage.TrustedType.Seller);
        transmuter.toggleTrusted(NEW_KEEPER, Storage.TrustedType.Seller);
        transmuter.toggleTrusted(DEPLOYER, Storage.TrustedType.Seller);
        IAgToken(treasuryUSDA).addMinter(address(FLASHLOAN));
        vm.stopPrank();

        // Setup rebalancer
        rebalancer = new RebalancerFlashloan(
            // Mock access control manager for
            IAccessControlManager(0x3fc5a1bd4d0A435c55374208A6A81535A1923039),
            transmuter,
            IERC4626(address(STEAK_USDC)),
            IERC3156FlashLender(address(FLASHLOAN))
        );

        // Setup flashloan
        // Core contract
        vm.startPrank(0x5bc6BEf80DA563EBf6Df6D6913513fa9A7ec89BE);
        FLASHLOAN.addStablecoinSupport(address(treasuryUSDA));
        vm.stopPrank();
        // Governor address
        vm.startPrank(0xdC4e6DFe07EFCa50a197DF15D9200883eF4Eb1c8);
        FLASHLOAN.setFlashLoanParameters(address(USDA), 0, type(uint256).max);
        vm.stopPrank();

        // Initialize Transmuter reserves
        deal(BIB01, NEW_DEPLOYER, 100000 * BASE_18);
        deal(STEAK_USDC, NEW_DEPLOYER, 1000000 * BASE_18);
        vm.startPrank(NEW_DEPLOYER);
        IERC20(BIB01).approve(address(transmuter), type(uint256).max);
        IERC20(STEAK_USDC).approve(address(transmuter), type(uint256).max);
        transmuter.swapExactOutput(
            1200 * BASE_18,
            type(uint256).max,
            BIB01,
            address(USDA),
            NEW_DEPLOYER,
            block.timestamp
        );
        transmuter.swapExactOutput(
            2400 * BASE_18,
            type(uint256).max,
            STEAK_USDC,
            address(USDA),
            NEW_DEPLOYER,
            block.timestamp
        );
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        GETTERS
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testUnit_RebalancerSetup() external {
        assertEq(address(transmuter.agToken()), 0x0000206329b97DB379d5E1Bf586BbDB969C63274);
        // Revert when no order has been setup
        vm.startPrank(NEW_DEPLOYER);
        vm.expectRevert();
        rebalancer.adjustYieldExposure(BASE_18, 1);

        vm.expectRevert();
        rebalancer.adjustYieldExposure(BASE_18, 0);
        vm.stopPrank();
    }

    function testFuzz_adjustYieldExposure_SuccessIncrease(uint256 amount) external {
        amount = bound(amount, BASE_18, BASE_18 * 100);
        deal(address(USDA), address(rebalancer), BASE_18 * 1000);
        (uint256 fromUSDC, uint256 total) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        vm.startPrank(DEPLOYER);
        rebalancer.setOrder(address(STEAK_USDC), address(USDC), BASE_18 * 500, 0);
        rebalancer.setOrder(address(USDC), address(STEAK_USDC), BASE_18 * 500, 0);

        uint256 budget = rebalancer.budget();
        (uint112 orderBudget0, , , ) = rebalancer.orders(address(USDC), address(STEAK_USDC));
        (uint112 orderBudget1, , , ) = rebalancer.orders(address(STEAK_USDC), address(USDC));
        rebalancer.adjustYieldExposure(amount, 1);

        vm.stopPrank();

        (uint256 fromUSDCPost, uint256 totalPost) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAKPost, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        assertLe(totalPost, total);
        assertEq(fromUSDCPost, fromUSDC - amount);
        assertLe(fromSTEAKPost, fromSTEAK + amount);
        assertGe(fromSTEAKPost, fromSTEAK);
        assertLe(rebalancer.budget(), budget);
        (uint112 newOrder0, , , ) = rebalancer.orders(address(USDC), address(STEAK_USDC));
        (uint112 newOrder1, , , ) = rebalancer.orders(address(STEAK_USDC), address(USDC));
        assertEq(newOrder0, orderBudget0);
        assertLe(newOrder1, orderBudget1);
    }

    function testFuzz_adjustYieldExposure_SuccessDecrease(uint256 amount) external {
        amount = bound(amount, BASE_18, BASE_18 * 100);
        deal(address(USDA), address(rebalancer), BASE_18 * 1000);
        (uint256 fromUSDC, uint256 total) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        vm.startPrank(DEPLOYER);
        rebalancer.setOrder(address(STEAK_USDC), address(USDC), BASE_18 * 500, 0);
        rebalancer.setOrder(address(USDC), address(STEAK_USDC), BASE_18 * 500, 0);
        uint256 budget = rebalancer.budget();
        (uint112 orderBudget0, , , ) = rebalancer.orders(address(USDC), address(STEAK_USDC));
        (uint112 orderBudget1, , , ) = rebalancer.orders(address(STEAK_USDC), address(USDC));
        rebalancer.adjustYieldExposure(amount, 0);
        vm.stopPrank();
        (uint256 fromUSDCPost, uint256 totalPost) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAKPost, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        assertLe(totalPost, total);
        assertLe(fromUSDCPost, fromUSDC + amount);
        assertGe(fromUSDCPost, fromUSDC);
        assertEq(fromSTEAKPost, fromSTEAK - amount);
        assertLe(rebalancer.budget(), budget);
        (uint112 newOrder0, , , ) = rebalancer.orders(address(USDC), address(STEAK_USDC));
        (uint112 newOrder1, , , ) = rebalancer.orders(address(STEAK_USDC), address(USDC));
        assertLe(newOrder0, orderBudget0);
        assertEq(newOrder1, orderBudget1);
    }

    function testFuzz_adjustYieldExposure_SuccessNoBudgetIncrease(uint256 amount) external {
        amount = bound(amount, BASE_18, BASE_18 * 100);
        deal(address(USDA), address(rebalancer), BASE_18 * 1000);
        (uint256 fromUSDC, uint256 total) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        vm.startPrank(DEPLOYER);
        uint64[] memory xMintFee = new uint64[](1);
        xMintFee[0] = uint64(0);
        int64[] memory yMintFee = new int64[](1);
        yMintFee[0] = int64(0);
        transmuter.setFees(STEAK_USDC, xMintFee, yMintFee, true);
        assertEq(rebalancer.budget(), 0);
        rebalancer.adjustYieldExposure(amount, 1);
        vm.stopPrank();
        (uint256 fromUSDCPost, uint256 totalPost) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAKPost, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        assertGe(totalPost, total);
        assertEq(fromUSDCPost, fromUSDC - amount);
        assertGe(fromSTEAKPost, fromSTEAK + amount);
    }

    function testFuzz_adjustYieldExposure_SuccessDecreaseSplit(uint256 amount, uint256 split) external {
        amount = bound(amount, BASE_18, BASE_18 * 100);
        split = bound(split, BASE_9 / 4, (BASE_9 * 3) / 4);
        deal(address(USDA), address(rebalancer), BASE_18 * 1000);
        (uint256 fromUSDC, uint256 total) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        vm.startPrank(DEPLOYER);
        rebalancer.setOrder(address(STEAK_USDC), address(USDC), BASE_18 * 500, 0);
        rebalancer.setOrder(address(USDC), address(STEAK_USDC), BASE_18 * 500, 0);
        uint256 budget = rebalancer.budget();
        (uint112 orderBudget0, , , ) = rebalancer.orders(address(USDC), address(STEAK_USDC));
        (uint112 orderBudget1, , , ) = rebalancer.orders(address(STEAK_USDC), address(USDC));

        rebalancer.adjustYieldExposure((amount * split) / BASE_9, 0);

        (uint256 fromUSDCPost, uint256 totalPost) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAKPost, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        assertLe(totalPost, total);
        assertLe(fromUSDCPost, fromUSDC + (amount * split) / BASE_9);
        assertGe(fromUSDCPost, fromUSDC);
        assertEq(fromSTEAKPost, fromSTEAK - (amount * split) / BASE_9);
        assertLe(rebalancer.budget(), budget);

        rebalancer.adjustYieldExposure(amount - (amount * split) / BASE_9, 0);

        (fromUSDCPost, totalPost) = transmuter.getIssuedByCollateral(address(USDC));
        (fromSTEAKPost, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        assertLe(totalPost, total);
        assertLe(fromUSDCPost, fromUSDC + amount);
        assertGe(fromUSDCPost, fromUSDC);
        assertEq(fromSTEAKPost, fromSTEAK - amount);
        assertLe(rebalancer.budget(), budget);
        (uint112 newOrder0, , , ) = rebalancer.orders(address(USDC), address(STEAK_USDC));
        (uint112 newOrder1, , , ) = rebalancer.orders(address(STEAK_USDC), address(USDC));
        assertLe(newOrder0, orderBudget0);
        assertEq(newOrder1, orderBudget1);

        vm.stopPrank();
    }

    function testFuzz_adjustYieldExposure_SuccessIncreaseSplit(uint256 amount, uint256 split) external {
        amount = bound(amount, BASE_18, BASE_18 * 100);
        split = bound(split, BASE_9 / 4, (BASE_9 * 3) / 4);
        deal(address(USDA), address(rebalancer), BASE_18 * 1000);
        (uint256 fromUSDC, uint256 total) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        vm.startPrank(DEPLOYER);
        rebalancer.setOrder(address(STEAK_USDC), address(USDC), BASE_18 * 500, 0);
        rebalancer.setOrder(address(USDC), address(STEAK_USDC), BASE_18 * 500, 0);
        uint256 budget = rebalancer.budget();
        (uint112 orderBudget0, , , ) = rebalancer.orders(address(USDC), address(STEAK_USDC));
        (uint112 orderBudget1, , , ) = rebalancer.orders(address(STEAK_USDC), address(USDC));

        rebalancer.adjustYieldExposure((amount * split) / BASE_9, 1);

        (uint256 fromUSDCPost, uint256 totalPost) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAKPost, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        assertLe(totalPost, total);
        assertEq(fromUSDCPost, fromUSDC - (amount * split) / BASE_9);
        assertLe(fromSTEAKPost, fromSTEAK + (amount * split) / BASE_9);
        assertGe(fromSTEAKPost, fromSTEAK);
        assertLe(rebalancer.budget(), budget);

        rebalancer.adjustYieldExposure(amount - (amount * split) / BASE_9, 1);

        (fromUSDCPost, totalPost) = transmuter.getIssuedByCollateral(address(USDC));
        (fromSTEAKPost, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        assertLe(totalPost, total);
        assertEq(fromUSDCPost, fromUSDC - amount);
        assertLe(fromSTEAKPost, fromSTEAK + amount);
        assertGe(fromSTEAKPost, fromSTEAK);
        assertLe(rebalancer.budget(), budget);
        (uint112 newOrder0, , , ) = rebalancer.orders(address(USDC), address(STEAK_USDC));
        (uint112 newOrder1, , , ) = rebalancer.orders(address(STEAK_USDC), address(USDC));
        assertEq(newOrder0, orderBudget0);
        assertLe(newOrder1, orderBudget1);

        vm.stopPrank();
    }

    function testFuzz_adjustYieldExposure_SuccessAltern(uint256 amount) external {
        amount = bound(amount, BASE_18, BASE_18 * 100);
        deal(address(USDA), address(rebalancer), BASE_18 * 1000);
        (uint256 fromUSDC, uint256 total) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAK, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        vm.startPrank(DEPLOYER);
        rebalancer.setOrder(address(STEAK_USDC), address(USDC), BASE_18 * 500, 0);
        rebalancer.setOrder(address(USDC), address(STEAK_USDC), BASE_18 * 500, 0);
        uint256 budget = rebalancer.budget();
        (uint112 orderBudget0, , , ) = rebalancer.orders(address(USDC), address(STEAK_USDC));
        (uint112 orderBudget1, , , ) = rebalancer.orders(address(STEAK_USDC), address(USDC));

        rebalancer.adjustYieldExposure(amount, 1);

        (uint256 fromUSDCPost, uint256 totalPost) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAKPost, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));
        assertLe(totalPost, total);
        assertEq(fromUSDCPost, fromUSDC - amount);
        assertLe(fromSTEAKPost, fromSTEAK + amount);
        assertGe(fromSTEAKPost, fromSTEAK);
        assertLe(rebalancer.budget(), budget);
        (uint112 newOrder0, , , ) = rebalancer.orders(address(USDC), address(STEAK_USDC));
        (uint112 newOrder1, , , ) = rebalancer.orders(address(STEAK_USDC), address(USDC));
        assertEq(newOrder0, orderBudget0);
        assertLe(newOrder1, orderBudget1);

        rebalancer.adjustYieldExposure(amount, 0);

        (orderBudget0, , , ) = rebalancer.orders(address(USDC), address(STEAK_USDC));
        (orderBudget1, , , ) = rebalancer.orders(address(STEAK_USDC), address(USDC));
        assertLe(orderBudget0, newOrder0);
        assertEq(orderBudget1, newOrder1);

        (uint256 fromUSDCPost2, uint256 totalPost2) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromSTEAKPost2, ) = transmuter.getIssuedByCollateral(address(STEAK_USDC));

        assertLe(totalPost2, totalPost);
        assertLe(fromUSDCPost2, fromUSDC);
        assertLe(fromSTEAKPost2, fromSTEAK);
        assertLe(fromSTEAKPost2, fromSTEAKPost);
        assertGe(fromUSDCPost2, fromUSDCPost);
        assertLe(rebalancer.budget(), budget);

        vm.stopPrank();
    }
}
