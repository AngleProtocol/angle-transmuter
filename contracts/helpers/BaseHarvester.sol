// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControl, IAccessControlManager } from "../utils/AccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ITransmuter } from "../interfaces/ITransmuter.sol";
import { IAgToken } from "../interfaces/IAgToken.sol";

import "../utils/Errors.sol";
import "../interfaces/IHarvester.sol";

struct YieldBearingParams {
    // Address of the stablecoin (ex: USDC)
    address stablecoin;
    // Target exposure to the collateral yield bearing asset used
    uint64 targetExposure;
    // Maximum exposure within the Transmuter to the stablecoin asset
    uint64 maxExposure;
    // Minimum exposure within the Transmuter to the stablecoin asset
    uint64 minExposure;
    // Whether limit exposures should be overriden or read onchain through the Transmuter
    // This value should be 1 to override exposures or 2 if these shouldn't be overriden
    uint64 overrideExposures;
}

/// @title BaseHarvester
/// @author Angle Labs, Inc.
/// @dev Abstract contract for a harvester that aims at rebalancing a Transmuter
abstract contract BaseHarvester is IHarvester, AccessControl {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       MODIFIERS
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    modifier onlyAllowed() {
        if (!isAllowed[msg.sender]) revert NotTrusted();
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       VARIABLES
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Reference to the `transmuter` implementation this contract aims at rebalancing
    ITransmuter public immutable transmuter;
    /// @notice AgToken handled by the `transmuter` of interest
    IAgToken public immutable agToken;
    /// @notice Max slippage when dealing with the Transmuter
    uint96 public maxSlippage;
    /// @notice Data associated to a yield bearing asset
    mapping(address => YieldBearingParams) public yieldBearingData;
    /// @notice Whether an address is allowed to update the target exposure of a yield bearing asset
    mapping(address => bool) public isAllowed;

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
     * @notice Set the yieldBearingAsset data
     * @param yieldBearingAsset address of the yieldBearingAsset
     * @param stablecoin address of the stablecoin
     * @param targetExposure target exposure to the yieldBearingAsset asset used
     * @param minExposure minimum exposure within the Transmuter to the stablecoin
     * @param maxExposure maximum exposure within the Transmuter to the stablecoin
     * @param overrideExposures whether limit exposures should be overriden or read onchain through the Transmuter
     */
    function setYieldBearingAssetData(
        address yieldBearingAsset,
        address stablecoin,
        uint64 targetExposure,
        uint64 minExposure,
        uint64 maxExposure,
        uint64 overrideExposures
    ) external onlyGuardian {
        _setYieldBearingAssetData(
            yieldBearingAsset,
            stablecoin,
            targetExposure,
            minExposure,
            maxExposure,
            overrideExposures
        );
    }

    /**
     * @notice Set the limit exposures to the stablecoin linked to the yield bearing asset
     * @param yieldBearingAsset address of the yield bearing asset
     */
    function updateLimitExposuresYieldAsset(address yieldBearingAsset) public virtual {
        YieldBearingParams storage yieldBearingInfo = yieldBearingData[yieldBearingAsset];
        if (yieldBearingInfo.overrideExposures == 2)
            _updateLimitExposuresYieldAsset(yieldBearingInfo.stablecoin, yieldBearingInfo);
    }

    /**
     * @notice Set the max allowed slippage
     * @param newMaxSlippage new max allowed slippage
     */
    function setMaxSlippage(uint96 newMaxSlippage) external onlyGuardian {
        _setMaxSlippage(newMaxSlippage);
    }

    /**
     * @notice add an address to the allowed list
     * @param account address to be added
     */
    function toggleAllowed(address account) external onlyGuardian {
        isAllowed[account] = !isAllowed[account];
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        ALLOWED FUNCTIONS
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the target exposure of a yield bearing asset
     * @param yieldBearingAsset address of the yield bearing asset
     * @param targetExposure target exposure to the yield bearing asset used
     */
    function setTargetExposure(address yieldBearingAsset, uint64 targetExposure) external onlyAllowed {
        yieldBearingData[yieldBearingAsset].targetExposure = targetExposure;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Compute the amount needed to rebalance the Transmuter
     * @param yieldBearingAsset address of the yield bearing asset
     * @return increase whether the exposure should be increased
     * @return amount amount to be rebalanced
     */
    function computeRebalanceAmount(address yieldBearingAsset) external view returns (uint8 increase, uint256 amount) {
        return _computeRebalanceAmount(yieldBearingAsset, yieldBearingData[yieldBearingAsset]);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _computeRebalanceAmount(
        address yieldBearingAsset,
        YieldBearingParams memory yieldBearingInfo
    ) internal view returns (uint8 increase, uint256 amount) {
        (uint256 stablecoinsFromYieldBearingAsset, uint256 stablecoinsIssued) = transmuter.getIssuedByCollateral(
            yieldBearingAsset
        );
        (uint256 stablecoinsFromStablecoin, ) = transmuter.getIssuedByCollateral(yieldBearingInfo.stablecoin);
        uint256 targetExposureScaled = yieldBearingInfo.targetExposure * stablecoinsIssued;
        if (stablecoinsFromYieldBearingAsset * 1e9 > targetExposureScaled) {
            // Need to decrease exposure to yield bearing asset
            amount = stablecoinsFromYieldBearingAsset - targetExposureScaled / 1e9;
            uint256 maxValueScaled = yieldBearingInfo.maxExposure * stablecoinsIssued;
            // These checks assume that there are no transaction fees on the stablecoin->collateral conversion and so
            // it's still possible that exposure goes above the max exposure in some rare cases
            if (stablecoinsFromStablecoin * 1e9 > maxValueScaled) amount = 0;
            else if ((stablecoinsFromStablecoin + amount) * 1e9 > maxValueScaled)
                amount = maxValueScaled / 1e9 - stablecoinsFromStablecoin;
        } else {
            // In this case, exposure after the operation might remain slightly below the targetExposure as less
            // collateral may be obtained by burning stablecoins for the yield asset and unwrapping it
            increase = 1;
            amount = targetExposureScaled / 1e9 - stablecoinsFromYieldBearingAsset;
            uint256 minValueScaled = yieldBearingInfo.minExposure * stablecoinsIssued;
            if (stablecoinsFromStablecoin * 1e9 < minValueScaled) amount = 0;
            else if (stablecoinsFromStablecoin * 1e9 < minValueScaled + amount * 1e9)
                amount = stablecoinsFromStablecoin - minValueScaled / 1e9;
        }
    }

    function _setYieldBearingAssetData(
        address yieldBearingAsset,
        address stablecoin,
        uint64 targetExposure,
        uint64 minExposure,
        uint64 maxExposure,
        uint64 overrideExposures
    ) internal virtual {
        YieldBearingParams storage yieldBearingInfo = yieldBearingData[yieldBearingAsset];
        yieldBearingInfo.stablecoin = stablecoin;
        if (targetExposure >= 1e9) revert InvalidParam();
        yieldBearingInfo.targetExposure = targetExposure;
        yieldBearingInfo.overrideExposures = overrideExposures;
        if (overrideExposures == 1) {
            if (maxExposure >= 1e9 || minExposure >= maxExposure) revert InvalidParam();
            yieldBearingInfo.maxExposure = maxExposure;
            yieldBearingInfo.minExposure = minExposure;
        } else {
            yieldBearingInfo.overrideExposures = 2;
            _updateLimitExposuresYieldAsset(yieldBearingInfo.stablecoin, yieldBearingInfo);
        }
    }

    function _updateLimitExposuresYieldAsset(
        address stablecoin,
        YieldBearingParams storage yieldBearingInfo
    ) internal virtual {
        uint64[] memory xFeeMint;
        (xFeeMint, ) = transmuter.getCollateralMintFees(stablecoin);
        uint256 length = xFeeMint.length;
        if (length <= 1) yieldBearingInfo.maxExposure = 1e9;
        else yieldBearingInfo.maxExposure = xFeeMint[length - 2];

        uint64[] memory xFeeBurn;
        (xFeeBurn, ) = transmuter.getCollateralBurnFees(stablecoin);
        length = xFeeBurn.length;
        if (length <= 1) yieldBearingInfo.minExposure = 0;
        else yieldBearingInfo.minExposure = xFeeBurn[length - 2];
    }

    function _setMaxSlippage(uint96 newMaxSlippage) internal virtual {
        if (newMaxSlippage > 1e9) revert InvalidParam();
        maxSlippage = newMaxSlippage;
    }

    function _scaleAmountBasedOnDecimals(
        uint256 decimalsTokenIn,
        uint256 decimalsTokenOut,
        uint256 amountIn,
        bool assetIn
    ) internal pure returns (uint256) {
        if (decimalsTokenIn > decimalsTokenOut) {
            if (assetIn) {
                amountIn /= 10 ** (decimalsTokenIn - decimalsTokenOut);
            } else {
                amountIn *= 10 ** (decimalsTokenIn - decimalsTokenOut);
            }
        } else if (decimalsTokenIn < decimalsTokenOut) {
            if (assetIn) {
                amountIn *= 10 ** (decimalsTokenOut - decimalsTokenIn);
            } else {
                amountIn /= 10 ** (decimalsTokenOut - decimalsTokenIn);
            }
        }
        return amountIn;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        HELPER                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _adjustAllowance(address token, address sender, uint256 amountIn) internal {
        uint256 allowance = IERC20(token).allowance(address(this), sender);
        if (allowance < amountIn) IERC20(token).safeIncreaseAllowance(sender, type(uint256).max - allowance);
    }
}
