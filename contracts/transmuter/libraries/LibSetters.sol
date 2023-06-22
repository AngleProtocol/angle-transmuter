// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import { SafeCast } from "oz/utils/math/SafeCast.sol";
import { IERC20Metadata } from "oz/token/ERC20/extensions/IERC20Metadata.sol";

import { LibManager } from "../libraries/LibManager.sol";
import { LibOracle } from "./LibOracle.sol";
import { LibStorage as s } from "./LibStorage.sol";
import { LibDiamond } from "./LibDiamond.sol";
import { LibWhitelist } from "./LibWhitelist.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import "../Storage.sol";

/// @title LibSetters
/// @author Angle Labs, Inc.
library LibSetters {
    using SafeCast for uint256;

    event CollateralAdded(address indexed collateral);
    event CollateralManagerSet(address indexed collateral, ManagerStorage managerData);
    event CollateralRevoked(address indexed collateral);
    event CollateralWhitelistStatusUpdated(address indexed collateral, bytes whitelistData, uint8 whitelistStatus);
    event FeesSet(address indexed collateral, uint64[] xFee, int64[] yFee, bool mint);
    event OracleSet(address indexed collateral, bytes oracleConfig);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event PauseToggled(address indexed collateral, uint256 pausedType, bool isPaused);
    event RedemptionCurveParamsSet(uint64[] xFee, int64[] yFee);
    event ReservesAdjusted(address indexed collateral, uint256 amount, bool increase);
    event TrustedToggled(address indexed sender, bool isTrusted, TrustedType trustedType);
    event WhitelistStatusToggled(WhitelistType whitelistType, address indexed who, uint256 whitelistStatus);

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                 ONLY GOVERNOR ACTIONS                                              
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Internal version of `setAccessControlManager`
    function setAccessControlManager(IAccessControlManager _newAccessControlManager) internal {
        DiamondStorage storage ds = s.diamondStorage();
        IAccessControlManager previousAccessControlManager = ds.accessControlManager;
        ds.accessControlManager = _newAccessControlManager;
        emit OwnershipTransferred(address(previousAccessControlManager), address(_newAccessControlManager));
    }

    /// @notice Internal version of `setCollateralManager`
    function setCollateralManager(address collateral, ManagerStorage memory managerData) internal {
        Collateral storage collatInfo = s.transmuterStorage().collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        uint8 isManaged = collatInfo.isManaged;
        if (isManaged > 0) {
            (, uint256 totalValue) = LibManager.totalAssets(collatInfo.managerData.config);
            if (totalValue > 0) revert ManagerHasAssets();
        }
        if (managerData.config.length != 0) {
            // The first subCollateral given should be the actual collateral asset
            if (address(managerData.subCollaterals[0]) != collateral) revert InvalidParams();
            // Sanity check on the manager data that is passed
            LibManager.parseManagerConfig(managerData.config);
            collatInfo.isManaged = 1;
        } else collatInfo.isManaged = 0;
        collatInfo.managerData = managerData;
        emit CollateralManagerSet(collateral, managerData);
    }

    /// @notice Internal version of `toggleTrusted`
    function toggleTrusted(address sender, TrustedType t) internal {
        TransmuterStorage storage ts = s.transmuterStorage();
        uint256 trustedStatus;
        if (t == TrustedType.Updater) {
            trustedStatus = 1 - ts.isTrusted[sender];
            ts.isTrusted[sender] = trustedStatus;
        } else {
            trustedStatus = 1 - ts.isSellerTrusted[sender];
            ts.isSellerTrusted[sender] = trustedStatus;
        }
        emit TrustedToggled(sender, trustedStatus == 1, t);
    }

    /// @notice Internal version of `addCollateral`
    function addCollateral(address collateral) internal {
        TransmuterStorage storage ts = s.transmuterStorage();
        Collateral storage collatInfo = ts.collaterals[collateral];
        if (collatInfo.decimals != 0) revert AlreadyAdded();
        collatInfo.decimals = uint8(IERC20Metadata(collateral).decimals());
        ts.collateralList.push(collateral);
        emit CollateralAdded(collateral);
    }

    /// @notice Internal version of `adjustStablecoins`
    function adjustStablecoins(address collateral, uint128 amount, bool increase) internal {
        TransmuterStorage storage ts = s.transmuterStorage();
        Collateral storage collatInfo = ts.collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        uint128 normalizedAmount = ((amount * BASE_27) / ts.normalizer).toUint128();
        if (increase) {
            collatInfo.normalizedStables += uint216(normalizedAmount);
            ts.normalizedStables += normalizedAmount;
        } else {
            collatInfo.normalizedStables -= uint216(normalizedAmount);
            ts.normalizedStables -= normalizedAmount;
        }
        emit ReservesAdjusted(collateral, amount, increase);
    }

    /// @notice Internal version of `revokeCollateral`
    function revokeCollateral(address collateral) internal {
        TransmuterStorage storage ts = s.transmuterStorage();
        Collateral storage collatInfo = ts.collaterals[collateral];
        if (collatInfo.decimals == 0 || collatInfo.normalizedStables > 0) revert NotCollateral();
        uint8 isManaged = collatInfo.isManaged;
        if (isManaged > 0) {
            (, uint256 totalValue) = LibManager.totalAssets(collatInfo.managerData.config);
            if (totalValue > 0) revert ManagerHasAssets();
        }
        delete ts.collaterals[collateral];
        address[] memory collateralListMem = ts.collateralList;
        uint256 length = collateralListMem.length;
        for (uint256 i; i < length - 1; ++i) {
            if (collateralListMem[i] == collateral) {
                ts.collateralList[i] = collateralListMem[length - 1];
                break;
            }
        }
        ts.collateralList.pop();
        emit CollateralRevoked(collateral);
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

    /// @notice Internal version of `setWhitelistStatus`
    function setWhitelistStatus(address collateral, uint8 whitelistStatus, bytes memory whitelistData) internal {
        Collateral storage collatInfo = s.transmuterStorage().collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        if (whitelistStatus == 1) {
            // Sanity check
            LibWhitelist.parseWhitelistData(whitelistData);
            collatInfo.whitelistData = whitelistData;
        }
        collatInfo.onlyWhitelisted = whitelistStatus;
        emit CollateralWhitelistStatusUpdated(collateral, whitelistData, whitelistStatus);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                 ONLY GUARDIAN ACTIONS                                              
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

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
            TransmuterStorage storage ts = s.transmuterStorage();
            isLive = 1 - ts.isRedemptionLive;
            ts.isRedemptionLive = isLive;
        }
        emit PauseToggled(collateral, uint256(action), isLive == 0);
    }

    /// @notice Internal version of `setFees`
    function setFees(address collateral, uint64[] memory xFee, int64[] memory yFee, bool mint) internal {
        TransmuterStorage storage ts = s.transmuterStorage();
        Collateral storage collatInfo = ts.collaterals[collateral];
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

    /// @notice Internal version of `setRedemptionCurveParams`
    function setRedemptionCurveParams(uint64[] memory xFee, int64[] memory yFee) internal {
        TransmuterStorage storage ts = s.transmuterStorage();
        LibSetters.checkFees(xFee, yFee, ActionType.Redeem);
        ts.xRedemptionCurve = xFee;
        ts.yRedemptionCurve = yFee;
        emit RedemptionCurveParamsSet(xFee, yFee);
    }

    /// @notice Internal version of `toggleWhitelist`
    function toggleWhitelist(WhitelistType whitelistType, address who) internal {
        TransmuterStorage storage ts = s.transmuterStorage();
        uint256 whitelistStatus = 1 - ts.isWhitelistedForType[whitelistType][who];
        ts.isWhitelistedForType[whitelistType][who] = whitelistStatus;
        emit WhitelistStatusToggled(whitelistType, who, whitelistStatus);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        HELPERS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

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

        // If a mint or burn fee is negative, we need to check that accounts atomically minting
        // (from any collateral) and then burning cannot get more than their initial value
        if (yFee[0] < 0) {
            if (!LibDiamond.isGovernor(msg.sender)) revert NotGovernor(); // Only governor can set negative fees
            TransmuterStorage storage ts = s.transmuterStorage();
            address[] memory collateralListMem = ts.collateralList;
            uint256 length = collateralListMem.length;
            if (action == ActionType.Mint) {
                // This can be mathematically expressed by `(1-min_c(burnFee_c))<=(1+mintFee[0])`
                for (uint256 i; i < length; ++i) {
                    int64[] memory burnFees = ts.collaterals[collateralListMem[i]].yFeeBurn;
                    if (burnFees[0] + yFee[0] < 0) revert InvalidNegativeFees();
                }
            }
            if (action == ActionType.Burn) {
                // This can be mathematically expressed by `(1-burnFee[0])<=(1+min_c(mintFee_c))`
                for (uint256 i; i < length; ++i) {
                    int64[] memory mintFees = ts.collaterals[collateralListMem[i]].yFeeMint;
                    if (yFee[0] + mintFees[0] < 0) revert InvalidNegativeFees();
                }
            }
        }
    }
}
