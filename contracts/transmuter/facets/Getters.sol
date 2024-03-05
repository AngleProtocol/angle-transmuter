// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import {IAccessControlManager} from "interfaces/IAccessControlManager.sol";
import {IGetters} from "interfaces/IGetters.sol";

import {LibOracle} from "../libraries/LibOracle.sol";
import {LibGetters} from "../libraries/LibGetters.sol";
import {LibStorage as s} from "../libraries/LibStorage.sol";
import {LibWhitelist} from "../libraries/LibWhitelist.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import "../Storage.sol";

/// @title Getters
/// @author Angle Labs, Inc.
/// @dev There may be duplicates in the info provided by the getters defined here
contract Getters is IGetters {
    /// @inheritdoc IGetters
    function isValidSelector(bytes4 selector) external view returns (bool) {
        return s.diamondStorage().selectorInfo[selector].facetAddress != address(0);
    }

    /// @inheritdoc IGetters
    function accessControlManager() external view returns (IAccessControlManager) {
        return s.diamondStorage().accessControlManager;
    }

    /// @inheritdoc IGetters
    function agToken() external view returns (IAgToken) {
        return s.transmuterStorage().agToken;
    }

    /// @inheritdoc IGetters
    function getCollateralList() external view returns (address[] memory) {
        return s.transmuterStorage().collateralList;
    }

    /// @inheritdoc IGetters
    function getCollateralInfo(address collateral) external view returns (Collateral memory) {
        return s.transmuterStorage().collaterals[collateral];
    }

    /// @inheritdoc IGetters
    function getCollateralDecimals(address collateral) external view returns (uint8) {
        return s.transmuterStorage().collaterals[collateral].decimals;
    }

    /// @inheritdoc IGetters
    function getCollateralMintFees(address collateral)
        external
        view
        returns (uint64[] memory xFeeMint, int64[] memory yFeeMint)
    {
        Collateral storage collatInfo = s.transmuterStorage().collaterals[collateral];
        return (collatInfo.xFeeMint, collatInfo.yFeeMint);
    }

    /// @inheritdoc IGetters
    function getCollateralBurnFees(address collateral)
        external
        view
        returns (uint64[] memory xFeeBurn, int64[] memory yFeeBurn)
    {
        Collateral storage collatInfo = s.transmuterStorage().collaterals[collateral];
        return (collatInfo.xFeeBurn, collatInfo.yFeeBurn);
    }

    /// @inheritdoc IGetters
    function getRedemptionFees()
        external
        view
        returns (uint64[] memory xRedemptionCurve, int64[] memory yRedemptionCurve)
    {
        TransmuterStorage storage ts = s.transmuterStorage();
        return (ts.xRedemptionCurve, ts.yRedemptionCurve);
    }

    /// @inheritdoc IGetters
    /// @dev This function may revert and overflow if the collateral ratio is too big due to a too small
    /// amount of `stablecoinsIssued`. Due to this, it is recommended to initialize the system with a non
    /// negligible amount of `stablecoinsIssued` so DoS attacks on redemptions which use this function
    /// become economically impossible
    function getCollateralRatio() external view returns (uint64 collatRatio, uint256 stablecoinsIssued) {
        TransmuterStorage storage ts = s.transmuterStorage();
        // Reentrant protection
        if (ts.statusReentrant == ENTERED) revert ReentrantCall();

        (collatRatio, stablecoinsIssued,,,) = LibGetters.getCollateralRatio();
    }

    /// @inheritdoc IGetters
    function getIssuedByCollateral(address collateral)
        external
        view
        returns (uint256 stablecoinsFromCollateral, uint256 stablecoinsIssued)
    {
        TransmuterStorage storage ts = s.transmuterStorage();
        uint256 _normalizer = ts.normalizer;
        return (
            (uint256(ts.collaterals[collateral].normalizedStables) * _normalizer) / BASE_27,
            (uint256(ts.normalizedStables) * _normalizer) / BASE_27
        );
    }

    /// @inheritdoc IGetters
    function getTotalIssued() external view returns (uint256) {
        TransmuterStorage storage ts = s.transmuterStorage();
        return (uint256(ts.normalizedStables) * uint256(ts.normalizer)) / BASE_27;
    }

    /// @inheritdoc IGetters
    function getManagerData(address collateral) external view returns (bool, IERC20[] memory, bytes memory) {
        Collateral storage collatInfo = s.transmuterStorage().collaterals[collateral];
        if (collatInfo.isManaged > 0) {
            return (true, collatInfo.managerData.subCollaterals, collatInfo.managerData.config);
        }
        return (false, new IERC20[](0), "");
    }

    /// @inheritdoc IGetters
    /// @dev This function is not optimized for gas consumption as for instance the `burn` value for collateral
    /// is computed twice: once in `readBurn` and once in `getBurnOracle`
    function getOracleValues(address collateral)
        external
        view
        returns (uint256 mint, uint256 burn, uint256 ratio, uint256 minRatio, uint256 redemption)
    {
        bytes memory oracleConfig = s.transmuterStorage().collaterals[collateral].oracleConfig;
        (burn, ratio) = LibOracle.readBurn(oracleConfig);
        (minRatio,) = LibOracle.getBurnOracle(collateral, oracleConfig);
        return (LibOracle.readMint(oracleConfig), burn, ratio, minRatio, LibOracle.readRedemption(oracleConfig));
    }

    /// @inheritdoc IGetters
    function getOracle(address collateral)
        external
        view
        returns (
            OracleReadType oracleType,
            OracleReadType targetType,
            bytes memory oracleData,
            bytes memory targetData,
            bytes memory hyperparameters
        )
    {
        return LibOracle.getOracle(collateral);
    }

    /// @inheritdoc IGetters
    function isPaused(address collateral, ActionType action) external view returns (bool) {
        if (action == ActionType.Mint || action == ActionType.Burn) {
            Collateral storage collatInfo = s.transmuterStorage().collaterals[collateral];
            if (collatInfo.decimals == 0) revert NotCollateral();
            if (action == ActionType.Mint) {
                return collatInfo.isMintLive == 0;
            } else {
                return collatInfo.isBurnLive == 0;
            }
        } else {
            return s.transmuterStorage().isRedemptionLive == 0;
        }
    }

    /// @inheritdoc IGetters
    function isTrusted(address sender) external view returns (bool) {
        return s.transmuterStorage().isTrusted[sender] == 1;
    }

    /// @inheritdoc IGetters
    function isTrustedSeller(address sender) external view returns (bool) {
        return s.transmuterStorage().isSellerTrusted[sender] == 1;
    }

    /// @inheritdoc IGetters
    function isWhitelistedForType(WhitelistType whitelistType, address sender) external view returns (bool) {
        return s.transmuterStorage().isWhitelistedForType[whitelistType][sender] > 0;
    }

    /// @inheritdoc IGetters
    /// @dev This function is non view as it may consult external non view functions from whitelist providers
    function isWhitelistedForCollateral(address collateral, address sender) external returns (bool) {
        Collateral storage collatInfo = s.transmuterStorage().collaterals[collateral];
        return (collatInfo.onlyWhitelisted == 0 || LibWhitelist.checkWhitelist(collatInfo.whitelistData, sender));
    }

    /// @inheritdoc IGetters
    function isWhitelistedCollateral(address collateral) external view returns (bool) {
        return s.transmuterStorage().collaterals[collateral].onlyWhitelisted == 1;
    }

    /// @inheritdoc IGetters
    function getCollateralWhitelistData(address collateral) external view returns (bytes memory) {
        return s.transmuterStorage().collaterals[collateral].whitelistData;
    }
}
