// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { IAccessControlManager } from "interfaces/IAccessControlManager.sol";
import { IGetters } from "interfaces/IGetters.sol";

import { LibOracle } from "../libraries/LibOracle.sol";
import { LibRedeemer } from "../libraries/LibRedeemer.sol";
import { LibStorage as s } from "../libraries/LibStorage.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import "../Storage.sol";

/// @title Getters
/// @author Angle Labs, Inc.
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
    function getCollateralMintFees(
        address collateral
    ) external view returns (uint64[] memory xFeeMint, int64[] memory yFeeMint) {
        Collateral storage collatInfo = s.transmuterStorage().collaterals[collateral];
        return (collatInfo.xFeeMint, collatInfo.yFeeMint);
    }

    /// @inheritdoc IGetters
    function getCollateralBurnFees(
        address collateral
    ) external view returns (uint64[] memory xFeeBurn, int64[] memory yFeeBurn) {
        Collateral storage collatInfo = s.transmuterStorage().collaterals[collateral];
        return (collatInfo.xFeeBurn, collatInfo.yFeeBurn);
    }

    /// @inheritdoc IGetters
    function getRedemptionFees()
        external
        view
        returns (uint64[] memory xRedemptionCurve, int64[] memory yRedemptionCurve)
    {
        TransmuterStorage storage ks = s.transmuterStorage();
        return (ks.xRedemptionCurve, ks.yRedemptionCurve);
    }

    /// @inheritdoc IGetters
    function getCollateralRatio() external view returns (uint64 collatRatio, uint256 stablecoinsIssued) {
        (collatRatio, stablecoinsIssued, , , ) = LibRedeemer.getCollateralRatio();
    }

    /// @inheritdoc IGetters
    function getIssuedByCollateral(
        address collateral
    ) external view returns (uint256 stablecoinsFromCollateral, uint256 stablecoinsIssued) {
        TransmuterStorage storage ks = s.transmuterStorage();
        uint256 _normalizer = ks.normalizer;
        return (
            (ks.collaterals[collateral].normalizedStables * _normalizer) / BASE_27,
            (ks.normalizedStables * _normalizer) / BASE_27
        );
    }

    /// @inheritdoc IGetters
    function getOracleValues(
        address collateral
    ) external view returns (uint256 mint, uint256 burn, uint256 ratio, uint256 redemption) {
        bytes memory oracleConfig = s.transmuterStorage().collaterals[collateral].oracleConfig;
        (burn, ratio) = LibOracle.readBurn(oracleConfig);
        return (LibOracle.readMint(oracleConfig), burn, ratio, LibOracle.readRedemption(oracleConfig));
    }

    /// @inheritdoc IGetters
    function getOracle(
        address collateral
    ) external view returns (OracleReadType readType, OracleTargetType targetType, bytes memory data) {
        return LibOracle.getOracle(collateral);
    }
}
