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

            bytes memory readData;
            bytes memory oracleConfig = abi.encode(
                Storage.OracleReadType.NO_ORACLE,
                Storage.OracleTargetType.STABLE,
                readData
            );
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
            yMintFeeC3M[0] = int64(uint64((BASE_9) / 1000));
            yMintFeeC3M[1] = int64(uint64(BASE_9 / 1000));
            yMintFeeC3M[2] = int64(uint64(MAX_MINT_FEE));

            uint64[] memory xBurnFeeC3M = new uint64[](3);
            xBurnFeeC3M[0] = uint64(BASE_9);
            xBurnFeeC3M[1] = uint64((20 * BASE_9) / 100);
            xBurnFeeC3M[2] = uint64((21 * BASE_9) / 100);

            int64[] memory yBurnFeeC3M = new int64[](3);
            yBurnFeeC3M[0] = int64(uint64((5 * BASE_9) / 1000));
            yBurnFeeC3M[1] = int64(uint64((5 * BASE_9) / 1000));
            yBurnFeeC3M[2] = int64(uint64(MAX_BURN_FEE));

            bytes memory readData;
            bytes memory oracleConfig = abi.encode(
                Storage.OracleReadType.NO_ORACLE,
                Storage.OracleTargetType.STABLE,
                readData
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
        ts.normalizer = uint128(BASE_27);
        ts.agToken = IAgToken(_agToken);

        // Setup each collaterals
        for (uint256 i; i < collaterals.length; i++) {
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
    }
}
