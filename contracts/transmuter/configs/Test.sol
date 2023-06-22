// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import "interfaces/external/chainlink/AggregatorV3Interface.sol";

import "../libraries/LibOracle.sol";
import { LibSetters } from "../libraries/LibSetters.sol";
import { LibStorage as s } from "../libraries/LibStorage.sol";

import "../../utils/Constants.sol";
import "../Storage.sol";

struct CollateralSetup {
    address collateral;
    address oracle;
}

/// @dev This contract is used only once to initialize the diamond proxy.
contract Test {
    function initialize(
        IAccessControlManager _accessControlManager,
        address _agToken,
        CollateralSetup calldata eurA,
        CollateralSetup calldata eurB,
        CollateralSetup calldata eurY
    ) external {
        LibSetters.setAccessControlManager(_accessControlManager);

        TransmuterStorage storage ts = s.transmuterStorage();
        ts.normalizer = uint128(BASE_27);
        ts.agToken = IAgToken(_agToken);

        // Setup first collateral
        LibSetters.addCollateral(eurA.collateral);
        AggregatorV3Interface[] memory circuitChainlink = new AggregatorV3Interface[](1);
        uint32[] memory stalePeriods = new uint32[](1);
        uint8[] memory circuitChainIsMultiplied = new uint8[](1);
        uint8[] memory chainlinkDecimals = new uint8[](1);
        circuitChainlink[0] = AggregatorV3Interface(eurA.oracle);
        stalePeriods[0] = 1 hours;
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
        LibSetters.setOracle(
            eurA.collateral,
            abi.encode(OracleReadType.CHAINLINK_FEEDS, OracleTargetType.STABLE, readData)
        );

        // Fees
        uint64[] memory xMintFee = new uint64[](4);
        xMintFee[0] = uint64(0);
        xMintFee[1] = uint64((40 * BASE_9) / 100);
        xMintFee[2] = uint64((45 * BASE_9) / 100);
        xMintFee[3] = uint64((70 * BASE_9) / 100);

        // Linear at 1%, 3% at 45%, then steep to 100%
        int64[] memory yMintFee = new int64[](4);
        yMintFee[0] = int64(uint64(BASE_9 / 99));
        yMintFee[1] = int64(uint64(BASE_9 / 99));
        yMintFee[2] = int64(uint64((3 * BASE_9) / 97));
        yMintFee[3] = int64(uint64(BASE_12 - 1));

        LibSetters.setFees(eurA.collateral, xMintFee, yMintFee, true);
        LibSetters.togglePause(eurA.collateral, ActionType.Mint);

        uint64[] memory xBurnFee = new uint64[](4);
        xBurnFee[0] = uint64(BASE_9);
        xBurnFee[1] = uint64((40 * BASE_9) / 100);
        xBurnFee[2] = uint64((35 * BASE_9) / 100);
        xBurnFee[3] = uint64(BASE_9 / 100);

        // Linear at 1%, 3% at 35%, then steep to 100%
        int64[] memory yBurnFee = new int64[](4);
        yBurnFee[0] = int64(uint64(BASE_9 / 99));
        yBurnFee[1] = int64(uint64(BASE_9 / 99));
        yBurnFee[2] = int64(uint64((3 * BASE_9) / 97));
        yBurnFee[3] = int64(uint64(MAX_BURN_FEE - 1));

        LibSetters.setFees(eurA.collateral, xBurnFee, yBurnFee, false);
        LibSetters.togglePause(eurA.collateral, ActionType.Burn);

        // Setup second collateral
        LibSetters.addCollateral(eurB.collateral);
        circuitChainlink = new AggregatorV3Interface[](1);
        stalePeriods = new uint32[](1);
        circuitChainIsMultiplied = new uint8[](1);
        chainlinkDecimals = new uint8[](1);
        circuitChainlink[0] = AggregatorV3Interface(eurB.oracle);
        stalePeriods[0] = 1 hours;
        circuitChainIsMultiplied[0] = 1;
        chainlinkDecimals[0] = 8;
        quoteType = OracleQuoteType.UNIT;
        readData = abi.encode(circuitChainlink, stalePeriods, circuitChainIsMultiplied, chainlinkDecimals, quoteType);
        LibSetters.setOracle(
            eurB.collateral,
            abi.encode(OracleReadType.CHAINLINK_FEEDS, OracleTargetType.STABLE, readData)
        );

        // Fees
        xMintFee = new uint64[](4);
        xMintFee[0] = uint64(0);
        xMintFee[1] = uint64((40 * BASE_9) / 100);
        xMintFee[2] = uint64((42 * BASE_9) / 100);
        xMintFee[3] = uint64((70 * BASE_9) / 100);

        // Linear at 1%, 5% at 42%, then steep to 100%
        yMintFee = new int64[](4);
        yMintFee[0] = int64(uint64(BASE_9 / 100));
        yMintFee[1] = int64(uint64(BASE_9 / 100));
        yMintFee[2] = int64(uint64((5 * BASE_9) / 100));
        yMintFee[3] = int64(uint64(BASE_12 - 1));

        LibSetters.setFees(eurB.collateral, xMintFee, yMintFee, true);
        LibSetters.togglePause(eurB.collateral, ActionType.Mint);

        xBurnFee = new uint64[](4);
        xBurnFee[0] = uint64(BASE_9);
        xBurnFee[1] = uint64((40 * BASE_9) / 100);
        xBurnFee[2] = uint64((37 * BASE_9) / 100);
        xBurnFee[3] = uint64(BASE_9 / 100);

        // Linear at 1%, 5% at 37%, then steep to 100%
        yBurnFee = new int64[](4);
        yBurnFee[0] = int64(uint64(BASE_9 / 100));
        yBurnFee[1] = int64(uint64(BASE_9 / 100));
        yBurnFee[2] = int64(uint64((5 * BASE_9) / 100));
        yBurnFee[3] = int64(uint64(MAX_BURN_FEE - 1));

        LibSetters.setFees(eurB.collateral, xBurnFee, yBurnFee, false);
        LibSetters.togglePause(eurB.collateral, ActionType.Burn);

        // Setup third collateral
        LibSetters.addCollateral(eurY.collateral);
        circuitChainlink = new AggregatorV3Interface[](1);
        stalePeriods = new uint32[](1);
        circuitChainIsMultiplied = new uint8[](1);
        chainlinkDecimals = new uint8[](1);
        circuitChainlink[0] = AggregatorV3Interface(eurY.oracle);
        stalePeriods[0] = 1 hours;
        circuitChainIsMultiplied[0] = 1;
        chainlinkDecimals[0] = 8;
        quoteType = OracleQuoteType.UNIT;
        readData = abi.encode(circuitChainlink, stalePeriods, circuitChainIsMultiplied, chainlinkDecimals, quoteType);
        LibSetters.setOracle(
            eurY.collateral,
            abi.encode(OracleReadType.CHAINLINK_FEEDS, OracleTargetType.STABLE, readData)
        );

        // Fees
        xMintFee = new uint64[](4);
        xMintFee[0] = uint64(0);
        xMintFee[1] = uint64((40 * BASE_9) / 100);
        xMintFee[2] = uint64((42 * BASE_9) / 100);
        xMintFee[3] = uint64((70 * BASE_9) / 100);

        // Linear at 1%, 5% at 42%, then steep to 100%
        yMintFee = new int64[](4);
        yMintFee[0] = int64(uint64(BASE_9 / 100));
        yMintFee[1] = int64(uint64(BASE_9 / 100));
        yMintFee[2] = int64(uint64((5 * BASE_9) / 100));
        yMintFee[3] = int64(uint64(BASE_12 - 1));

        LibSetters.setFees(eurY.collateral, xMintFee, yMintFee, true);
        LibSetters.togglePause(eurY.collateral, ActionType.Mint);

        xBurnFee = new uint64[](4);
        xBurnFee[0] = uint64(BASE_9);
        xBurnFee[1] = uint64((40 * BASE_9) / 100);
        xBurnFee[2] = uint64((37 * BASE_9) / 100);
        xBurnFee[3] = uint64(BASE_9 / 100);

        // Linear at 1%, 5% at 37%, then steep to 100%
        yBurnFee = new int64[](4);
        yBurnFee[0] = int64(uint64(BASE_9 / 100));
        yBurnFee[1] = int64(uint64(BASE_9 / 100));
        yBurnFee[2] = int64(uint64((5 * BASE_9) / 100));
        yBurnFee[3] = int64(uint64(MAX_BURN_FEE - 1));

        LibSetters.setFees(eurY.collateral, xBurnFee, yBurnFee, false);
        LibSetters.togglePause(eurY.collateral, ActionType.Burn);

        // Redeem
        LibSetters.togglePause(eurA.collateral, ActionType.Redeem);
    }
}
