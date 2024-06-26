// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

import { IERC20 } from "oz/interfaces/IERC20.sol";
import { IERC4626 } from "interfaces/external/IERC4626.sol";
import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "oz/utils/math/SafeCast.sol";

import { ITransmuter } from "interfaces/ITransmuter.sol";

import { AccessControl, IAccessControlManager } from "../utils/AccessControl.sol";
import "../utils/Constants.sol";
import "../utils/Errors.sol";

import { RebalancerFlashloan } from "./RebalancerFlashloan.sol";

struct CollatParams {
    // Vault associated to the collateral
    address vault;
    // Target exposure to the collateral asset used in the vault
    uint64 targetExposure;
    // Maximum exposure within the Transmuter to the vault asset
    uint64 maxExposureYieldAsset;
    // Minimum exposure within the Transmuter to the vault asset
    uint64 minExposureYieldAsset;
    // Whether limit exposures should be overriden or read onchain through the Transmuter
    // This value should be 1 to override exposures or 2 if these shouldn't be overriden
    uint64 overrideExposures;
}

/// @title Harvester
/// @author Angle Labs, Inc.
/// @dev Contract for anyone to permissionlessly adjust the reserves of Angle Transmuter through
/// the RebalancerFlashloan contract
contract Harvester is AccessControl {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    /// @notice Reference to the `transmuter` implementation this contract aims at rebalancing
    ITransmuter public immutable TRANSMUTER;
    /// @notice Permissioned rebalancer contract
    RebalancerFlashloan public rebalancer;
    /// @notice Max slippage when dealing with the Transmuter
    uint96 public maxSlippage;
    /// @notice Data associated to a collateral
    mapping(address => CollatParams) public collateralData;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    INITIALIZATION                                                  
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    constructor(
        address _rebalancer,
        address vault,
        uint64 targetExposure,
        uint64 overrideExposures,
        uint64 maxExposureYieldAsset,
        uint64 minExposureYieldAsset,
        uint96 _maxSlippage
    ) {
        ITransmuter transmuter = RebalancerFlashloan(_rebalancer).TRANSMUTER();
        TRANSMUTER = transmuter;
        rebalancer = RebalancerFlashloan(_rebalancer);
        accessControlManager = IAccessControlManager(transmuter.accessControlManager());
        _setCollateralData(vault, targetExposure, minExposureYieldAsset, maxExposureYieldAsset, overrideExposures);
        _setMaxSlippage(_maxSlippage);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        HARVEST                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Invests or divests from the yield asset associated to `collateral` based on the current exposure to this
    /// collateral
    /// @dev This transaction either reduces the exposure to `collateral` in the Transmuter or frees up some collateral
    /// that can then be used for people looking to burn stablecoins
    /// @dev Due to potential transaction fees within the Transmuter, this function doesn't exactly bring `collateral`
    /// to the target exposure
    /// @dev The `harvest` possibility shouldn't be implemented for assets with a manipulable price (like ERC4626)
    /// contracts on which the `previewRedeem` values can be easily moved by creating a loss or a profit
    function harvest(address collateral) external {
        (uint256 stablecoinsFromCollateral, uint256 stablecoinsIssued) = TRANSMUTER.getIssuedByCollateral(collateral);
        CollatParams memory collatInfo = collateralData[collateral];
        (uint256 stablecoinsFromVault, ) = TRANSMUTER.getIssuedByCollateral(collatInfo.vault);
        uint8 increase;
        uint256 amount;
        uint256 targetExposureScaled = collatInfo.targetExposure * stablecoinsIssued;
        if (stablecoinsFromCollateral * 1e9 > targetExposureScaled) {
            // Need to increase exposure to yield bearing asset
            increase = 1;
            amount = stablecoinsFromCollateral - targetExposureScaled / 1e9;
            uint256 maxValueScaled = collatInfo.maxExposureYieldAsset * stablecoinsIssued;
            // These checks assume that there are no transaction fees on the stablecoin->collateral conversion and so
            // it's still possible that exposure goes above the max exposure in some rare cases
            if (stablecoinsFromVault * 1e9 > maxValueScaled) amount = 0;
            else if ((stablecoinsFromVault + amount) * 1e9 > maxValueScaled)
                amount = maxValueScaled / 1e9 - stablecoinsFromVault;
        } else {
            // In this case, exposure after the operation might remain slightly below the targetExposure as less
            // collateral may be obtained by burning stablecoins for the yield asset and unwrapping it
            amount = targetExposureScaled / 1e9 - stablecoinsFromCollateral;
            uint256 minValueScaled = collatInfo.minExposureYieldAsset * stablecoinsIssued;
            if (stablecoinsFromVault * 1e9 < minValueScaled) amount = 0;
            else if (stablecoinsFromVault * 1e9 < minValueScaled + amount * 1e9)
                amount = stablecoinsFromVault - minValueScaled / 1e9;
        }
        if (amount > 0) {
            try TRANSMUTER.updateOracle(collatInfo.vault) {} catch {}

            rebalancer.adjustYieldExposure(
                amount,
                increase,
                collateral,
                collatInfo.vault,
                (amount * (1e9 - maxSlippage)) / 1e9
            );
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        SETTERS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function setRebalancer(address _newRebalancer) external onlyGuardian {
        if (_newRebalancer == address(0)) revert ZeroAddress();
        rebalancer = RebalancerFlashloan(_newRebalancer);
    }

    /// @dev This function shouldn't be called for a vault (e.g an ERC4626 token) which price can be easily moved
    /// by creating a loss or a profit, at the risk of depleting the reserves available in the Rebalancer
    function setCollateralData(
        address vault,
        uint64 targetExposure,
        uint64 minExposureYieldAsset,
        uint64 maxExposureYieldAsset,
        uint64 overrideExposures
    ) external onlyGuardian {
        _setCollateralData(vault, targetExposure, minExposureYieldAsset, maxExposureYieldAsset, overrideExposures);
    }

    function setMaxSlippage(uint96 _maxSlippage) external onlyGuardian {
        _setMaxSlippage(_maxSlippage);
    }

    function updateLimitExposuresYieldAsset(address collateral) external {
        CollatParams storage collatInfo = collateralData[collateral];
        if (collatInfo.overrideExposures == 2) _updateLimitExposuresYieldAsset(collatInfo);
    }

    function _setMaxSlippage(uint96 _maxSlippage) internal {
        if (_maxSlippage > 1e9) revert InvalidParam();
        maxSlippage = _maxSlippage;
    }

    function _setCollateralData(
        address vault,
        uint64 targetExposure,
        uint64 minExposureYieldAsset,
        uint64 maxExposureYieldAsset,
        uint64 overrideExposures
    ) internal {
        address collateral = address(IERC4626(vault).asset());
        CollatParams storage collatInfo = collateralData[collateral];
        collatInfo.vault = vault;
        if (targetExposure >= 1e9) revert InvalidParam();
        collatInfo.targetExposure = targetExposure;
        collatInfo.overrideExposures = overrideExposures;
        if (overrideExposures == 1) {
            if (maxExposureYieldAsset >= 1e9 || minExposureYieldAsset >= maxExposureYieldAsset) revert InvalidParam();
            collatInfo.maxExposureYieldAsset = maxExposureYieldAsset;
            collatInfo.minExposureYieldAsset = minExposureYieldAsset;
        } else {
            collatInfo.overrideExposures = 2;
            _updateLimitExposuresYieldAsset(collatInfo);
        }
    }

    function _updateLimitExposuresYieldAsset(CollatParams storage collatInfo) internal {
        uint64[] memory xFeeMint;
        (xFeeMint, ) = TRANSMUTER.getCollateralMintFees(collatInfo.vault);
        uint256 length = xFeeMint.length;
        if (length <= 1) collatInfo.maxExposureYieldAsset = 1e9;
        else collatInfo.maxExposureYieldAsset = xFeeMint[length - 2];

        uint64[] memory xFeeBurn;
        (xFeeBurn, ) = TRANSMUTER.getCollateralBurnFees(collatInfo.vault);
        length = xFeeBurn.length;
        if (length <= 1) collatInfo.minExposureYieldAsset = 0;
        else collatInfo.minExposureYieldAsset = xFeeBurn[length - 2];
    }
}
