// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.12;

import { LibStorage as s } from "../libraries/LibStorage.sol";
import { LibRedeemer } from "../libraries/LibRedeemer.sol";
import { LibOracle } from "../libraries/LibOracle.sol";
import { Diamond } from "../libraries/Diamond.sol";
import "../../utils/Constants.sol";
import "../../utils/Errors.sol";

import { IAccessControlManager } from "../../interfaces/IAccessControlManager.sol";
import "../Storage.sol";

import { IGetters } from "../interfaces/IGetters.sol";

/// @title Getters
/// @author Angle Labs, Inc.
contract Getters is IGetters {
    /// @inheritdoc IGetters
    function isValidSelector(bytes4 selector) external view returns (bool) {
        return s.diamondStorage().facetAddressAndSelectorPosition[selector].facetAddress != address(0);
    }

    /// @inheritdoc IGetters
    function accessControlManager() external view returns (IAccessControlManager) {
        return s.diamondStorage().accessControlManager;
    }

    /// @inheritdoc IGetters
    function agToken() external view returns (IAgToken) {
        return s.kheopsStorage().agToken;
    }

    /// @notice Checks whether `admin` has the governor role
    function isGovernor(address admin) external view returns (bool) {
        return Diamond.isGovernor(admin);
    }

    /// @notice Checks whether `admin` has the guardian role
    function isGovernorOrGuardian(address admin) external view returns (bool) {
        return Diamond.isGovernorOrGuardian(admin);
    }

    /// @inheritdoc IGetters
    function getCollateralList() external view returns (address[] memory) {
        return s.kheopsStorage().collateralList;
    }

    /// @inheritdoc IGetters
    function getCollateralMintFees(address collateralAddress) external view returns (uint64[] memory, int64[] memory) {
        Collateral storage collateral = s.kheopsStorage().collaterals[collateralAddress];
        return (collateral.xFeeMint, collateral.yFeeMint);
    }

    /// @inheritdoc IGetters
    function getCollateralBurnFees(address collateralAddress) external view returns (uint64[] memory, int64[] memory) {
        Collateral storage collateral = s.kheopsStorage().collaterals[collateralAddress];
        return (collateral.xFeeBurn, collateral.yFeeBurn);
    }

    /// @inheritdoc IGetters
    function getRedemptionFees() external view returns (uint64[] memory, int64[] memory) {
        KheopsStorage storage ks = s.kheopsStorage();
        return (ks.xRedemptionCurve, ks.yRedemptionCurve);
    }

    /// @inheritdoc IGetters
    function getCollateralRatio() external view returns (uint64 collatRatio, uint256 reservesValue) {
        (collatRatio, reservesValue, , , ) = LibRedeemer.getCollateralRatio();
    }

    /// @inheritdoc IGetters
    function getIssuedByCollateral(address collateral) external view returns (uint256, uint256) {
        KheopsStorage storage ks = s.kheopsStorage();
        uint256 _normalizer = ks.normalizer;
        return (
            (ks.collaterals[collateral].normalizedStables * _normalizer) / BASE_27,
            (ks.normalizedStables * _normalizer) / BASE_27
        );
    }

    /// @inheritdoc IGetters
    function getOracleValues(address collateral) external view returns (uint256, uint256, uint256, uint256) {
        bytes memory oracleConfig = s.kheopsStorage().collaterals[collateral].oracleConfig;
        (uint256 burn, uint256 deviation) = LibOracle.readBurn(oracleConfig);
        return (LibOracle.readMint(oracleConfig), burn, deviation, LibOracle.readRedemption(oracleConfig));
    }

    /// @inheritdoc IGetters
    function getOracle(
        address collateral
    ) external view returns (OracleReadType, OracleQuoteType, OracleTargetType, bytes memory) {
        return LibOracle.getOracle(collateral);
    }
}
