// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Storage as s } from "./Storage.sol";
import { Utils } from "../utils/Utils.sol";
import { Oracle } from "./Oracle.sol";
import "../Storage.sol";
import "../../utils/Constants.sol";
import "../../utils/Errors.sol";

library Setters {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function setAccessControlManager(IAccessControlManager _newAccessControlManager) internal {
        DiamondStorage storage ds = s.diamondStorage();
        IAccessControlManager previousAccessControlManager = ds.accessControlManager;
        ds.accessControlManager = _newAccessControlManager;
        emit OwnershipTransferred(address(previousAccessControlManager), address(_newAccessControlManager));
    }

    function addCollateral(address collateral) internal {
        KheopsStorage storage ks = s.kheopsStorage();
        Collateral storage collatInfo = ks.collaterals[collateral];
        if (collatInfo.decimals != 0) revert AlreadyAdded();
        collatInfo.decimals = uint8(IERC20Metadata(collateral).decimals());
        ks.collateralList.push(collateral);
    }

    function setOracle(address collateral, bytes memory oracleConfig, bytes memory oracleStorage) internal {
        KheopsStorage storage ks = s.kheopsStorage();
        Collateral storage collatInfo = ks.collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        Oracle.readMint(oracleConfig, oracleStorage); // Checks oracle validity
        collatInfo.oracleConfig = oracleConfig;
        collatInfo.oracleStorage = oracleStorage;
    }

    function setFees(address collateral, uint64[] memory xFee, int64[] memory yFee, bool mint) internal {
        KheopsStorage storage ks = s.kheopsStorage();
        Collateral storage collatInfo = ks.collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        uint8 setter;
        if (!mint) setter = 1;
        checkFees(xFee, yFee, setter);
        if (mint) {
            collatInfo.xFeeMint = xFee;
            collatInfo.yFeeMint = yFee;
        } else {
            collatInfo.xFeeBurn = xFee;
            collatInfo.yFeeBurn = yFee;
        }
    }

    function togglePause(address collateral, PauseType pausedType) internal {
        if (pausedType == PauseType.Mint || pausedType == PauseType.Burn) {
            Collateral storage collatInfo = s.kheopsStorage().collaterals[collateral];
            if (collatInfo.decimals == 0) revert NotCollateral();
            if (pausedType == PauseType.Mint) {
                uint8 pausedStatus = collatInfo.unpausedMint;
                collatInfo.unpausedMint = 1 - pausedStatus;
            } else {
                uint8 pausedStatus = collatInfo.unpausedBurn;
                collatInfo.unpausedBurn = 1 - pausedStatus;
            }
        } else {
            KheopsStorage storage ks = s.kheopsStorage();
            uint8 pausedStatus = ks.pausedRedemption;
            ks.pausedRedemption = 1 - pausedStatus;
        }
    }

    /// @notice Set fees for {mint}/{burn}/{redeem} these are all piecewise linear function
    /// @param xFee Inflexion points array
    /// @param yFee Fees associated to the inflexion point
    /// @param setter Whether to set the mint fees (=0), the burn fees (=1) or the redeem fees(=2)
    /// @dev Mint/redeem xFee should be increasing and burn should be decreasing
    /// @dev Mint/redeem yFee should be increasing in their respective xFee referential
    function checkFees(uint64[] memory xFee, int64[] memory yFee, uint8 setter) internal view {
        uint256 n = xFee.length;
        if (n != yFee.length || n == 0) revert InvalidParams();

        // All inflexion point mint xFee should be in [0,BASE_9[
        // All inflexion point burn xFee should be in [0,BASE_9[
        // All inflexion point burn xFee should be in [0,BASE_9[
        // yFee should all be <= BASE_9
        if (
            (setter == 0 && (xFee[n - 1] >= BASE_9 || xFee[0] != 0)) ||
            (setter == 1 && (xFee[n - 1] < 0 || xFee[0] != BASE_9)) ||
            (setter == 2 && (xFee[n - 1] > BASE_9 || xFee[0] != 0))
        ) revert InvalidParams();

        for (uint256 i = 0; i < n - 1; ++i) {
            // xFee should be strictly monotonic, yFee monotonic (for setter == (0 || 1)) and yFee>=0 for redeem
            if (setter == 0 && (xFee[i] >= xFee[i + 1] || (yFee[i + 1] < yFee[i]))) revert InvalidParams();
            if (setter == 1 && (xFee[i] <= xFee[i + 1] || (yFee[i + 1] < yFee[i]))) revert InvalidParams();
            if (setter == 2 && (xFee[i] >= xFee[i + 1] || yFee[i] < 0 || yFee[i] > int256(BASE_9)))
                revert InvalidParams();
        }

        KheopsStorage storage ks = s.kheopsStorage();
        address[] memory collateralListMem = ks.collateralList;
        uint256 length = collateralListMem.length;
        if (setter == 0 && yFee[0] < 0) {
            // To not be exposed to direct arbitrage - an account atomically minting and then burning (from any collateral) -
            // we need to ensure that any product of fees will give you less than the initial value
            // if setter = 0, it can be mathematically expressed by (1-min_c(burnFee_c))(1-mintFee[0])<=1
            for (uint256 i; i < length; ++i) {
                int64[] memory burnFees = ks.collaterals[collateralListMem[i]].yFeeBurn;
                if ((int256(BASE_9) - burnFees[0]) * (int256(BASE_9) - yFee[0]) > int256(BASE_18))
                    revert InvalidParams();
            }
        }
        // if setter = 1, it can be mathematically expressed by (1-min_c(mintFee_c))(1-burnFee[0])<=1
        if (setter == 1 && yFee[0] < 0) {
            for (uint256 i; i < length; ++i) {
                int64[] memory mintFees = ks.collaterals[collateralListMem[i]].yFeeMint;
                if ((int256(BASE_9) - mintFees[0]) * (int256(BASE_9) - yFee[0]) > int256(BASE_18))
                    revert InvalidParams();
            }
        }
    }
}
