// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import "interfaces/external/chainlink/AggregatorV3Interface.sol";

import "../libraries/LibOracle.sol";
import { LibSetters } from "../libraries/LibSetters.sol";
import { LibStorage as s } from "../libraries/LibStorage.sol";

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
contract FakeGnosis {
    function initialize(
        IAccessControlManager _accessControlManager,
        address _agToken,
        address[] memory _collateralAddresses,
        address[] memory _oracleAddresses
    ) external {
        // Fee structure

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

        // Set Collaterals

        CollateralSetupProd[] memory collaterals = new CollateralSetupProd[](_collateralAddresses.length);

        for (uint256 i; i < _collateralAddresses.length; i++) {
            AggregatorV3Interface[] memory circuitChainlink = new AggregatorV3Interface[](1);
            bytes memory readData;
            {
                uint32[] memory stalePeriods = new uint32[](1);
                uint8[] memory circuitChainIsMultiplied = new uint8[](1);
                uint8[] memory chainlinkDecimals = new uint8[](1);
                circuitChainlink[0] = AggregatorV3Interface(_oracleAddresses[i]);
                stalePeriods[0] = 7 days;
                circuitChainIsMultiplied[0] = 1;
                chainlinkDecimals[0] = 8;
                OracleQuoteType quoteType = OracleQuoteType.UNIT;
                readData = abi.encode(
                    circuitChainlink,
                    stalePeriods,
                    circuitChainIsMultiplied,
                    chainlinkDecimals,
                    quoteType
                );
            }
            bytes memory targetData;
            bytes memory oracleConfig = abi.encode(
                Storage.OracleReadType.CHAINLINK_FEEDS,
                Storage.OracleReadType.STABLE,
                readData,
                targetData
            );
            collaterals[i] = CollateralSetupProd(
                _collateralAddresses[i],
                oracleConfig,
                xMintFee,
                yMintFee,
                xBurnFee,
                yBurnFee
            );
        }

        LibSetters.setAccessControlManager(_accessControlManager);

        TransmuterStorage storage ts = s.transmuterStorage();
        ts.normalizer = uint128(BASE_27);
        ts.agToken = IAgToken(_agToken);

        // Setup each collaterals
        for (uint256 i; i < collaterals.length; i++) {
            CollateralSetupProd memory collateral = collaterals[i];
            LibSetters.addCollateral(collateral.token);
            LibSetters.setOracle(collateral.token, collateral.oracleConfig);
            //Mint fees
            LibSetters.setFees(collateral.token, collateral.xMintFee, collateral.yMintFee, true);
            //Burn fees
            LibSetters.setFees(collateral.token, collateral.xBurnFee, collateral.yBurnFee, false);
            // togglePause
            LibSetters.togglePause(collateral.token, Storage.ActionType.Mint);
            LibSetters.togglePause(collateral.token, Storage.ActionType.Burn);
        }
    }
}
