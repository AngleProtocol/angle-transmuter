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
import { MockMorphoOracle } from "../mock/MockMorphoOracle.sol";
import { IAgToken } from "interfaces/IAgToken.sol";

import { IFlashAngle } from "borrow/interfaces/IFlashAngle.sol";

interface OldTransmuter {
    function getOracle(
        address
    ) external view returns (Storage.OracleReadType, Storage.OracleReadType, bytes memory, bytes memory);
}

contract UpdateTransmuterFacetsUSDATest is Helpers, Test {
    using stdJson for string;

    uint256 public CHAIN_SOURCE;

    string[] replaceFacetNames;
    string[] addFacetNames;
    address[] facetAddressList;
    address[] addFacetAddressList;

    ITransmuter transmuter;
    IERC20 USDA;
    IAgToken TreasuryUSDA;
    IFlashAngle FLASHLOAN;
    address governor;
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
        TreasuryUSDA = IAgToken(0x8667DBEBf68B0BFa6Db54f550f41Be16c4067d60);

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
            (, , , , uint256 redemptionPrice) = transmuter.getOracleValues(address(USDC));
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
            yMintFeeSteak[0] = int64(0);
            yMintFeeSteak[1] = int64(0);
            yMintFeeSteak[2] = int64(uint64(MAX_MINT_FEE));

            uint64[] memory xBurnFeeSteak = new uint64[](3);
            xBurnFeeSteak[0] = uint64(BASE_9);
            xBurnFeeSteak[1] = uint64((31 * BASE_9) / 100);
            xBurnFeeSteak[2] = uint64((30 * BASE_9) / 100);

            int64[] memory yBurnFeeSteak = new int64[](3);
            yBurnFeeSteak[0] = int64(0);
            yBurnFeeSteak[1] = int64(0);
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
                    abi.encode(USER_PROTECTION_STEAK_USDC, FIREWALL_MINT_STEAK_USDC, FIREWALL_BURN_RATIO_STEAK_USDC)
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
        transmuter.toggleWhitelist(Storage.WhitelistType.BACKED, WHALE_USDA);
        transmuter.toggleTrusted(NEW_DEPLOYER, Storage.TrustedType.Seller);
        transmuter.toggleTrusted(NEW_KEEPER, Storage.TrustedType.Seller);

        IAgToken(TreasuryUSDA).addMinter(address(FLASHLOAN));
        vm.stopPrank();

        // Setup rebalancer

        // Setup flashloan

        vm.startPrank(governor);
        FLASHLOAN = 
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        GETTERS
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testUnit_UpgradeUSDA_AgToken() external {
        assertEq(address(transmuter.agToken()), 0x0000206329b97DB379d5E1Bf586BbDB969C63274);
    }

    function testUnit_UpgradeUSDA_GetCollateralList() external {
        address[] memory collateralList = transmuter.getCollateralList();
        assertEq(collateralList.length, 3);
        assertEq(collateralList[0], address(USDC));
        assertEq(collateralList[1], address(BIB01));
        assertEq(collateralList[2], address(STEAK_USDC));
    }

    function testUnit_UpgradeUSDA_GetCollateralInfo() external {
        {
            Storage.Collateral memory collatInfoUSDC = transmuter.getCollateralInfo(address(USDC));
            assertEq(collatInfoUSDC.isManaged, 0);
            assertEq(collatInfoUSDC.isMintLive, 1);
            assertEq(collatInfoUSDC.isBurnLive, 1);
            assertEq(collatInfoUSDC.decimals, 6);
            assertEq(collatInfoUSDC.onlyWhitelisted, 0);
            assertEq(collatInfoUSDC.oracleConfig, oracleConfigUSDC);
            assertEq(collatInfoUSDC.whitelistData.length, 0);
            assertEq(collatInfoUSDC.managerData.subCollaterals.length, 0);
            assertEq(collatInfoUSDC.managerData.config.length, 0);

            {
                assertEq(collatInfoUSDC.xFeeMint.length, 1);
                assertEq(collatInfoUSDC.yFeeMint.length, 1);
                assertEq(collatInfoUSDC.xFeeMint[0], 0);
                assertEq(collatInfoUSDC.yFeeMint[0], 0);
            }
            {
                assertEq(collatInfoUSDC.xFeeBurn.length, 1);
                assertEq(collatInfoUSDC.yFeeBurn.length, 1);
                assertEq(collatInfoUSDC.xFeeBurn[0], 1000000000);
                assertEq(collatInfoUSDC.yFeeBurn[0], 0);
            }
        }

        {
            Storage.Collateral memory collatInfoIB01 = transmuter.getCollateralInfo(address(BIB01));
            assertEq(collatInfoIB01.isManaged, 0);
            assertEq(collatInfoIB01.isMintLive, 1);
            assertEq(collatInfoIB01.isBurnLive, 1);
            assertEq(collatInfoIB01.decimals, 18);
            assertEq(collatInfoIB01.onlyWhitelisted, 1);
            assertEq(collatInfoIB01.oracleConfig, oracleConfigIB01);
            {
                (Storage.WhitelistType whitelist, bytes memory data) = abi.decode(
                    collatInfoIB01.whitelistData,
                    (Storage.WhitelistType, bytes)
                );
                address keyringGuard = abi.decode(data, (address));
                assertEq(uint8(whitelist), uint8(Storage.WhitelistType.BACKED));
                assertEq(keyringGuard, 0x4954c61984180868495D1a7Fb193b05a2cbd9dE3);
            }
            assertEq(collatInfoIB01.managerData.subCollaterals.length, 0);
            assertEq(collatInfoIB01.managerData.config.length, 0);

            {
                assertEq(collatInfoIB01.xFeeMint.length, 3);
                assertEq(collatInfoIB01.yFeeMint.length, 3);
                assertEq(collatInfoIB01.xFeeMint[0], 0);
                assertEq(collatInfoIB01.xFeeMint[1], 490000000);
                assertEq(collatInfoIB01.xFeeMint[2], 500000000);
                assertEq(collatInfoIB01.yFeeMint[0], 0);
                assertEq(collatInfoIB01.yFeeMint[1], 0);
                assertEq(collatInfoIB01.yFeeMint[2], 999999999999);
            }
            {
                assertEq(collatInfoIB01.xFeeBurn.length, 3);
                assertEq(collatInfoIB01.yFeeBurn.length, 3);
                assertEq(collatInfoIB01.xFeeBurn[0], 1000000000);
                assertEq(collatInfoIB01.xFeeBurn[1], 160000000);
                assertEq(collatInfoIB01.xFeeBurn[2], 150000000);
                assertEq(collatInfoIB01.yFeeBurn[0], 5000000);
                assertEq(collatInfoIB01.yFeeBurn[1], 5000000);
                assertEq(collatInfoIB01.yFeeBurn[2], 999000000);
            }
        }

        {
            Storage.Collateral memory collatInfoSTEAK = transmuter.getCollateralInfo(address(STEAK_USDC));
            assertEq(collatInfoSTEAK.isManaged, 0);
            assertEq(collatInfoSTEAK.isMintLive, 1);
            assertEq(collatInfoSTEAK.isBurnLive, 1);
            assertEq(collatInfoSTEAK.decimals, 18);
            assertEq(collatInfoSTEAK.onlyWhitelisted, 0);
            assertEq(collatInfoSTEAK.oracleConfig, oracleConfigSTEAK);
            assertEq(collatInfoSTEAK.managerData.subCollaterals.length, 0);
            assertEq(collatInfoSTEAK.managerData.config.length, 0);

            {
                assertEq(collatInfoSTEAK.xFeeMint.length, 3);
                assertEq(collatInfoSTEAK.yFeeMint.length, 3);
                assertEq(collatInfoSTEAK.xFeeMint[0], 0);
                assertEq(collatInfoSTEAK.xFeeMint[1], 790000000);
                assertEq(collatInfoSTEAK.xFeeMint[2], 800000000);
                assertEq(collatInfoSTEAK.yFeeMint[0], 0);
                assertEq(collatInfoSTEAK.yFeeMint[1], 0);
                assertEq(collatInfoSTEAK.yFeeMint[2], 999999999999);
            }
            {
                assertEq(collatInfoSTEAK.xFeeBurn.length, 3);
                assertEq(collatInfoSTEAK.yFeeBurn.length, 3);
                assertEq(collatInfoSTEAK.xFeeBurn[0], 1000000000);
                assertEq(collatInfoSTEAK.yFeeBurn[0], 0);
                assertEq(collatInfoSTEAK.xFeeBurn[1], 310000000);
                assertEq(collatInfoSTEAK.yFeeBurn[1], 0);
                assertEq(collatInfoSTEAK.xFeeBurn[2], 300000000);
                assertEq(collatInfoSTEAK.yFeeBurn[2], 999000000);
            }
        }
    }

    function testUnit_UpgradeUSDA_GetCollateralDecimals() external {
        assertEq(transmuter.getCollateralDecimals(address(USDC)), 6);
        assertEq(transmuter.getCollateralDecimals(address(STEAK_USDC)), 18);
        assertEq(transmuter.getCollateralDecimals(address(BIB01)), 18);
    }

    function testUnit_UpgradeUSDA_GetCollateralRatio() external {
        (uint64 collatRatio, uint256 stablecoinIssued) = transmuter.getCollateralRatio();

        assertApproxEqRel(collatRatio, 1000173196, BPS * 100);
        assertApproxEqRel(stablecoinIssued, 1199993347000000000000, 100 * BPS);
    }

    function testUnit_UpgradeUSDA_isTrusted() external {
        assertEq(transmuter.isTrusted(address(governor)), false);
        assertEq(transmuter.isTrustedSeller(address(governor)), false);
        assertEq(transmuter.isTrusted(DEPLOYER), false);
        assertEq(transmuter.isTrustedSeller(DEPLOYER), false);
        assertEq(transmuter.isTrusted(NEW_DEPLOYER), false);
        assertEq(transmuter.isTrustedSeller(NEW_DEPLOYER), true);
        assertEq(transmuter.isTrusted(KEEPER), false);
        assertEq(transmuter.isTrustedSeller(KEEPER), false);
        assertEq(transmuter.isTrusted(NEW_KEEPER), false);
        assertEq(transmuter.isTrustedSeller(NEW_KEEPER), true);
    }

    function testUnit_UpgradeUSDA_IsWhitelistedForCollateral() external {
        assertEq(transmuter.isWhitelistedForCollateral(address(USDC), alice), true);
        assertEq(transmuter.isWhitelistedForCollateral(address(BIB01), alice), false);
        assertEq(transmuter.isWhitelistedForCollateral(address(STEAK_USDC), alice), true);
        vm.startPrank(governor);
        transmuter.toggleWhitelist(Storage.WhitelistType.BACKED, alice);
        vm.stopPrank();
        assertEq(transmuter.isWhitelistedForCollateral(address(BIB01), alice), true);
        assertEq(transmuter.isWhitelistedForCollateral(address(BIB01), WHALE_USDA), true);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        ORACLE
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testUnit_UpgradeUSDA_getOracleValues_Success() external {
        _checkOracleValues(address(USDC), BASE_18, USER_PROTECTION_USDC, FIREWALL_MINT_USDC, FIREWALL_BURN_RATIO_USDC);
        _checkOracleValues(
            address(BIB01),
            109480000000000000000,
            USER_PROTECTION_IB01,
            FIREWALL_MINT_IB01,
            FIREWALL_BURN_RATIO_IB01
        );
        _checkOracleValues(
            address(STEAK_USDC),
            1013000000000000000,
            USER_PROTECTION_STEAK_USDC,
            FIREWALL_MINT_STEAK_USDC,
            FIREWALL_BURN_RATIO_STEAK_USDC
        );
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         MINT
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_UpgradeUSDA_QuoteMintExactInput_Reflexivity(uint256 amountIn, uint256 fromToken) public {
        fromToken = bound(fromToken, 0, transmuter.getCollateralList().length - 1);
        address collateral = transmuter.getCollateralList()[fromToken];
        amountIn = bound(amountIn, BASE_6, collateral != USDC ? 1000 * BASE_18 : BASE_6 * 1e6);

        uint256 amountStable = transmuter.quoteIn(amountIn, collateral, address(USDA));
        uint256 amountInReflexive = transmuter.quoteOut(amountStable, collateral, address(USDA));
        assertApproxEqRel(amountIn, amountInReflexive, BPS * 10);
    }

    function testFuzz_UpgradeUSDA_QuoteMintExactInput_Independent(
        uint256 amountIn,
        uint256 splitProportion,
        uint256 fromToken
    ) public {
        fromToken = bound(fromToken, 0, transmuter.getCollateralList().length - 1);
        address collateral = transmuter.getCollateralList()[fromToken];
        amountIn = bound(amountIn, BASE_6, collateral != USDC ? 1000 * BASE_18 : BASE_6 * 1e6);
        splitProportion = bound(splitProportion, 0, BASE_9);

        uint256 amountStable = transmuter.quoteIn(amountIn, collateral, address(USDA));
        uint256 amountInSplit1 = (amountIn * splitProportion) / BASE_9;
        amountInSplit1 = amountInSplit1 == 0 ? 1 : amountInSplit1;
        uint256 amountStableSplit1 = transmuter.quoteIn(amountInSplit1, collateral, address(USDA));
        // do the swap to update the system
        _mintExactInput(alice, collateral, amountInSplit1, amountStableSplit1);
        uint256 amountStableSplit2 = transmuter.quoteIn(amountIn - amountInSplit1, collateral, address(USDA));
        assertApproxEqRel(amountStableSplit1 + amountStableSplit2, amountStable, BPS * 10);
    }

    function testFuzz_UpgradeUSDA_MintExactOutput(uint256 stableAmount, uint256 fromToken) public {
        fromToken = bound(fromToken, 0, transmuter.getCollateralList().length - 1);
        address collateral = transmuter.getCollateralList()[fromToken];
        stableAmount = bound(stableAmount, BASE_18, BASE_6 * 1e18);

        uint256 prevBalanceStable = USDA.balanceOf(alice);
        uint256 prevTransmuterCollat = IERC20(collateral).balanceOf(address(transmuter));
        uint256 prevAgTokenSupply = IERC20(USDA).totalSupply();
        (uint256 prevStableAmountCollat, uint256 prevStableAmount) = transmuter.getIssuedByCollateral(collateral);

        uint256 amountIn = transmuter.quoteOut(stableAmount, collateral, address(USDA));
        if (amountIn == 0 || stableAmount == 0) return;
        _mintExactOutput(alice, collateral, stableAmount, amountIn);

        uint256 balanceStable = USDA.balanceOf(alice);

        assertEq(balanceStable, prevBalanceStable + stableAmount);
        assertEq(USDA.totalSupply(), prevAgTokenSupply + stableAmount);
        assertEq(IERC20(collateral).balanceOf(alice), 0);
        assertEq(IERC20(collateral).balanceOf(address(transmuter)), prevTransmuterCollat + amountIn);

        (uint256 newStableAmountCollat, uint256 newStableAmount) = transmuter.getIssuedByCollateral(collateral);

        assertApproxEqAbs(newStableAmountCollat, prevStableAmountCollat + stableAmount, 1 wei);
        assertApproxEqAbs(newStableAmount, prevStableAmount + stableAmount, 1 wei);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         BURN
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_UpgradeUSDA_QuoteBurnExactInput_Independent(
        uint256 amountStable,
        uint256 splitProportion
    ) public {
        amountStable = bound(amountStable, 1, BASE_6);
        splitProportion = bound(splitProportion, 0, BASE_9);

        uint256 amountOut = transmuter.quoteIn(amountStable, address(USDA), USDC);
        uint256 amountStableSplit1 = (amountStable * splitProportion) / BASE_9;
        amountStableSplit1 = amountStableSplit1 == 0 ? 1 : amountStableSplit1;
        uint256 amountOutSplit1 = transmuter.quoteIn(amountStableSplit1, address(USDA), USDC);
        // do the swap to update the system
        _burnExactInput(WHALE_USDA, USDC, amountStableSplit1, amountOutSplit1);
        uint256 amountOutSplit2 = transmuter.quoteIn(amountStable - amountStableSplit1, address(USDA), USDC);
        assertApproxEqRel(amountOutSplit1 + amountOutSplit2, amountOut, BPS * 10);
    }

    function testFuzz_UpgradeUSDA_BurnExactOutput(uint256 amountOut) public {
        amountOut = bound(amountOut, 1, BASE_6);

        uint256 prevBalanceStable = USDA.balanceOf(WHALE_USDA);
        uint256 prevBalanceUSDC = IERC20(USDC).balanceOf(WHALE_USDA);
        uint256 prevTransmuterCollat = IERC20(USDC).balanceOf(address(transmuter));
        uint256 prevAgTokenSupply = IERC20(USDA).totalSupply();
        (uint256 prevStableAmountCollat, uint256 prevStableAmount) = transmuter.getIssuedByCollateral(USDC);

        uint256 stableAmount = transmuter.quoteOut(amountOut, address(USDA), USDC);
        if (amountOut == 0 || stableAmount == 0) return;
        _burnExactOutput(WHALE_USDA, USDC, amountOut, stableAmount);

        uint256 balanceStable = USDA.balanceOf(WHALE_USDA);

        assertEq(balanceStable, prevBalanceStable - stableAmount);
        assertEq(USDA.totalSupply(), prevAgTokenSupply - stableAmount);
        assertEq(IERC20(USDC).balanceOf(WHALE_USDA), amountOut + prevBalanceUSDC);
        assertEq(IERC20(USDC).balanceOf(address(transmuter)), prevTransmuterCollat - amountOut);

        (uint256 newStableAmountCollat, uint256 newStableAmount) = transmuter.getIssuedByCollateral(USDC);

        assertApproxEqAbs(newStableAmountCollat, prevStableAmountCollat - stableAmount, 1 wei);
        assertApproxEqAbs(newStableAmount, prevStableAmount - stableAmount, 1 wei);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         UTILS
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _mintExactOutput(
        address owner,
        address tokenIn,
        uint256 amountStable,
        uint256 estimatedAmountIn
    ) internal {
        vm.startPrank(owner);
        deal(tokenIn, owner, estimatedAmountIn);
        IERC20(tokenIn).approve(address(transmuter), type(uint256).max);
        transmuter.swapExactOutput(amountStable, estimatedAmountIn, tokenIn, address(USDA), owner, block.timestamp * 2);
        vm.stopPrank();
    }

    function _mintExactInput(address owner, address tokenIn, uint256 amountIn, uint256 estimatedStable) internal {
        vm.startPrank(owner);
        deal(tokenIn, owner, amountIn);
        IERC20(tokenIn).approve(address(transmuter), type(uint256).max);
        transmuter.swapExactInput(amountIn, estimatedStable, tokenIn, address(USDA), owner, block.timestamp * 2);
        vm.stopPrank();
    }

    function _burnExactInput(
        address owner,
        address tokenOut,
        uint256 amountStable,
        uint256 estimatedAmountOut
    ) internal returns (bool burnMoreThanHad) {
        // we need to increase the balance because fees are negative and we need to transfer
        // more than what we received with the mint
        if (IERC20(tokenOut).balanceOf(address(transmuter)) < estimatedAmountOut) {
            deal(tokenOut, address(transmuter), estimatedAmountOut);
            burnMoreThanHad = true;
        }

        vm.startPrank(owner);
        transmuter.swapExactInput(amountStable, estimatedAmountOut, address(USDA), tokenOut, owner, 0);
        vm.stopPrank();
    }

    function _burnExactOutput(
        address owner,
        address tokenOut,
        uint256 amountOut,
        uint256 estimatedStable
    ) internal returns (bool) {
        // _logIssuedCollateral();
        vm.startPrank(owner);
        (uint256 maxAmount, ) = transmuter.getIssuedByCollateral(tokenOut);
        uint256 balanceStableOwner = USDA.balanceOf(owner);
        if (estimatedStable > maxAmount) vm.expectRevert();
        else if (estimatedStable > balanceStableOwner) vm.expectRevert("ERC20: burn amount exceeds balance");
        transmuter.swapExactOutput(amountOut, estimatedStable, address(USDA), tokenOut, owner, block.timestamp * 2);
        if (amountOut > maxAmount) return false;
        vm.stopPrank();
        return true;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        CHECKS
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _checkOracleValues(
        address collateral,
        uint256 targetValue,
        uint80 userProtection,
        uint80 firewallMint,
        uint80 firewallBurn
    ) internal {
        (uint256 mint, uint256 burn, uint256 ratio, uint256 minRatio, uint256 redemption) = transmuter.getOracleValues(
            collateral
        );
        assertApproxEqRel(targetValue, redemption, 200 * BPS);

        if (
            targetValue * (BASE_18 - userProtection) < redemption * BASE_18 &&
            redemption * BASE_18 < targetValue * (BASE_18 + userProtection)
        ) assertEq(burn, targetValue);
        else assertEq(burn, redemption);

        if (
            targetValue * (BASE_18 - userProtection) < redemption * BASE_18 &&
            redemption * BASE_18 < targetValue * (BASE_18 + userProtection)
        ) {
            assertEq(mint, targetValue);
            assertEq(ratio, BASE_18);
        } else if (redemption * BASE_18 > targetValue * (BASE_18 + firewallMint)) {
            assertEq(mint, targetValue);
            assertEq(ratio, BASE_18);
        } else if (redemption * BASE_18 < targetValue * (BASE_18 - firewallBurn)) {
            assertEq(mint, redemption);
            assertEq(ratio, (redemption * BASE_18) / targetValue);
        } else {
            assertEq(mint, redemption);
            assertEq(ratio, BASE_18);
        }
    }
}
