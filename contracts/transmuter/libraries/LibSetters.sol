// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "oz/token/ERC20/extensions/IERC20Metadata.sol";

import { LibHelpers } from "./LibHelpers.sol";
import { LibOracle } from "./LibOracle.sol";
import { LibStorage as s } from "./LibStorage.sol";
import { LibWhitelist } from "./LibWhitelist.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import "../Storage.sol";

/// @title LibSetters
/// @author Angle Labs, Inc.
library LibSetters {
    event CollateralAdded(address indexed collateral);
    event CollateralWhitelistStatusUpdated(address indexed collateral, bytes whitelistData, uint8 whitelistStatus);
    event FeesSet(address indexed collateral, uint64[] xFee, int64[] yFee, bool mint);
    event OracleSet(address indexed collateral, bytes oracleConfig);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event PauseToggled(address indexed collateral, uint256 pausedType, bool isPaused);

    /// @notice Internal version of `setAccessControlManager`
    function setAccessControlManager(IAccessControlManager _newAccessControlManager) internal {
        DiamondStorage storage ds = s.diamondStorage();
        IAccessControlManager previousAccessControlManager = ds.accessControlManager;
        ds.accessControlManager = _newAccessControlManager;
        emit OwnershipTransferred(address(previousAccessControlManager), address(_newAccessControlManager));
    }

    /// @notice Internal version of `addCollateral`
    function addCollateral(address collateral) internal {
        TransmuterStorage storage ks = s.transmuterStorage();
        Collateral storage collatInfo = ks.collaterals[collateral];
        if (collatInfo.decimals != 0) revert AlreadyAdded();
        collatInfo.decimals = uint8(IERC20Metadata(collateral).decimals());
        ks.collateralList.push(collateral);
        emit CollateralAdded(collateral);
    }

    /// @notice Internal version of `setWhitelistStatus`
    function setWhitelistStatus(address collateral, uint8 whitelistStatus, bytes memory whitelistData) internal {
        Collateral storage collatInfo = s.transmuterStorage().collaterals[collateral];
        if (whitelistStatus == 1) {
            // Sanity check
            LibWhitelist.parseWhitelistData(whitelistData);
            collatInfo.whitelistData = whitelistData;
        }
        collatInfo.onlyWhitelisted = whitelistStatus;
        emit CollateralWhitelistStatusUpdated(collateral, whitelistData, whitelistStatus);
    }

    /// @notice Internal version of `setOracle`
    function setOracle(address collateral, bytes memory oracleConfig) internal {
        Collateral storage collatInfo = s.transmuterStorage().collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        // Checks oracle validity
        LibOracle.readMint(oracleConfig);
        collatInfo.oracleConfig = oracleConfig;
        emit OracleSet(collateral, oracleConfig);
    }

    /// @notice Internal version of `setFees`
    function setFees(address collateral, uint64[] memory xFee, int64[] memory yFee, bool mint) internal {
        TransmuterStorage storage ks = s.transmuterStorage();
        Collateral storage collatInfo = ks.collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        checkFees(xFee, yFee, mint ? ActionType.Mint : ActionType.Burn);
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
    function togglePause(address collateral, ActionType action) internal {
        uint8 isLive;
        if (action == ActionType.Mint || action == ActionType.Burn) {
            Collateral storage collatInfo = s.transmuterStorage().collaterals[collateral];
            if (collatInfo.decimals == 0) revert NotCollateral();
            if (action == ActionType.Mint) {
                isLive = 1 - collatInfo.isMintLive;
                collatInfo.isMintLive = isLive;
            } else {
                isLive = 1 - collatInfo.isBurnLive;
                collatInfo.isBurnLive = isLive;
            }
        } else {
            TransmuterStorage storage ks = s.transmuterStorage();
            isLive = 1 - ks.isRedemptionLive;
            ks.isRedemptionLive = isLive;
        }
        emit PauseToggled(collateral, uint256(action), isLive == 0);
    }

    /// @notice Checks the fee values given for the `mint`, `burn`, and `redeem` functions
    function checkFees(uint64[] memory xFee, int64[] memory yFee, ActionType action) internal view {
        uint256 n = xFee.length;
        if (n != yFee.length || n == 0) revert InvalidParams();
        if (
            // Mint inflexion points should be in [0,BASE_9[
            // We have: amountPostFee * (BASE_9 + yFeeMint) = amountPreFee * BASE_9
            // Hence we consider BASE_12 as the max value (100% fees) for yFeeMint
            (action == ActionType.Mint && (xFee[n - 1] >= BASE_9 || xFee[0] != 0 || yFee[n - 1] > int256(BASE_12))) ||
            // Burn inflexion points should be in [0,BASE_9] but fees should be constant in
            // the first segment [BASE_9, x_{n-1}[
            (action == ActionType.Burn &&
                (xFee[0] != BASE_9 || yFee[n - 1] > int256(BASE_9) || (n > 1 && (yFee[0] != yFee[1])))) ||
            // Redemption inflexion points should be in [0,BASE_9]
            (action == ActionType.Redeem && (xFee[n - 1] > BASE_9 || yFee[n - 1] < 0 || yFee[n - 1] > int256(BASE_9)))
        ) revert InvalidParams();

        for (uint256 i = 0; i < n - 1; ++i) {
            if (
                // xFee strictly increasing and yFee increasing for mints
                (action == ActionType.Mint && (xFee[i] >= xFee[i + 1] || (yFee[i + 1] < yFee[i]))) ||
                // xFee strictly decreasing and yFee increasing for burns
                (action == ActionType.Burn && (xFee[i] <= xFee[i + 1] || (yFee[i + 1] < yFee[i]))) ||
                // xFee strictly increasing and yFee should be in [0,BASE_9] for redemptions
                (action == ActionType.Redeem && (xFee[i] >= xFee[i + 1] || yFee[i] < 0 || yFee[i] > int256(BASE_9)))
            ) revert InvalidParams();
        }

        // If a mint or burn feefee is negative, we need to check that accounts atomically minting
        // (from any collateral) and then burning cannot get more than their initial value
        if (yFee[0] < 0) {
            TransmuterStorage storage ks = s.transmuterStorage();
            address[] memory collateralListMem = ks.collateralList;
            uint256 length = collateralListMem.length;
            if (action == ActionType.Mint) {
                // This can be mathematically expressed by `(1-min_c(burnFee_c))<=(1+mintFee[0])`
                for (uint256 i; i < length; ++i) {
                    int64[] memory burnFees = ks.collaterals[collateralListMem[i]].yFeeBurn;
                    if (burnFees[0] + yFee[0] < 0) revert InvalidNegativeFees();
                }
            }
            if (action == ActionType.Burn) {
                // This can be mathematically expressed by `(1-burnFee[0])<=(1+min_c(mintFee_c))`
                for (uint256 i; i < length; ++i) {
                    int64[] memory mintFees = ks.collaterals[collateralListMem[i]].yFeeMint;
                    if (yFee[0] + mintFees[0] < 0) revert InvalidNegativeFees();
                }
            }
        }
    }
}
