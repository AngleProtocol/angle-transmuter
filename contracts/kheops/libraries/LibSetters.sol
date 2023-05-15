// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "oz/token/ERC20/extensions/IERC20Metadata.sol";

import { LibHelpers } from "./LibHelpers.sol";
import { LibOracle } from "./LibOracle.sol";
import { LibStorage as s } from "./LibStorage.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import "../Storage.sol";

/// @title LibSetters
/// @author Angle Labs, Inc.
library LibSetters {
    event CollateralAdded(address indexed collateral);
    event FeesSet(address indexed collateral, uint64[] xFee, int64[] yFee, bool mint);
    event OracleSet(address indexed collateral, bytes oracleConfig);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event PauseToggled(address indexed collateral, uint256 pausedType);

    /// @notice Internal version of `setAccessControlManager`
    function setAccessControlManager(IAccessControlManager _newAccessControlManager) internal {
        DiamondStorage storage ds = s.diamondStorage();
        IAccessControlManager previousAccessControlManager = ds.accessControlManager;
        ds.accessControlManager = _newAccessControlManager;
        emit OwnershipTransferred(address(previousAccessControlManager), address(_newAccessControlManager));
    }

    /// @notice Internal version of `addCollateral`
    function addCollateral(address collateral) internal {
        KheopsStorage storage ks = s.kheopsStorage();
        Collateral storage collatInfo = ks.collaterals[collateral];
        if (collatInfo.decimals != 0) revert AlreadyAdded();
        collatInfo.decimals = uint8(IERC20Metadata(collateral).decimals());
        ks.collateralList.push(collateral);
        emit CollateralAdded(collateral);
    }

    /// @notice Internal version of `setOracle`
    function setOracle(address collateral, bytes memory oracleConfig) internal {
        Collateral storage collatInfo = s.kheopsStorage().collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        // Checks oracle validity
        LibOracle.readMint(oracleConfig);
        collatInfo.oracleConfig = oracleConfig;
        emit OracleSet(collateral, oracleConfig);
    }

    /// @notice Internal version of `setFees`
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
        emit FeesSet(collateral, xFee, yFee, mint);
    }

    /// @notice Internal version of `togglePause`
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
        emit PauseToggled(collateral, uint256(pausedType));
    }

    /// @notice Checks the fee values given for the `mint`, `burn`, and `redeem` functions
    /// @param setter Whether to set the mint fees (=0), the burn fees (=1) or the redeem fees(=2)
    function checkFees(uint64[] memory xFee, int64[] memory yFee, uint8 setter) internal view {
        uint256 n = xFee.length;
        if (n != yFee.length || n == 0) revert InvalidParams();
        if (
            // yFee should be <= BASE_9 for burn and redeem
            (setter != 0 && yFee[n - 1] > int256(BASE_9)) ||
            // Mint inflexion points should be in [0,BASE_9[
            (setter == 0 && (xFee[n - 1] >= BASE_9 || xFee[0] != 0)) ||
            // Burn inflexion points should be in ]0,BASE_9]
            (setter == 1 && (xFee[n - 1] <= 0 || xFee[0] != BASE_9)) ||
            // Redemption inflexion points should be in [0,BASE_9]
            (setter == 2 && xFee[n - 1] > BASE_9)
        ) revert InvalidParams();

        for (uint256 i = 0; i < n - 1; ++i) {
            if (
                // xFee strictly increasing and yFee increasing for mints
                (setter == 0 && (xFee[i] >= xFee[i + 1] || (yFee[i + 1] < yFee[i]))) ||
                // xFee strictly decreasing and yFee increasing for burns
                (setter == 1 && (xFee[i] <= xFee[i + 1] || (yFee[i + 1] < yFee[i]))) ||
                // xFee strictly increasing and yFee>=0 for redemptions
                (setter == 2 && (xFee[i] >= xFee[i + 1] || yFee[i] < 0 || yFee[i] > int256(BASE_9)))
            ) revert InvalidParams();
        }
        KheopsStorage storage ks = s.kheopsStorage();
        address[] memory collateralListMem = ks.collateralList;
        uint256 length = collateralListMem.length;
        // If a fee is negative, we need to check that accounts atomically minting (from any collateral) and
        // then burning cannot get more than their initial value
        if (setter == 0 && yFee[0] < 0) {
            // If `setter = 0`, this can be mathematically expressed by `(1-min_c(burnFee_c))(1-mintFee[0])<=1`
            for (uint256 i; i < length; ++i) {
                int64[] memory burnFees = ks.collaterals[collateralListMem[i]].yFeeBurn;
                if ((int256(BASE_9) - burnFees[0]) * (int256(BASE_9) - yFee[0]) > int256(BASE_18))
                    revert InvalidParams();
            }
        }

        if (setter == 1 && yFee[0] < 0) {
            // If `setter = 1`, this can be mathematically expressed by `(1-min_c(mintFee_c))(1-burnFee[0])<=1`
            for (uint256 i; i < length; ++i) {
                int64[] memory mintFees = ks.collaterals[collateralListMem[i]].yFeeMint;
                if ((int256(BASE_9) - mintFees[0]) * (int256(BASE_9) - yFee[0]) > int256(BASE_18))
                    revert InvalidParams();
            }
        }
    }
}
