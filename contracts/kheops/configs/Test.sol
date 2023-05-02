// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import { Storage as s } from "../libraries/Storage.sol";
import { Setters } from "../libraries/Setters.sol";
import { Oracle } from "../libraries/Oracle.sol";
import "../../utils/Constants.sol";
import "../../interfaces/external/chainlink/AggregatorV3Interface.sol";

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
        CollateralSetup calldata eur_A,
        CollateralSetup calldata eur_B,
        CollateralSetup calldata eur_Y
    ) external {
        Setters.setAccessControlManager(_accessControlManager);

        KheopsStorage storage ks = s.kheopsStorage();
        ks.normalizer = BASE_27;
        ks.agToken = IAgToken(_agToken);

        // Setup first collateral
        Setters.addCollateral(eur_A.collateral);
        AggregatorV3Interface[] memory circuitChainlink = new AggregatorV3Interface[](1);
        uint32[] memory stalePeriods = new uint32[](1);
        uint8[] memory circuitChainIsMultiplied = new uint8[](1);
        uint8[] memory chainlinkDecimals = new uint8[](1);
        circuitChainlink[0] = AggregatorV3Interface(eur_A.oracle);
        stalePeriods[0] = 1 hours;
        circuitChainIsMultiplied[0] = 1;
        chainlinkDecimals[0] = 8;
        bytes memory readData = abi.encode(circuitChainlink, stalePeriods, circuitChainIsMultiplied, chainlinkDecimals);
        Setters.setOracle(
            eur_A.collateral,
            abi.encode(OracleReadType.CHAINLINK_FEEDS, OracleQuoteType.UNIT, OracleTargetType.STABLE, readData),
            ""
        );

        // Fees
        uint64[] memory xMintFee = new uint64[](4);
        xMintFee[0] = uint64(0);
        xMintFee[1] = uint64((40 * BASE_9) / 100);
        xMintFee[2] = uint64((45 * BASE_9) / 100);
        xMintFee[3] = uint64(BASE_9);

        // Linear at 1%, 3% at 45%, then steep to 100%
        int64[] memory yMintFee = new int64[](3);
        yMintFee[0] = int64(uint64(BASE_9 / 100));
        yMintFee[1] = int64(uint64(BASE_9 / 100));
        yMintFee[2] = int64(uint64((3 * BASE_9) / 100));
        yMintFee[3] = int64(uint64(BASE_9));

        Setters.setFees(eur_A.collateral, xMintFee, yMintFee, true);

        uint64[] memory xBurnFee = new uint64[](4);
        xBurnFee[0] = uint64(BASE_9);
        xBurnFee[1] = uint64((40 * BASE_9) / 100);
        xBurnFee[2] = uint64((35 * BASE_9) / 100);
        xBurnFee[3] = uint64(0);

        // Linear at 1%, 3% at 35%, then steep to 100%
        int64[] memory yBurnFee = new int64[](3);
        yBurnFee[0] = int64(uint64(BASE_9 / 100));
        yBurnFee[1] = int64(uint64(BASE_9 / 100));
        yBurnFee[2] = int64(uint64((3 * BASE_9) / 100));
        yBurnFee[3] = int64(uint64(BASE_9));

        Setters.setFees(eur_A.collateral, xBurnFee, yBurnFee, false);

        // Unpause
        Setters.togglePause(eur_A.collateral, PauseType.Mint);
        Setters.togglePause(eur_A.collateral, PauseType.Burn);

        Setters.togglePause(eur_A.collateral, PauseType.Redeem);
    }
}
