// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import "oz/interfaces/IERC20.sol";
import "oz/interfaces/IERC20Metadata.sol";
import "oz/token/ERC20/utils/SafeERC20.sol";

import { ITransmuter } from "interfaces/ITransmuter.sol";

import { AccessControl, IAccessControlManager } from "../utils/AccessControl.sol";
import "../utils/Constants.sol";
import "../utils/Errors.sol";

/// @title Rebalancer
/// @author Angle Labs, Inc.
/// @notice Contract market makers building on top of Angle can use to rebalance the reserves of the protocol
contract Rebalancer is AccessControl {
    using SafeERC20 for IERC20;

    struct Order {
        // Total agToken budget allocated to subsidize the swaps between the tokens associated to the order
        uint256 subsidyBudget;
        // Guaranteed exchange rate in `BASE_18` for the swaps between the `tokenIn` and `tokenOut` associated to
        // the order. This rate is a minimum rate guaranteed up to when the subsidyBudget is fully consumed
        uint256 guaranteedRate;
    }

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

    /// @notice Initializes the immutable variables of the contract, namely `accessControlManager` and `transmuter`
    constructor(IAccessControlManager _accessControlManager, ITransmuter _transmuter) {
        if (address(_accessControlManager) == address(0)) revert ZeroAddress();
        accessControlManager = _accessControlManager;
        transmuter = _transmuter;
        agToken = address(_transmuter.agToken());
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                 REBALANCING FUNCTIONS                                              
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Swaps `tokenIn` for `tokenOut` through an intermediary agToken mint from `tokenIn` and
    /// burn to `tokenOut`. Eventually, this transaction may be sponsored and yield an amount of `tokenOut`
    /// higher than what would be obtained through a mint and burn directly on the `transmuter`
    /// @param amountIn Amount of `tokenIn` to bring for the rebalancing
    /// @param amountOutMin Minimum amount of `tokenOut` that must be obtained from the swap
    /// @param to Address to which `tokenOut` must be sent
    /// @param deadline Timestamp before which this transaction must be included
    /// @return amountOut Amount of outToken obtained
    /// @dev Contrarily to what is done in the Transmuter contract, here neither of `tokenIn` or `tokenOut`
    /// should be an `agToken`
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
            orders[tokenIn][tokenOut].subsidyBudget -= subsidy;
            budget -= subsidy;
            amountAgToken += subsidy;
        }
        amountOut = transmuter.swapExactInput(amountAgToken, amountOutMin, agToken, tokenOut, to, deadline);
    }

    /// @notice Approximates how much a call to `swapExactInput` with the same parameters would yield in terms
    /// of `amountOut` and `subsidy`
    /// @dev This function returns an approximation and not an exact value as the first mint to compute `amountAgToken`
    /// might change the state of the fees slope within the Transmuter that will then be taken into account when
    /// burning the minted agToken.
    function quoteIn(uint256 amountIn, address tokenIn, address tokenOut) external view returns (uint256 amountOut) {
        uint256 amountAgToken = transmuter.quoteIn(amountIn, tokenIn, agToken);
        amountAgToken += _getSubsidyAmount(tokenIn, tokenOut, amountAgToken, amountIn);
        amountOut = transmuter.quoteIn(amountAgToken, agToken, tokenOut);
    }

    /// @notice Helper to compute the minimum guaranteed amount out that would be obtained from a swap of `amountIn`
    /// of `tokenIn` to `tokenOut`
    /// @dev Note that this minimum amount is guaranteed up to the subsidy budget, and if for a swap the subsidy budget
    /// is not big enough to provide this guaranteed amount out, then less will actually be obtained
    function getGuaranteedAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256) {
        return _getGuaranteedAmountOut(tokenIn, tokenOut, amountIn, orders[tokenIn][tokenOut].guaranteedRate);
    }

    /// @notice Internal version of `_getGuaranteedAmountOut`
    function _getGuaranteedAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 guaranteedRate
    ) internal view returns (uint256 amountOut) {
        return
            (amountIn * guaranteedRate * (10 ** IERC20Metadata(tokenOut).decimals())) /
            (1e18 * (10 ** IERC20Metadata(tokenIn).decimals()));
    }

    /// @notice Computes the additional subsidy amount in agToken that must be added during the process of a swap
    /// of `amountIn` of `tokenIn` to `tokenOut`
    function _getSubsidyAmount(
        address tokenIn,
        address tokenOut,
        uint256 amountAgToken,
        uint256 amountIn
    ) internal view returns (uint256 subsidy) {
        Order memory order = orders[tokenIn][tokenOut];
        uint256 guaranteedAmountOut = _getGuaranteedAmountOut(tokenIn, tokenOut, amountIn, order.guaranteedRate);
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

    /// @notice Lets governance set an order to subsidize rebalances between `tokenIn` and `tokenOut`
    /// @dev Before calling this function, governance must make sure that there are enough `agToken` idle
    /// in the contract to sponsor the swaps
    function setOrder(
        address tokenIn,
        address tokenOut,
        uint256 subsidyBudget,
        uint256 guaranteedRate
    ) external onlyGuardian {
        // If a token has 0 decimals on the Transmuter, then it's not an actual collateral
        if (transmuter.getCollateralDecimals(tokenIn) == 0 || transmuter.getCollateralDecimals(tokenOut) == 0)
            revert NotCollateral();
        Order storage order = orders[tokenIn][tokenOut];
        uint256 newBudget = budget + subsidyBudget - order.subsidyBudget;
        if (IERC20(agToken).balanceOf(address(this)) < newBudget) revert InvalidParam();
        budget = newBudget;
        order.subsidyBudget = subsidyBudget;
        order.guaranteedRate = guaranteedRate;
    }

    /// @notice Recovers `amount` of `token` to the `to` address
    /// @dev This function checks if too much is not being recovered with respect to currently available budgets
    function recover(address token, uint256 amount, address to) external onlyGuardian {
        if (token == address(agToken) && IERC20(token).balanceOf(address(this)) < budget + amount)
            revert InvalidParam();
        IERC20(token).safeTransfer(to, amount);
    }
}
