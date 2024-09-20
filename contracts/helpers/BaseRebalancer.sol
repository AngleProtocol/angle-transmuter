// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControl, IAccessControlManager } from "../utils/AccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ITransmuter } from "../interfaces/ITransmuter.sol";
import { IAgToken } from "../interfaces/IAgToken.sol";

import "../utils/Errors.sol";

struct CollatParams {
    // Address of the collateral
    address asset;
    // Target exposure to the collateral asset used
    uint64 targetExposure;
    // Maximum exposure within the Transmuter to the asset
    uint64 maxExposureYieldAsset;
    // Minimum exposure within the Transmuter to the asset
    uint64 minExposureYieldAsset;
    // Whether limit exposures should be overriden or read onchain through the Transmuter
    // This value should be 1 to override exposures or 2 if these shouldn't be overriden
    uint64 overrideExposures;
}

abstract contract BaseRebalancer is AccessControl {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       VARIABLES
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Reference to the `transmuter` implementation this contract aims at rebalancing
    ITransmuter public immutable transmuter;
    /// @notice AgToken handled by the `transmuter` of interest
    IAgToken public immutable agToken;
    /// @notice Max slippage when dealing with the Transmuter
    uint96 public maxSlippage;
    /// @notice Data associated to a collateral
    mapping(address => CollatParams) public collateralData;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    constructor(
        uint96 initialMaxSlippage,
        IAccessControlManager definitiveAccessControlManager,
        IAgToken definitiveAgToken,
        ITransmuter definitiveTransmuter
    ) {
        _setMaxSlippage(initialMaxSlippage);
        accessControlManager = definitiveAccessControlManager;
        agToken = definitiveAgToken;
        transmuter = definitiveTransmuter;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        GUARDIAN FUNCTIONS
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the collateral data
     * @param collateral address of the collateral
     * @param targetExposure target exposure to the collateral asset used
     * @param minExposureYieldAsset minimum exposure within the Transmuter to the asset
     * @param maxExposureYieldAsset maximum exposure within the Transmuter to the asset
     * @param overrideExposures whether limit exposures should be overriden or read onchain through the Transmuter
     * This value should be 1 to override exposures or 2 if these shouldn't be overriden
     */
    function setCollateralData(
        address collateral,
        uint64 targetExposure,
        uint64 minExposureYieldAsset,
        uint64 maxExposureYieldAsset,
        uint64 overrideExposures
    ) external onlyGuardian {
        _setCollateralData(
            collateral,
            collateral,
            targetExposure,
            minExposureYieldAsset,
            maxExposureYieldAsset,
            overrideExposures
        );
    }

    /**
     * @notice Set the collateral data
     * @param collateral address of the collateral
     * @param asset address of the asset
     * @param targetExposure target exposure to the collateral asset used
     * @param minExposureYieldAsset minimum exposure within the Transmuter to the asset
     * @param maxExposureYieldAsset maximum exposure within the Transmuter to the asset
     * @param overrideExposures whether limit exposures should be overriden or read onchain through the Transmuter
     */
    function setCollateralData(
        address collateral,
        address asset,
        uint64 targetExposure,
        uint64 minExposureYieldAsset,
        uint64 maxExposureYieldAsset,
        uint64 overrideExposures
    ) external onlyGuardian {
        _setCollateralData(
            collateral,
            asset,
            targetExposure,
            minExposureYieldAsset,
            maxExposureYieldAsset,
            overrideExposures
        );
    }

    /**
     * @notice Set the limit exposures to the yield bearing asset
     * @param collateral address of the collateral
     */
    function updateLimitExposuresYieldAsset(address collateral) public virtual onlyGuardian {
        CollatParams storage collatInfo = collateralData[collateral];
        if (collatInfo.overrideExposures == 2) _updateLimitExposuresYieldAsset(collatInfo);
    }

    /**
     * @notice Set the max allowed slippage
     * @param newMaxSlippage new max allowed slippage
     */
    function setMaxSlippage(uint96 newMaxSlippage) external onlyGuardian {
        _setMaxSlippage(newMaxSlippage);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _computeRebalanceAmount(
        address collateral,
        CollatParams memory collatInfo
    ) internal view returns (uint8 increase, uint256 amount) {
        (uint256 stablecoinsFromCollateral, uint256 stablecoinsIssued) = transmuter.getIssuedByCollateral(collateral);
        (uint256 stablecoinsFromAsset, ) = transmuter.getIssuedByCollateral(collatInfo.asset);
        uint256 targetExposureScaled = collatInfo.targetExposure * stablecoinsIssued;
        if (stablecoinsFromCollateral * 1e9 > targetExposureScaled) {
            // Need to increase exposure to yield bearing asset
            increase = 1;
            amount = stablecoinsFromCollateral - targetExposureScaled / 1e9;
            uint256 maxValueScaled = collatInfo.maxExposureYieldAsset * stablecoinsIssued;
            // These checks assume that there are no transaction fees on the stablecoin->collateral conversion and so
            // it's still possible that exposure goes above the max exposure in some rare cases
            if (stablecoinsFromAsset * 1e9 > maxValueScaled) amount = 0;
            else if ((stablecoinsFromAsset + amount) * 1e9 > maxValueScaled)
                amount = maxValueScaled / 1e9 - stablecoinsFromAsset;
        } else {
            // In this case, exposure after the operation might remain slightly below the targetExposure as less
            // collateral may be obtained by burning stablecoins for the yield asset and unwrapping it
            amount = targetExposureScaled / 1e9 - stablecoinsFromCollateral;
            uint256 minValueScaled = collatInfo.minExposureYieldAsset * stablecoinsIssued;
            if (stablecoinsFromAsset * 1e9 < minValueScaled) amount = 0;
            else if (stablecoinsFromAsset * 1e9 < minValueScaled + amount * 1e9)
                amount = stablecoinsFromAsset - minValueScaled / 1e9;
        }
    }

    function _setCollateralData(
        address collateral,
        address asset,
        uint64 targetExposure,
        uint64 minExposureYieldAsset,
        uint64 maxExposureYieldAsset,
        uint64 overrideExposures
    ) internal virtual {
        CollatParams storage collatInfo = collateralData[collateral];
        collatInfo.asset = asset;
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

    function _updateLimitExposuresYieldAsset(CollatParams storage collatInfo) internal virtual {
        uint64[] memory xFeeMint;
        (xFeeMint, ) = transmuter.getCollateralMintFees(collatInfo.asset);
        uint256 length = xFeeMint.length;
        if (length <= 1) collatInfo.maxExposureYieldAsset = 1e9;
        else collatInfo.maxExposureYieldAsset = xFeeMint[length - 2];

        uint64[] memory xFeeBurn;
        (xFeeBurn, ) = transmuter.getCollateralBurnFees(collatInfo.asset);
        length = xFeeBurn.length;
        if (length <= 1) collatInfo.minExposureYieldAsset = 0;
        else collatInfo.minExposureYieldAsset = xFeeBurn[length - 2];
    }

    function _setMaxSlippage(uint96 newMaxSlippage) internal virtual {
        if (newMaxSlippage > 1e9) revert InvalidParam();
        maxSlippage = newMaxSlippage;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        HELPER                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _adjustAllowance(address token, address sender, uint256 amountIn) internal {
        uint256 allowance = IERC20(token).allowance(address(this), sender);
        if (allowance < amountIn) IERC20(token).safeIncreaseAllowance(sender, type(uint256).max - allowance);
    }
}
