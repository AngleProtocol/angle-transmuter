// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { Utils } from "./utils/Utils.s.sol";
import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
import "stringutils/strings.sol";
import "./Constants.s.sol";

import "contracts/transmuter/Storage.sol" as Storage;
import { ITransmuter } from "interfaces/ITransmuter.sol";
import "interfaces/external/chainlink/AggregatorV3Interface.sol";
import "interfaces/external/IERC4626.sol";
import "interfaces/IAgToken.sol";

import { CollateralSetupProd } from "contracts/transmuter/configs/ProductionTypes.sol";

contract SetupDeployedTransmuter is Utils {
    function run() external {
        uint256 deployerPrivateKey = vm.deriveKey(vm.envString("MNEMONIC_MAINNET"), "m/44'/60'/0'/0/", 0);
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Address: %s", deployer);
        console.log(deployer.balance);
        vm.startBroadcast(deployerPrivateKey);

        ITransmuter usdaTransmuter = ITransmuter(0x222222fD79264BBE280b4986F6FEfBC3524d0137);
        IAgToken treasuryUSDA = IAgToken(0x8667DBEBf68B0BFa6Db54f550f41Be16c4067d60);
        console.log(address(usdaTransmuter));

        // TODO Run this script after facet upgrade script otherwise it won't work due to oracles calibrated
        // in a different manner

        // For USDC, we just need to update the oracle as the fees have already been properly set for this use case

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
                abi.encode(uint128(5 * BPS), uint128(0))
            );
            usdaTransmuter.setOracle(USDC, oracleConfig);
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

                (, int256 answer, , , ) = AggregatorV3Interface(0x32d1463EB53b73C095625719Afa544D5426354cB)
                    .latestRoundData();
                uint256 initTarget = uint256(answer) * 1e10;
                bytes memory targetData = abi.encode(initTarget);

                oracleConfig = abi.encode(
                    Storage.OracleReadType.CHAINLINK_FEEDS,
                    Storage.OracleReadType.MAX,
                    readData,
                    targetData,
                    abi.encode(USER_PROTECTION_IB01, FIREWALL_BURN_RATIO_IB01)
                );
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
                uint256 startPrice = IERC4626(STEAK_USDC).previewRedeem(1e30);
                bytes memory targetData = abi.encode(startPrice);
                oracleConfig = abi.encode(
                    Storage.OracleReadType.MORPHO_ORACLE,
                    Storage.OracleReadType.MAX,
                    readData,
                    targetData,
                    abi.encode(USER_PROTECTION_STEAK_USDC, FIREWALL_BURN_RATIO_STEAK_USDC)
                );
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
            usdaTransmuter.addCollateral(collateral.token);
            usdaTransmuter.setOracle(collateral.token, collateral.oracleConfig);
            // Mint fees
            usdaTransmuter.setFees(collateral.token, collateral.xMintFee, collateral.yMintFee, true);
            // Burn fees
            usdaTransmuter.setFees(collateral.token, collateral.xBurnFee, collateral.yBurnFee, false);
            usdaTransmuter.togglePause(collateral.token, Storage.ActionType.Mint);
            usdaTransmuter.togglePause(collateral.token, Storage.ActionType.Burn);
        }

        // Set whitelist status for bIB01
        bytes memory whitelistData = abi.encode(
            Storage.WhitelistType.BACKED,
            abi.encode(address(0x9391B14dB2d43687Ea1f6E546390ED4b20766c46))
        );
        usdaTransmuter.setWhitelistStatus(BIB01, 1, whitelistData);

        usdaTransmuter.toggleTrusted(NEW_DEPLOYER, Storage.TrustedType.Seller);
        usdaTransmuter.toggleTrusted(NEW_KEEPER, Storage.TrustedType.Seller);

        // Add minter the flashloan contract on Ethereum
        treasuryUSDA.addMinter(0x4A2FF9bC686A0A23DA13B6194C69939189506F7F);

        console.log("Transmuter setup");
        vm.stopBroadcast();
    }
}
