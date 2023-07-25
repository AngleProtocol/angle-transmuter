// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { Utils } from "../Utils.s.sol";
import { console } from "forge-std/console.sol";
import { ITransmuter } from "interfaces/ITransmuter.sol";
import "stringutils/strings.sol";
import "../Constants.s.sol";
import "contracts/transmuter/Storage.sol" as Storage;

import { console } from "forge-std/console.sol";

contract CheckTransmuter is Utils {
    using strings for *;

    // TODO: replace with deployed Transmuter address
    ITransmuter public constant transmuter = ITransmuter(0xa85EffB2658CFd81e0B1AaD4f2364CdBCd89F3a1);

    function run() external {
        /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        FEE STRUCTURE                                                  
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

        address[] memory collaterals = new address[](2);
        collaterals[0] = EUROC;
        collaterals[1] = BC3M;

        // Checks all valid selectors are here
        bytes4[] memory selectors = _generateSelectors("ITransmuter");
        console.log("Num selectors: ", selectors.length);
        for (uint i = 0; i < selectors.length; ++i) {
            assertEq(transmuter.isValidSelector(selectors[i]), true);
        }

        assertEq(address(transmuter.accessControlManager()), address(CORE_BORROW));
        assertEq(address(transmuter.agToken()), address(AGEUR));
        assertEq(transmuter.getCollateralList(), collaterals);
        assertEq(transmuter.getCollateralDecimals(EUROC), 6);
        assertEq(transmuter.getCollateralDecimals(BC3M), 18);

        {
            address collat = EUROC;
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
            (uint64[] memory xRealFeeMint, int64[] memory yRealFeeMint) = transmuter.getCollateralMintFees(collat);
            _assertArrayUint64(xRealFeeMint, xMintFeeEuroc);
            _assertArrayInt64(yRealFeeMint, yMintFeeEuroc);
            (uint64[] memory xRealFeeBurn, int64[] memory yRealFeeBurn) = transmuter.getCollateralBurnFees(collat);
            _assertArrayUint64(xRealFeeBurn, xBurnFeeEuroc);
            _assertArrayInt64(yRealFeeBurn, yBurnFeeEuroc);
        }

        {
            address collat = BC3M;
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
            xBurnFeeC3M[1] = uint64((21 * BASE_9) / 100);
            xBurnFeeC3M[2] = uint64((20 * BASE_9) / 100);

            int64[] memory yBurnFeeC3M = new int64[](3);
            yBurnFeeC3M[0] = int64(uint64((5 * BASE_9) / 1000));
            yBurnFeeC3M[1] = int64(uint64((5 * BASE_9) / 1000));
            yBurnFeeC3M[2] = int64(uint64(MAX_BURN_FEE));
            (uint64[] memory xRealFeeMint, int64[] memory yRealFeeMint) = transmuter.getCollateralMintFees(collat);
            _assertArrayUint64(xRealFeeMint, xMintFeeC3M);
            _assertArrayInt64(yRealFeeMint, yMintFeeC3M);
            (uint64[] memory xRealFeeBurn, int64[] memory yRealFeeBurn) = transmuter.getCollateralBurnFees(collat);
            _assertArrayUint64(xRealFeeBurn, xBurnFeeC3M);
            _assertArrayInt64(yRealFeeBurn, yBurnFeeC3M);
        }
        {
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

            (uint64[] memory xRedemptionCurve, int64[] memory yRedemptionCurve) = transmuter.getRedemptionFees();
            _assertArrayUint64(xRedemptionCurve, xRedeemFee);
            _assertArrayInt64(yRedemptionCurve, yRedeemFee);
        }

        /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         PAUSE                                                      
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

        assertEq(transmuter.isPaused(EUROC, Storage.ActionType.Mint), false);
        assertEq(transmuter.isPaused(EUROC, Storage.ActionType.Burn), false);
        assertEq(transmuter.isPaused(EUROC, Storage.ActionType.Redeem), false);

        assertEq(transmuter.isPaused(BC3M, Storage.ActionType.Mint), false);
        assertEq(transmuter.isPaused(BC3M, Storage.ActionType.Burn), false);
        assertEq(transmuter.isPaused(BC3M, Storage.ActionType.Redeem), false);

        /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        ORACLES                                                     
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/
        {
            address collat = EUROC;
            (uint256 mint, uint256 burn, uint256 ratio, uint256 minRatio, uint256 redemption) = transmuter
                .getOracleValues(collat);
            console.log("EUROC oracle values");
            console.log(mint, burn, ratio);
            console.log(minRatio, redemption);
        }

        {
            address collat = BC3M;
            (uint256 mint, uint256 burn, uint256 ratio, uint256 minRatio, uint256 redemption) = transmuter
                .getOracleValues(collat);
            console.log("BC3M oracle values");
            console.log(mint, burn, ratio);
            console.log(minRatio, redemption);
        }

        /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                  STABLECOINS MINTED                                                
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

        (uint64 collatRatio, uint256 stablecoinsIssued) = transmuter.getCollateralRatio();
        assertEq(stablecoinsIssued, 13043780000000000000000000);
        assertEq(collatRatio, 0);

        /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                   WHITELIST STATUS                                                 
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

        assert(transmuter.isWhitelistedCollateral(BC3M));
        bytes memory whitelistData = abi.encode(Storage.WhitelistType.BACKED, abi.encode(address(0)));
        assertEq(transmuter.getCollateralWhitelistData(BC3M), whitelistData);
        // Choosing a random address here
        assert(!transmuter.isWhitelistedForCollateral(BC3M, EUROC));
    }
}
