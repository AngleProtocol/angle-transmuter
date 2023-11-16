// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import "oz/interfaces/IERC20.sol";
import "oz/token/ERC20/utils/SafeERC20.sol";

import { IAgToken } from "interfaces/IAgToken.sol";
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
        // Total budget allocated to subsidize the swaps between the tokens associated to the order
        uint256 subsidyBudget;
        // Premium paid (in `BASE_9`)
        uint256 premium;
    }

    /// @notice Reference to the `transmuter` implementation this contract aims at rebalancing
    ITransmuter public immutable transmuter;
    /// @notice AgToken handled by the `transmuter` of interest
    address public immutable agToken;
    /// @notice Maps a `(tokenIn,tokenOut)` pair to details about the subsidy potentially provided on
    /// `tokenIn` to `tokenOut` rebalances
    mapping(address tokenIn => mapping(address tokenOut => Order)) public orders;
    /// @notice Gives the total subsidy budget for each `tokenOut`
    mapping(address tokenOut => uint256 maxBudget) public budget;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    INITIALIZATION                                                  
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Initializes the immutable variables of the contract, namely `_accessControlManager` and `_transmuter`
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
    /// burn to `tokenOut`. Eventually, this transaction may be sponsored with an additional amount
    /// of `tokenOut` based on the `orders` set by governance
    /// @param amountIn Amount of `tokenIn` to bring for the rebalancing
    /// @param amountOutMin Minimum amount of `tokenOut`that must be obtained from the swap
    /// @param to Address to which `tokenOut` must be sent
    /// @param deadline Timestamp before which this transaction must be included
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
        // Dealing with the allowance of the rebalancer to the Transmuter: this allowance is made infinite by default
        uint256 allowance = IERC20(tokenIn).allowance(address(this), address(transmuter));
        if (allowance < amountIn)
            IERC20(tokenIn).safeIncreaseAllowance(address(transmuter), type(uint256).max - allowance);
        // First, mint agToken from `tokenIn`
        uint256 amountAgToken = transmuter.swapExactInput(
            amountIn,
            0,
            tokenIn,
            agToken,
            address(this),
            block.timestamp
        );
        // Then, burn the minted agToken to `tokenOut`
        amountOut = transmuter.swapExactInput(amountAgToken, 0, agToken, tokenOut, to, deadline);
        // Based on the `amountOut` obtained, checking whether this is eligible to a subsidy
        uint256 subsidy = _computeSubsidy(tokenIn, tokenOut, amountOut);
        if (subsidy > 0) {
            // Everytime a subsidy takes place, the total subsidy budget must be reduced
            orders[tokenIn][tokenOut].subsidyBudget -= subsidy;
            budget[tokenOut] -= subsidy;
            amountOut += subsidy;
            IERC20(tokenOut).safeTransfer(to, subsidy);
        }
        if (amountOut < amountOutMin) revert TooSmallAmountOut();
    }

    /// @notice Simulates how much a call to `swapExactInput` with the same parameters would yield in terms
    /// of `amountOut`
    function quoteIn(uint256 amountIn, address tokenIn, address tokenOut) external view returns (uint256) {
        uint256 amountAgToken = transmuter.quoteIn(amountIn, tokenIn, agToken);
        uint256 amountOut = transmuter.quoteIn(amountAgToken, agToken, tokenOut);
        return amountOut + _computeSubsidy(tokenIn, tokenOut, amountOut);
    }

    /// @notice Computes based on the subsidy budget how many `tokenOut` can be obtained from a `tokenIn` swap and
    /// still be eligible to a subsidy
    /// @dev This function returns an estimation and not a perfectly accurate value due to rounding
    function estimateAmountEligibleForIncentives(address tokenIn, address tokenOut) external view returns (uint256) {
        Order memory order = orders[tokenIn][tokenOut];
        if (order.premium == 0) return 0;
        else return (order.subsidyBudget * BASE_9) / order.premium;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                      GOVERNANCE                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Lets governance set an order to subsidize rebalances between `tokenIn` and `tokenOut`
    /// @dev Before calling this function, governance must make sure that there is enough of `tokenOut` idle
    /// in the contract to sponsor `tokenOut` swaps
    function setOrder(address tokenIn, address tokenOut, uint256 subsidyBudget, uint256 premium) external onlyGuardian {
        Order storage order = orders[tokenIn][tokenOut];
        uint256 newBudget = budget[tokenOut] + subsidyBudget - order.subsidyBudget;
        if (IERC20(tokenOut).balanceOf(address(this)) < newBudget) revert InvalidParam();
        budget[tokenOut] = newBudget;
        order.subsidyBudget = subsidyBudget;
        order.premium = premium;
    }

    /// @notice Recovers `amount` of `token` to the `to` address
    /// @dev This function checks if too much is not being recovered with respect to currently available budgets
    function recover(address token, uint256 amount, address to) external onlyGuardian {
        if (IERC20(token).balanceOf(address(this)) < budget[token] + amount) revert InvalidParam();
        IERC20(token).safeTransfer(to, amount);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       INTERNAL                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Computes the subsidy for a swap of `tokenIn` to `amountOut` of `tokenOut`
    function _computeSubsidy(
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) internal view returns (uint256 subsidy) {
        Order memory order = orders[tokenIn][tokenOut];
        subsidy = (amountOut * order.premium) / BASE_9;
        if (subsidy > order.subsidyBudget) subsidy = order.subsidyBudget;
    }
}
