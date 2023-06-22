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
contract Production {
    function initialize(IAccessControlManager _accessControlManager, address _agToken) external {
        address euroc = 0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c;
        address euroe = 0x820802Fa8a99901F52e39acD21177b0BE6EE2974;
        address eure = 0x3231Cb76718CDeF2155FC47b5286d82e6eDA273f;

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

        CollateralSetupProd[] memory collaterals = new CollateralSetupProd[](3);

        // EUROC
        {
            bytes memory readData;
            bytes memory oracleConfig = abi.encode(
                Storage.OracleReadType.NO_ORACLE,
                Storage.OracleTargetType.STABLE,
                readData
            );
            collaterals[0] = CollateralSetupProd(euroc, oracleConfig, xMintFee, yMintFee, xBurnFee, yBurnFee);
        }

        // EUROe
        {
            bytes memory readData;
            bytes memory oracleConfig = abi.encode(
                Storage.OracleReadType.NO_ORACLE,
                Storage.OracleTargetType.STABLE,
                readData
            );
            collaterals[1] = CollateralSetupProd(euroe, oracleConfig, xMintFee, yMintFee, xBurnFee, yBurnFee);
        }

        // EURe
        {
            bytes memory readData;
            bytes memory oracleConfig = abi.encode(
                Storage.OracleReadType.NO_ORACLE,
                Storage.OracleTargetType.STABLE,
                readData
            );
            collaterals[2] = CollateralSetupProd(eure, oracleConfig, xMintFee, yMintFee, xBurnFee, yBurnFee);
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
        }
    }
}
