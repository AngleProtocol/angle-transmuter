// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import "oz/interfaces/IERC20.sol";
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
        // Premium paid (in `BASE_9`)
        uint256 premium;
    }

    /// @notice Reference to the `transmuter` implementation this contract aims at rebalancing
    ITransmuter public immutable transmuter;
    /// @notice AgToken handled by the `transmuter` of interest. This is the token given as an incentive token
    /// to market makers rebalancing the reserves of the protocol
    address public immutable agToken;
    /// @notice Maps a `(tokenIn,tokenOut)` pair to details about the subsidy potentially provided on
    /// `tokenIn` to `tokenOut` rebalances
    mapping(address tokenIn => mapping(address tokenOut => Order)) public orders;
    /// @notice Gives the total subsidy budget
    uint256 public budget;

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
    /// of `agToken` based on the `orders` set by governance
    /// @param amountIn Amount of `tokenIn` to bring for the rebalancing
    /// @param amountOutMin Minimum amount of `tokenOut`that must be obtained from the swap
    /// @param subsidyOutMin Minimum subsidy amount in `agToken` to obtain from the swap
    /// @param to Address to which `tokenOut` must be sent
    /// @param deadline Timestamp before which this transaction must be included
    /// @return amountOut Amount of outToken obtained
    /// @return subsidy Amount of agToken given as a subsidy for the swap
    /// @dev Contrarily to what is done in the Transmuter contract, here neither of `tokenIn` or `tokenOut`
    /// should be an `agToken`
    function swapExactInput(
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 subsidyOutMin,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut, uint256 subsidy) {
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
        // Based on the `amountAgToken` obtained, checking whether this is eligible to a subsidy
        subsidy = _computeSubsidy(tokenIn, tokenOut, amountAgToken);
        if (subsidy < subsidyOutMin) revert TooSmallAmountOut();
        // Then, burn the minted agToken to `tokenOut`
        amountOut = transmuter.swapExactInput(amountAgToken, amountOutMin, agToken, tokenOut, to, deadline);
        if (subsidy > 0) {
            // Everytime a subsidy takes place, the total subsidy budget must be reduced
            orders[tokenIn][tokenOut].subsidyBudget -= subsidy;
            budget -= subsidy;
            IERC20(agToken).safeTransfer(to, subsidy);
        }
    }

    /// @notice Approximates how much a call to `swapExactInput` with the same parameters would yield in terms
    /// of `amountOut` and `subsidy`
    /// @dev This function returns an approximation and not an exact value as the first mint to compute `amountAgToken`
    /// might change the state of the fees slope within the Transmuter that will then be taken into account when
    /// burning the minted agToken
    function quoteIn(
        uint256 amountIn,
        address tokenIn,
        address tokenOut
    ) external view returns (uint256 amountOut, uint256 subsidy) {
        uint256 amountAgToken = transmuter.quoteIn(amountIn, tokenIn, agToken);
        amountOut = transmuter.quoteIn(amountAgToken, agToken, tokenOut);
        subsidy = _computeSubsidy(tokenIn, tokenOut, amountAgToken);
    }

    /// @notice Computes based on the subsidy budget how many `agToken` can be obtained from a `tokenIn`
    /// swap to `tokenOut` as a subsidy
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
    /// @dev Before calling this function, governance must make sure that there are enough `agToken` idle
    /// in the contract to sponsor the swaps
    function setOrder(address tokenIn, address tokenOut, uint256 subsidyBudget, uint256 premium) external onlyGuardian {
        Order storage order = orders[tokenIn][tokenOut];
        uint256 newBudget = budget + subsidyBudget - order.subsidyBudget;
        if (IERC20(agToken).balanceOf(address(this)) < newBudget) revert InvalidParam();
        budget = newBudget;
        order.subsidyBudget = subsidyBudget;
        order.premium = premium;
    }

    /// @notice Recovers `amount` of `token` to the `to` address
    /// @dev This function checks if too much is not being recovered with respect to currently available budgets
    function recover(address token, uint256 amount, address to) external onlyGuardian {
        if (token == address(agToken) && IERC20(token).balanceOf(address(this)) < budget + amount)
            revert InvalidParam();
        IERC20(token).safeTransfer(to, amount);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       INTERNAL                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Computes the subsidy for a swap of `tokenIn` to `tokenOut` which yielded an intermediary amount
    /// of `amountAgToken` agToken
    function _computeSubsidy(
        address tokenIn,
        address tokenOut,
        uint256 amountAgToken
    ) internal view returns (uint256 subsidy) {
        Order memory order = orders[tokenIn][tokenOut];
        subsidy = (amountAgToken * order.premium) / BASE_9;
        if (subsidy > order.subsidyBudget) subsidy = order.subsidyBudget;
    }
}
