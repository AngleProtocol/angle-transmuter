// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

import { SafeCast } from "oz/utils/math/SafeCast.sol";
import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "oz/interfaces/IERC20.sol";

import { ITransmuter } from "interfaces/ITransmuter.sol";

import { AccessControl, IAccessControlManager } from "../utils/AccessControl.sol";
import "../utils/Constants.sol";
import "../utils/Errors.sol";

import { IERC3156FlashBorrower } from "oz/interfaces/IERC3156FlashBorrower.sol";
import { IERC3156FlashLender } from "oz/interfaces/IERC3156FlashLender.sol";

struct CollatParams {
    // Yield bearing asset associated to the collateral
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

/// @title GenericHarvester
/// @author Angle Labs, Inc.
/// @dev Generic contract for anyone to permissionlessly adjust the reserves of Angle Transmuter
contract GenericHarvester is AccessControl, IERC3156FlashBorrower {
    using SafeCast for uint256;
    using SafeERC20 for IERC20;
    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    /// @notice Angle stablecoin flashloan contract
    IERC3156FlashLender public immutable FLASHLOAN;

    /// @notice Reference to the `transmuter` implementation this contract aims at rebalancing
    ITransmuter public immutable TRANSMUTER;
    /// @notice AgToken handled by the `transmuter` of interest
    address public immutable AGTOKEN;
    /// @notice Max slippage when dealing with the Transmuter
    uint96 public maxSlippage;
    /// @notice Data associated to a collateral
    mapping(address => CollatParams) public collateralData;
    /// @notice Budget of AGToken available for each users
    mapping(address => uint256) public budget;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    INITIALIZATION                                                  
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    constructor(
        address transmuter,
        address collateral,
        address asset,
        address flashloan,
        uint64 targetExposure,
        uint64 overrideExposures,
        uint64 maxExposureYieldAsset,
        uint64 minExposureYieldAsset,
        uint96 _maxSlippage
    ) {
        if (flashloan == address(0)) revert ZeroAddress();
        FLASHLOAN = IERC3156FlashLender(flashloan);
        TRANSMUTER = ITransmuter(transmuter);
        AGTOKEN = address(ITransmuter(transmuter).agToken());

        IERC20(AGTOKEN).safeApprove(flashloan, type(uint256).max);
        accessControlManager = IAccessControlManager(ITransmuter(transmuter).accessControlManager());
        _setCollateralData(
            collateral,
            asset,
            targetExposure,
            minExposureYieldAsset,
            maxExposureYieldAsset,
            overrideExposures
        );
        _setMaxSlippage(_maxSlippage);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        REBALANCE                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Burns `amountStablecoins` for one collateral asset, swap for asset then mints stablecoins
    /// from the proceeds of the swap.
    /// @dev If `increase` is 1, then the system tries to increase its exposure to the yield bearing asset which means
    /// burning stablecoin for the liquid asset, swapping for the yield bearing asset, then minting the stablecoin
    /// @dev This function reverts if the second stablecoin mint gives less than `minAmountOut` of stablecoins
    /// @dev This function reverts if the swap slippage is higher than `maxSlippage`
    function adjustYieldExposure(
        uint256 amountStablecoins,
        uint8 increase,
        address collateral,
        address asset,
        uint256 minAmountOut,
        bytes calldata extraData
    ) public virtual {
        FLASHLOAN.flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(AGTOKEN),
            amountStablecoins,
            abi.encode(msg.sender, increase, collateral, asset, minAmountOut, extraData)
        );
    }

    /// @inheritdoc IERC3156FlashBorrower
    function onFlashLoan(
        address initiator,
        address,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) public virtual returns (bytes32) {
        if (msg.sender != address(FLASHLOAN) || initiator != address(this) || fee != 0) revert NotTrusted();
        (
            address sender,
            uint256 typeAction,
            address collateral,
            address asset,
            uint256 minAmountOut,
            bytes memory callData
        ) = abi.decode(data, (address, uint256, address, address, uint256, bytes));
        address tokenOut;
        address tokenIn;
        if (typeAction == 1) {
            // Increase yield exposure action: we bring in the yield bearing asset
            tokenOut = collateral;
            tokenIn = asset;
        } else {
            // Decrease yield exposure action: we bring in the liquid asset
            tokenIn = collateral;
            tokenOut = asset;
        }
        uint256 amountOut = TRANSMUTER.swapExactInput(amount, 0, AGTOKEN, tokenOut, address(this), block.timestamp);

        // Swap to tokenIn
        amountOut = _swapToTokenIn(typeAction, tokenIn, tokenOut, amountOut, callData);

        _adjustAllowance(tokenIn, address(TRANSMUTER), amountOut);
        uint256 amountStableOut = TRANSMUTER.swapExactInput(
            amountOut,
            minAmountOut,
            tokenIn,
            AGTOKEN,
            address(this),
            block.timestamp
        );
        if (amount > amountStableOut) {
            // TODO temporary fix for for subsidy as stack too deep
            if (budget[sender] < amount - amountStableOut) revert InsufficientFunds();
            budget[sender] -= amount - amountStableOut;
        }
        return CALLBACK_SUCCESS;
    }

    /**
     * @notice Add budget to a receiver
     * @param amount amount of AGToken to add to the budget
     * @param receiver address of the receiver
     */
    function addBudget(uint256 amount, address receiver) public virtual {
        IERC20(AGTOKEN).safeTransferFrom(msg.sender, address(this), amount);

        budget[receiver] += amount;
    }

    /**
     * @notice Remove budget from a receiver
     * @param amount amount of AGToken to remove from the budget
     * @param receiver address of the receiver
     */
    function removeBudget(uint256 amount, address receiver) public virtual {
        if (budget[receiver] < amount) revert InsufficientFunds();
        budget[receiver] -= amount;

        IERC20(AGTOKEN).safeTransfer(receiver, amount);
    }

    /**
     * @dev hook to swap from tokenOut to tokenIn
     * @param typeAction 1 for deposit, 2 for redeem
     * @param tokenIn address of the token to swap
     * @param tokenOut address of the token to receive
     * @param amount amount of token to swap
     * @param callData extra call data (if needed)
     */
    function _swapToTokenIn(
        uint256 typeAction,
        address tokenIn,
        address tokenOut,
        uint256 amount,
        bytes memory callData
    ) internal virtual returns (uint256) {}

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        HARVEST                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Invests or divests from the yield asset associated to `collateral` based on the current exposure to this
    /// collateral
    /// @dev This transaction either reduces the exposure to `collateral` in the Transmuter or frees up some collateral
    /// that can then be used for people looking to burn stablecoins
    /// @dev Due to potential transaction fees within the Transmuter, this function doesn't exactly bring `collateral`
    /// to the target exposure
    function harvest(address collateral, uint256 scale, bytes calldata extraData) public virtual {
        if (scale > 1e9) revert InvalidParam();
        (uint256 stablecoinsFromCollateral, uint256 stablecoinsIssued) = TRANSMUTER.getIssuedByCollateral(collateral);
        CollatParams memory collatInfo = collateralData[collateral];
        (uint256 stablecoinsFromAsset, ) = TRANSMUTER.getIssuedByCollateral(collatInfo.asset);
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
        amount = (amount * scale) / 1e9;
        if (amount > 0) {
            try TRANSMUTER.updateOracle(collatInfo.asset) {} catch {}

            adjustYieldExposure(
                amount,
                increase,
                collateral,
                collatInfo.asset,
                (amount * (1e9 - maxSlippage)) / 1e9,
                extraData
            );
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        SETTERS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function setCollateralData(
        address collateral,
        address asset,
        uint64 targetExposure,
        uint64 minExposureYieldAsset,
        uint64 maxExposureYieldAsset,
        uint64 overrideExposures
    ) public virtual onlyGuardian {
        _setCollateralData(
            collateral,
            asset,
            targetExposure,
            minExposureYieldAsset,
            maxExposureYieldAsset,
            overrideExposures
        );
    }

    function setMaxSlippage(uint96 _maxSlippage) public virtual onlyGuardian {
        _setMaxSlippage(_maxSlippage);
    }

    function updateLimitExposuresYieldAsset(address collateral) public virtual {
        CollatParams storage collatInfo = collateralData[collateral];
        if (collatInfo.overrideExposures == 2) _updateLimitExposuresYieldAsset(collatInfo);
    }

    function _setMaxSlippage(uint96 _maxSlippage) internal virtual {
        if (_maxSlippage > 1e9) revert InvalidParam();
        maxSlippage = _maxSlippage;
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
        (xFeeMint, ) = TRANSMUTER.getCollateralMintFees(collatInfo.asset);
        uint256 length = xFeeMint.length;
        if (length <= 1) collatInfo.maxExposureYieldAsset = 1e9;
        else collatInfo.maxExposureYieldAsset = xFeeMint[length - 2];

        uint64[] memory xFeeBurn;
        (xFeeBurn, ) = TRANSMUTER.getCollateralBurnFees(collatInfo.asset);
        length = xFeeBurn.length;
        if (length <= 1) collatInfo.minExposureYieldAsset = 0;
        else collatInfo.minExposureYieldAsset = xFeeBurn[length - 2];
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        HELPER                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _adjustAllowance(address token, address sender, uint256 amountIn) internal {
        uint256 allowance = IERC20(token).allowance(address(this), sender);
        if (allowance < amountIn) IERC20(token).safeIncreaseAllowance(sender, type(uint256).max - allowance);
    }
}
