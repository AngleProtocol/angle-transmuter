// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { StdAssertions } from "forge-std/Test.sol";
import { ITransmuter } from "interfaces/ITransmuter.sol";
import "stringutils/strings.sol";
import "../Constants.s.sol";
import "contracts/transmuter/Storage.sol" as Storage;

contract CheckTransmuter is Script, StdAssertions {
    using strings for *;

    ITransmuter public constant transmuter = ITransmuter(0xd1df48175CAC7409abfF7d267A2c6bBc010dD19b);

    function run() external {
        /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        FEE STRUCTURE                                                  
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

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

        // not set yet
        uint64[] memory xRedeemFee = new uint64[](0);
        int64[] memory yRedeemFee = new int64[](0);

        address[] memory collaterals = new address[](3);
        collaterals[0] = EUROC;
        collaterals[1] = EUROE;
        collaterals[2] = EURE;

        // Checks all valid selectors are here
        bytes4[] memory selectors = _generateSelectors("ITransmuter");
        for (uint i = 0; i < selectors.length; ++i) {
            assertEq(transmuter.isValidSelector(selectors[i]), true);
        }
        assertEq(address(transmuter.accessControlManager()), address(CORE_BORROW));
        assertEq(address(transmuter.agToken()), address(AGEUR));
        assertEq(transmuter.getCollateralList(), collaterals);
        assertEq(transmuter.getCollateralDecimals(EUROC), 6);
        assertEq(transmuter.getCollateralDecimals(EUROE), 6);
        assertEq(transmuter.getCollateralDecimals(EURE), 18);
        {
            address collat = EUROC;
            (uint64[] memory xRealFeeMint, int64[] memory yRealFeeMint) = transmuter.getCollateralMintFees(collat);
            _assertArrayUint64(xRealFeeMint, xMintFee);
            _assertArrayInt64(yRealFeeMint, yMintFee);
            (uint64[] memory xRealFeeBurn, int64[] memory yRealFeeBurn) = transmuter.getCollateralBurnFees(collat);
            _assertArrayUint64(xRealFeeBurn, xBurnFee);
            _assertArrayInt64(yRealFeeBurn, yBurnFee);
        }
        (uint64[] memory xRedemptionCurve, int64[] memory yRedemptionCurve) = transmuter.getRedemptionFees();
        _assertArrayUint64(xRedemptionCurve, xRedeemFee);
        _assertArrayInt64(yRedemptionCurve, yRedeemFee);

        /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         PAUSE                                                      
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

        assertEq(transmuter.isPaused(EUROC, Storage.ActionType.Mint), true);
        assertEq(transmuter.isPaused(EUROC, Storage.ActionType.Burn), true);
        assertEq(transmuter.isPaused(EUROC, Storage.ActionType.Redeem), true);

        assertEq(transmuter.isPaused(EUROE, Storage.ActionType.Mint), true);
        assertEq(transmuter.isPaused(EUROE, Storage.ActionType.Burn), true);
        assertEq(transmuter.isPaused(EUROE, Storage.ActionType.Redeem), true);

        assertEq(transmuter.isPaused(EURE, Storage.ActionType.Mint), true);
        assertEq(transmuter.isPaused(EURE, Storage.ActionType.Burn), true);
        assertEq(transmuter.isPaused(EURE, Storage.ActionType.Redeem), true);

        /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        ORACLES                                                     
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/
        {
            address collat = EUROC;
            (uint256 mint, uint256 burn, uint256 ratio, uint256 redemption) = transmuter.getOracleValues(collat);
            assertEq(mint, BASE_18);
            assertEq(burn, BASE_18);
            assertEq(ratio, BASE_18);
            assertEq(redemption, BASE_18);
        }

        {
            address collat = EUROE;
            (uint256 mint, uint256 burn, uint256 ratio, uint256 redemption) = transmuter.getOracleValues(collat);
            assertEq(mint, BASE_18);
            assertEq(burn, BASE_18);
            assertEq(ratio, BASE_18);
            assertEq(redemption, BASE_18);
        }

        {
            address collat = EURE;
            (uint256 mint, uint256 burn, uint256 ratio, uint256 redemption) = transmuter.getOracleValues(collat);
            assertEq(mint, BASE_18);
            assertEq(burn, BASE_18);
            assertEq(ratio, BASE_18);
            assertEq(redemption, BASE_18);
        }

        /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                  STABLECOINS MINTED                                                
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

        (uint64 collatRatio, uint256 stablecoinsIssued) = transmuter.getCollateralRatio();
        assertEq(stablecoinsIssued, 0);
        assertEq(collatRatio, type(uint64).max);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        HELPERS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    // return array of function selectors for given facet name
    function _generateSelectors(string memory _facetName) internal returns (bytes4[] memory selectors) {
        //get string of contract methods
        string[] memory cmd = new string[](4);
        cmd[0] = "forge";
        cmd[1] = "inspect";
        cmd[2] = _facetName;
        cmd[3] = "methods";
        bytes memory res = vm.ffi(cmd);
        string memory st = string(res);

        // extract function signatures and take first 4 bytes of keccak
        strings.slice memory s = st.toSlice();
        strings.slice memory delim = ":".toSlice();
        strings.slice memory delim2 = ",".toSlice();
        selectors = new bytes4[]((s.count(delim)));
        for (uint i = 0; i < selectors.length; ++i) {
            s.split('"'.toSlice());
            selectors[i] = bytes4(s.split(delim).until('"'.toSlice()).keccak());
            s.split(delim2);
        }
        return selectors;
    }

    function _assertArrayUint64(uint64[] memory _a, uint64[] memory _b) internal {
        assertEq(_a.length, _b.length);
        for (uint i = 0; i < _a.length; ++i) {
            assertEq(_a[i], _b[i]);
        }
    }

    function _assertArrayInt64(int64[] memory _a, int64[] memory _b) internal {
        assertEq(_a.length, _b.length);
        for (uint i = 0; i < _a.length; ++i) {
            assertEq(_a[i], _b[i]);
        }
    }
}
