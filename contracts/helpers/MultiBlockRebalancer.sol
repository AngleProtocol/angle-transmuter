// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

import { AccessControl, IAccessControlManager } from "../utils/AccessControl.sol";
import { IAgToken } from "../interfaces/IAgToken.sol";
import { IPool } from "../interfaces/IPool.sol";
import { ITransmuter } from "../interfaces/ITransmuter.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../utils/Errors.sol";
import "../utils/Constants.sol";

struct CollatParams {
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

contract MultiBlockRebalancer is AccessControl {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       MODIFIERS
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    modifier onlyTrusted() {
        if (!isTrusted[msg.sender]) revert NotTrusted();
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       VARIABLES
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice address to deposit to receive collateral
    mapping(address => address) public collateralToDepositAddress;
    /// @notice Data associated to a collateral
    mapping(address => CollatParams) public collateralData;
    /// @notice trusted addresses
    mapping(address => bool) public isTrusted;

    /// @notice Maximum amount of stablecoins that can be minted in a single transaction
    uint256 public maxMintAmount;
    ITransmuter public transmuter;
    IAgToken public agToken;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    constructor(
        uint256 initialMaxMintAmount,
        IAccessControlManager definitiveAccessControlManager,
        IAgToken definitiveAgToken,
        ITransmuter definitivetransmuter
    ) {
        maxMintAmount = initialMaxMintAmount;
        accessControlManager = definitiveAccessControlManager;
        agToken = definitiveAgToken;
        transmuter = definitivetransmuter;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        GOVERNOR FUNCTIONS
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the maximum amount of stablecoins that can be minted in a single transaction
     * @param newMaxMintAmount new maximum amount of stablecoins that can be minted in a single transaction
     */
    function setMaxMintAmount(uint256 newMaxMintAmount) external onlyGovernor {
        maxMintAmount = newMaxMintAmount;
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
        CollatParams storage collatInfo = collateralData[collateral];
        if (targetExposure >= 1e9) revert InvalidParam();
        collatInfo.targetExposure = targetExposure;
        collatInfo.overrideExposures = overrideExposures;
        if (overrideExposures == 1) {
            if (maxExposureYieldAsset >= 1e9 || minExposureYieldAsset >= maxExposureYieldAsset) revert InvalidParam();
            collatInfo.maxExposureYieldAsset = maxExposureYieldAsset;
            collatInfo.minExposureYieldAsset = minExposureYieldAsset;
        } else {
            collatInfo.overrideExposures = 2;
            _updateLimitExposuresYieldAsset(collateral, collatInfo);
        }
    }

    /**
     * @notice Set the deposit address for a collateral
     * @param collateral address of the collateral
     * @param newDepositAddress address to deposit to receive collateral
     */
    function setCollateralToDepositAddress(address collateral, address newDepositAddress) external onlyGuardian {
        collateralToDepositAddress[collateral] = newDepositAddress;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        TRUSTED FUNCTIONS
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Initiate a rebalance
     * @param scale scale to apply to the rebalance amount
     * @param collateral address of the collateral
     */
    function initiateRebalance(uint256 scale, address collateral) external onlyTrusted {
        if (scale > 1e9) revert InvalidParam();
        (uint8 increase, uint256 amount) = _computeRebalanceAmount(collateral);
        amount = (amount * scale) / 1e9;

        try transmuter.updateOracle(collateral) {} catch {}
        _rebalance(increase, collateral, amount);
    }

    /**
     * @notice Finalize a rebalance
     * @param collateral address of the collateral
     */
    function finalizeRebalance(address collateral) external onlyTrusted {
        uint256 balance = IERC20(collateral).balanceOf(address(this));

        try transmuter.updateOracle(collateral) {} catch {}
        _adjustAllowance(address(agToken), address(transmuter), balance);
        uint256 amountOut = transmuter.swapExactInput(
            balance,
            0,
            collateral,
            address(agToken),
            address(this),
            block.timestamp
        );
        agToken.burnSelf(amountOut, address(this));
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _computeRebalanceAmount(address collateral) internal view returns (uint8 increase, uint256 amount) {
        (uint256 stablecoinsFromCollateral, uint256 stablecoinsIssued) = transmuter.getIssuedByCollateral(collateral);
        CollatParams memory collatInfo = collateralData[collateral];
        (uint256 stablecoinsFromAsset, ) = transmuter.getIssuedByCollateral(collateral);
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

    function _rebalance(uint8 typeAction, address collateral, uint256 amount) internal {
        if (amount > maxMintAmount) revert TooBigAmountIn();
        agToken.mint(address(this), amount);
        if (typeAction == 1) {
            _adjustAllowance(address(agToken), address(transmuter), amount);
            address depositAddresss = collateralToDepositAddress[collateral];

            if (collateral == XEVT) {
                uint256 amountOut = transmuter.swapExactInput(
                    amount,
                    0,
                    address(agToken),
                    EURC,
                    address(this),
                    block.timestamp
                );
                _adjustAllowance(collateral, address(depositAddresss), amountOut);
                (uint256 shares, ) = IPool(depositAddresss).deposit(amountOut, address(this));
                amountOut = transmuter.swapExactInput(
                    shares,
                    0,
                    collateral,
                    address(agToken),
                    address(this),
                    block.timestamp
                );
                agToken.burnSelf(amountOut, address(this));
            } else if (collateral == USDM) {
                uint256 amountOut = transmuter.swapExactInput(
                    amount,
                    0,
                    address(agToken),
                    USDC,
                    address(this),
                    block.timestamp
                );
                _adjustAllowance(collateral, address(depositAddresss), amountOut);
                IERC20(collateral).transfer(depositAddresss, amountOut);
            }
        } else {
            _adjustAllowance(address(agToken), address(transmuter), amount);
            uint256 amountOut = transmuter.swapExactInput(
                amount,
                0,
                address(agToken),
                collateral,
                address(this),
                block.timestamp
            );
            address depositAddresss = collateralToDepositAddress[collateral];

            if (collateral == XEVT) {
                IPool(depositAddresss).requestRedeem(amountOut);
            } else if (collateral == USDM) {
                IERC20(collateral).transfer(depositAddresss, amountOut);
            }
        }
    }

    function _updateLimitExposuresYieldAsset(address collateral, CollatParams storage collatInfo) internal virtual {
        uint64[] memory xFeeMint;
        (xFeeMint, ) = transmuter.getCollateralMintFees(collateral);
        uint256 length = xFeeMint.length;
        if (length <= 1) collatInfo.maxExposureYieldAsset = 1e9;
        else collatInfo.maxExposureYieldAsset = xFeeMint[length - 2];

        uint64[] memory xFeeBurn;
        (xFeeBurn, ) = transmuter.getCollateralBurnFees(collateral);
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
