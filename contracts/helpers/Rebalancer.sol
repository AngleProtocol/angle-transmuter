// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import { IERC20 } from "oz/interfaces/IERC20.sol";
import { IERC20Metadata } from "oz/interfaces/IERC20Metadata.sol";
import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "oz/utils/math/SafeCast.sol";

import { ITransmuter } from "interfaces/ITransmuter.sol";
import { Order, IRebalancer } from "interfaces/IRebalancer.sol";

import { AccessControl, IAccessControlManager } from "../utils/AccessControl.sol";
import "../utils/Constants.sol";
import "../utils/Errors.sol";

/// @title Rebalancer
/// @author Angle Labs, Inc.
/// @notice Contract built to subsidize rebalances between collateral tokens
/// @dev This contract is meant to "wrap" the Transmuter contract and provide a way for governance to
/// subsidize rebalances between collateral tokens. Rebalances are done through 2 swaps collateral <> agToken.
/// @dev This contract is not meant to hold any transient funds aside from the rebalancing budget
contract Rebalancer is IRebalancer, AccessControl {
    event OrderSet(address indexed tokenIn, address indexed tokenOut, uint256 subsidyBudget, uint256 guaranteedRate);
    event SubsidyPaid(address indexed tokenIn, address indexed tokenOut, uint256 subsidy);

    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    /// @notice Reference to the `transmuter` implementation this contract aims at rebalancing
    ITransmuter public immutable transmuter;
    /// @notice AgToken handled by the `transmuter` of interest
    address public immutable agToken;
    /// @notice Maps a `(tokenIn,tokenOut)` pair to details about the subsidy potentially provided on
    /// `tokenIn` to `tokenOut` rebalances
    mapping(address tokenIn => mapping(address tokenOut => Order)) public orders;
    /// @notice Gives the total subsidy budget
    uint256 public budget;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    INITIALIZATION                                                  
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Initializes the immutable variables of the contract: `accessControlManager`, `transmuter` and `agToken`
    constructor(IAccessControlManager _accessControlManager, ITransmuter _transmuter) {
        if (address(_accessControlManager) == address(0)) revert ZeroAddress();
        accessControlManager = _accessControlManager;
        transmuter = _transmuter;
        agToken = address(_transmuter.agToken());
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                 REBALANCING FUNCTIONS                                              
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRebalancer
    /// @dev Contrarily to what is done in the Transmuter contract, here neither of `tokenIn` or `tokenOut`
    /// should be an `agToken`
    /// @dev Can be used even if the subsidy budget is 0, in which case it'll just do 2 Transmuter swaps
    /// @dev The invariant should be that `msg.sender` injects `amountIn` in the transmuter and either the
    /// subsidy is 0 either they receive a subsidy from this contract on top of the output Transmuter up to
    /// the guaranteed amount out
    function swapExactInput(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut) {
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        // First, dealing with the allowance of the rebalancer to the Transmuter: this allowance is made infinite
        // by default
        uint256 allowance = IERC20(tokenIn).allowance(address(this), address(transmuter));
        if (allowance < amountIn)
            IERC20(tokenIn).safeIncreaseAllowance(address(transmuter), type(uint256).max - allowance);
        // Mint agToken from `tokenIn`
        uint256 amountAgToken = transmuter.swapExactInput(
            amountIn,
            0,
            tokenIn,
            agToken,
            address(this),
            block.timestamp
        );
        // Computing if a potential subsidy must be included in the agToken amount to burn
        uint256 subsidy = _getSubsidyAmount(tokenIn, tokenOut, amountAgToken, amountIn);
        if (subsidy > 0) {
            orders[tokenIn][tokenOut].subsidyBudget -= subsidy.toUint112();
            budget -= subsidy;
            amountAgToken += subsidy;

            emit SubsidyPaid(tokenIn, tokenOut, subsidy);
        }
        amountOut = transmuter.swapExactInput(amountAgToken, amountOutMin, agToken, tokenOut, to, deadline);
    }

    /// @inheritdoc IRebalancer
    /// @dev This function returns an approximation and not an exact value as the first mint to compute `amountAgToken`
    /// might change the state of the fees slope within the Transmuter that will then be taken into account when
    /// burning the minted agToken.
    function quoteIn(uint256 amountIn, address tokenIn, address tokenOut) external view returns (uint256 amountOut) {
        uint256 amountAgToken = transmuter.quoteIn(amountIn, tokenIn, agToken);
        amountAgToken += _getSubsidyAmount(tokenIn, tokenOut, amountAgToken, amountIn);
        amountOut = transmuter.quoteIn(amountAgToken, agToken, tokenOut);
    }

    /// @inheritdoc IRebalancer
    /// @dev Note that this minimum amount is guaranteed up to the subsidy budget, and if for a swap the subsidy budget
    /// is not big enough to provide this guaranteed amount out, then less will actually be obtained
    function getGuaranteedAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256) {
        Order storage order = orders[tokenIn][tokenOut];
        return _getGuaranteedAmountOut(amountIn, order.guaranteedRate, order.decimalsIn, order.decimalsOut);
    }

    /// @notice Internal version of `_getGuaranteedAmountOut`
    function _getGuaranteedAmountOut(
        uint256 amountIn,
        uint256 guaranteedRate,
        uint8 decimalsIn,
        uint8 decimalsOut
    ) internal pure returns (uint256 amountOut) {
        return (amountIn * guaranteedRate * (10 ** decimalsOut)) / (BASE_18 * (10 ** decimalsIn));
    }

    /// @notice Computes the additional subsidy amount in agToken that must be added during the process of a swap
    /// of `amountIn` of `tokenIn` to `tokenOut`
    function _getSubsidyAmount(
        address tokenIn,
        address tokenOut,
        uint256 amountAgToken,
        uint256 amountIn
    ) internal view returns (uint256 subsidy) {
        Order storage order = orders[tokenIn][tokenOut];
        uint256 guaranteedAmountOut = _getGuaranteedAmountOut(
            amountIn,
            order.guaranteedRate,
            order.decimalsIn,
            order.decimalsOut
        );
        // Computing the amount of agToken that must be burnt to get the amountOut guaranteed
        if (guaranteedAmountOut > 0) {
            uint256 amountAgTokenNeeded = transmuter.quoteOut(guaranteedAmountOut, agToken, tokenOut);
            // If more agTokens than what has been obtained through the first mint must be burnt to get to the
            // guaranteed amountOut, we're taking it from the subsidy budget set
            if (amountAgToken < amountAgTokenNeeded) {
                subsidy = amountAgTokenNeeded - amountAgToken;

                // In the case where the subsidy budget is too small, we may not be able to provide the guaranteed
                // amountOut to the user
                if (subsidy > order.subsidyBudget) subsidy = order.subsidyBudget;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                      GOVERNANCE                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRebalancer
    /// @dev Before calling this function, governance must make sure that there are enough `agToken` idle
    /// in the contract to sponsor the swaps
    /// @dev This function can be used to decrease an order by overriding it
    function setOrder(
        address tokenIn,
        address tokenOut,
        uint256 subsidyBudget,
        uint256 guaranteedRate
    ) external onlyGuardian {
        uint8 decimalsIn = transmuter.getCollateralDecimals(tokenIn);
        uint8 decimalsOut = transmuter.getCollateralDecimals(tokenOut);
        // If a token has 0 decimals on the Transmuter, then it's not an actual collateral
        if (decimalsIn == 0 || decimalsOut == 0) revert NotCollateral();
        Order storage order = orders[tokenIn][tokenOut];
        uint256 newBudget = budget + subsidyBudget - order.subsidyBudget;
        if (IERC20(agToken).balanceOf(address(this)) < newBudget) revert InvalidParam();
        budget = newBudget;
        order.subsidyBudget = subsidyBudget.toUint112();
        order.decimalsIn = decimalsIn;
        order.decimalsOut = decimalsOut;
        order.guaranteedRate = guaranteedRate.toUint128();

        emit OrderSet(tokenIn, tokenOut, subsidyBudget, guaranteedRate);
    }

    /// @inheritdoc IRebalancer
    /// @dev This function checks if too much is not being recovered with respect to currently available budgets
    function recover(address token, uint256 amount, address to) external onlyGuardian {
        if (token == address(agToken) && IERC20(token).balanceOf(address(this)) < budget + amount)
            revert InvalidParam();
        IERC20(token).safeTransfer(to, amount);
    }
}
