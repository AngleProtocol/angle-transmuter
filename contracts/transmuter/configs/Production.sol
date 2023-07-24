// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import "interfaces/external/chainlink/AggregatorV3Interface.sol";

import { LibDiamondEtherscan } from "../libraries/LibDiamondEtherscan.sol";
import "../libraries/LibOracle.sol";
import { LibSetters } from "../libraries/LibSetters.sol";
import { LibStorage as s } from "../libraries/LibStorage.sol";

import { DummyDiamondImplementation } from "../../../scripts/generated/DummyDiamondImplementation.sol";

import "../../utils/Constants.sol";
import "../Storage.sol" as Storage;

struct CollateralSetupProd {
    address token;
    bytes oracleConfig;
    uint64[] xMintFee;
    int64[] yMintFee;
    uint64[] xBurnFee;
    int64[] yBurnFee;
}

/// @dev This contract is used only once to initialize the diamond proxy.
contract Production {
    function initialize(
        IAccessControlManager _accessControlManager,
        address _agToken,
        address dummyImplementation
    ) external {
        address euroc = 0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c;
        address bc3m = 0x2F123cF3F37CE3328CC9B5b8415f9EC5109b45e7;

        // Check this docs for simulations:
        // https://docs.google.com/spreadsheets/d/1UxS1m4sG8j2Lv02wONYJNkF4S7NDLv-5iyAzFAFTfXw/edit#gid=0

        // Set Collaterals
        CollateralSetupProd[] memory collaterals = new CollateralSetupProd[](2);

        // EUROC
        {
            uint64[] memory xMintFeeEuroc = new uint64[](3);
            xMintFeeEuroc[0] = uint64(0);
            xMintFeeEuroc[1] = uint64((79 * BASE_9) / 100);
            xMintFeeEuroc[2] = uint64((80 * BASE_9) / 100);

            int64[] memory yMintFeeEuroc = new int64[](3);
            yMintFeeEuroc[0] = int64(uint64(BASE_9 / 1000));
            yMintFeeEuroc[1] = int64(uint64(BASE_9 / 1000));
            yMintFeeEuroc[2] = int64(uint64(MAX_MINT_FEE));

            uint64[] memory xBurnFeeEuroc = new uint64[](3);
            xBurnFeeEuroc[0] = uint64(BASE_9);
            xBurnFeeEuroc[1] = uint64((41 * BASE_9) / 100);
            xBurnFeeEuroc[2] = uint64((40 * BASE_9) / 100);

            int64[] memory yBurnFeeEuroc = new int64[](3);
            yBurnFeeEuroc[0] = int64(uint64((2 * BASE_9) / 1000));
            yBurnFeeEuroc[1] = int64(uint64((2 * BASE_9) / 1000));
            yBurnFeeEuroc[2] = int64(uint64(MAX_BURN_FEE));

            bytes memory oracleConfig;
            {
                // Pyth oracle for EUROC
                bytes32[] memory feedIds = new bytes32[](2);
                uint32[] memory stalePeriods = new uint32[](2);
                uint8[] memory isMultiplied = new uint8[](2);
                // pyth address
                address pyth = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6;
                // EUROC/USD
                feedIds[0] = 0xd052e6f54fe29355d6a3c06592fdefe49fae7840df6d8655bf6d6bfb789b56e4;
                // USD/EUR
                feedIds[1] = 0xa995d00bb36a63cef7fd2c287dc105fc8f3d93779f062f09551b0af3e81ec30b;
                stalePeriods[0] = 3 days;
                stalePeriods[1] = 3 days;
                isMultiplied[0] = 1;
                isMultiplied[1] = 0;
                OracleQuoteType quoteType = OracleQuoteType.UNIT;
                bytes memory readData = abi.encode(pyth, feedIds, stalePeriods, isMultiplied, quoteType);
                bytes memory targetData;
                oracleConfig = abi.encode(
                    Storage.OracleReadType.PYTH,
                    Storage.OracleReadType.STABLE,
                    readData,
                    targetData
                );
            }
            collaterals[0] = CollateralSetupProd(
                euroc,
                oracleConfig,
                xMintFeeEuroc,
                yMintFeeEuroc,
                xBurnFeeEuroc,
                yBurnFeeEuroc
            );
        }

        // bC3M
        {
            uint64[] memory xMintFeeC3M = new uint64[](3);
            xMintFeeC3M[0] = uint64(0);
            xMintFeeC3M[1] = uint64((59 * BASE_9) / 100);
            xMintFeeC3M[2] = uint64((60 * BASE_9) / 100);

            int64[] memory yMintFeeC3M = new int64[](3);
            yMintFeeC3M[0] = int64(uint64(BASE_9 / 1000));
            yMintFeeC3M[1] = int64(uint64(BASE_9 / 1000));
            yMintFeeC3M[2] = int64(uint64(MAX_MINT_FEE));

            uint64[] memory xBurnFeeC3M = new uint64[](3);
            xBurnFeeC3M[0] = uint64(BASE_9);
            xBurnFeeC3M[1] = uint64((21 * BASE_9) / 100);
            xBurnFeeC3M[2] = uint64((20 * BASE_9) / 100);

            int64[] memory yBurnFeeC3M = new int64[](3);
            yBurnFeeC3M[0] = int64(uint64((5 * BASE_9) / 1000));
            yBurnFeeC3M[1] = int64(uint64((5 * BASE_9) / 1000));
            yBurnFeeC3M[2] = int64(uint64(MAX_BURN_FEE));

            AggregatorV3Interface[] memory circuitChainlink = new AggregatorV3Interface[](1);
            uint32[] memory stalePeriods = new uint32[](1);
            uint8[] memory circuitChainIsMultiplied = new uint8[](1);
            uint8[] memory chainlinkDecimals = new uint8[](1);

            // bC3M: Redstone as a current price (more accurate for redemptions), and Backed as a target

            // Redstone C3M Oracle
            circuitChainlink[0] = AggregatorV3Interface(0x6E27A25999B3C665E44D903B2139F5a4Be2B6C26);
            stalePeriods[0] = 72 hours;
            circuitChainIsMultiplied[0] = 1;
            chainlinkDecimals[0] = 8;
            OracleQuoteType quoteType = OracleQuoteType.UNIT;
            bytes memory readData = abi.encode(
                circuitChainlink,
                stalePeriods,
                circuitChainIsMultiplied,
                chainlinkDecimals,
                quoteType
            );

            // Backed C3M Oracle
            circuitChainlink[0] = AggregatorV3Interface(0x83Ec02059F686E747392A22ddfED7833bA0d7cE3);
            bytes memory targetData = abi.encode(
                circuitChainlink,
                stalePeriods,
                circuitChainIsMultiplied,
                chainlinkDecimals,
                quoteType
            );
            bytes memory oracleConfig = abi.encode(
                Storage.OracleReadType.CHAINLINK_FEEDS,
                Storage.OracleReadType.CHAINLINK_FEEDS,
                readData,
                targetData
            );

            collaterals[1] = CollateralSetupProd(
                bc3m,
                oracleConfig,
                xMintFeeC3M,
                yMintFeeC3M,
                xBurnFeeC3M,
                yBurnFeeC3M
            );
        }

        LibSetters.setAccessControlManager(_accessControlManager);

        TransmuterStorage storage ts = s.transmuterStorage();
        ts.statusReentrant = NOT_ENTERED;
        ts.normalizer = uint128(BASE_27);
        ts.agToken = IAgToken(_agToken);

        // Setup each collateral
        uint256 collateralsLength = collaterals.length;
        for (uint256 i; i < collateralsLength; i++) {
            CollateralSetupProd memory collateral = collaterals[i];
            LibSetters.addCollateral(collateral.token);
            LibSetters.setOracle(collateral.token, collateral.oracleConfig);
            // Mint fees
            LibSetters.setFees(collateral.token, collateral.xMintFee, collateral.yMintFee, true);
            // Burn fees
            LibSetters.setFees(collateral.token, collateral.xBurnFee, collateral.yBurnFee, false);
            LibSetters.togglePause(collateral.token, ActionType.Mint);
            LibSetters.togglePause(collateral.token, ActionType.Burn);
        }

        // adjustStablecoins
        LibSetters.adjustStablecoins(euroc, 8851136430000000000000000, true);
        LibSetters.adjustStablecoins(bc3m, 4192643570000000000000000, true);

        // setRedemptionCurveParams
        LibSetters.togglePause(euroc, ActionType.Redeem);
        uint64[] memory xRedeemFee = new uint64[](4);
        xRedeemFee[0] = uint64((75 * BASE_9) / 100);
        xRedeemFee[1] = uint64((85 * BASE_9) / 100);
        xRedeemFee[2] = uint64((95 * BASE_9) / 100);
        xRedeemFee[3] = uint64((97 * BASE_9) / 100);

        int64[] memory yRedeemFee = new int64[](4);
        yRedeemFee[0] = int64(uint64((995 * BASE_9) / 1000));
        yRedeemFee[1] = int64(uint64((950 * BASE_9) / 1000));
        yRedeemFee[2] = int64(uint64((950 * BASE_9) / 1000));
        yRedeemFee[3] = int64(uint64((995 * BASE_9) / 1000));
        LibSetters.setRedemptionCurveParams(xRedeemFee, yRedeemFee);

        // setDummyImplementation
        LibDiamondEtherscan.setDummyImplementation(dummyImplementation);
    }
}
