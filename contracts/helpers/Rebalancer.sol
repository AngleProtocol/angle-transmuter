// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import { IAgToken } from "interfaces/IAgToken.sol";
import { ITransmuter } from "interfaces/ITransmuter.sol";

import "oz/interfaces/IERC20.sol";
import "oz/token/ERC20/utils/SafeERC20.sol";

import { AccessControl, IAccessControlManager } from "../utils/AccessControl.sol";
import "../utils/Errors.sol";

/// @title Rebalancer
/// @author Angle Labs, Inc.
/// @notice Contract market makers building on top of Angle can use to rebalance the resrves of the protocol
contract Rebalancer is AccessControl {
    using SafeERC20 for IERC20;

    struct Order {
        uint256 amountOutCovered;
        uint256 premium;
    }

    ITransmuter public immutable transmuter;
    address public immutable agToken;
    mapping(address tokenIn => mapping(address tokenOut => Order)) public orders;
    mapping(address tokenOut => uint256 maxBudget) public budget;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    INITIALIZATION                                                  
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    constructor(IAccessControlManager _accessControlManager, ITransmuter _transmuter) {
        if (address(_accessControlManager) == address(0) || address(_transmuter) == address(0)) revert ZeroAddress();
        accessControlManager = _accessControlManager;
        transmuter = _transmuter;
        agToken = address(_transmuter.agToken());
    }

    function swapExactInput(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut) {
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        uint256 amountAgToken = transmuter.swapExactInput(
            amountIn,
            0,
            tokenIn,
            agToken,
            address(this),
            block.timestamp
        );
        amountOut = transmuter.swapExactInput(amountAgToken, amountOutMin, agToken, tokenOut, to, deadline);
        (uint256 subsidy, uint256 newAmountCovered) = _computeSubsidy(tokenIn, tokenOut, amountOut);
        if (subsidy > 0) {
            orders[tokenIn][tokenOut].amountOutCovered = newAmountCovered;
            budget[tokenOut] -= subsidy;
            amountOut += subsidy;
            IERC20(tokenOut).safeTransfer(to, subsidy);
        }
    }

    function quoteIn(uint256 amountIn, address tokenIn, address tokenOut) external view returns (uint256) {
        uint256 amountAgToken = transmuter.quoteIn(amountIn, tokenIn, agToken);
        uint256 amountOut = transmuter.quoteIn(amountAgToken, agToken, tokenOut);
        (uint256 subsidy, ) = _computeSubsidy(tokenIn, tokenOut, amountOut);
        return amountOut + subsidy;
    }

    function setOrder(
        address tokenIn,
        address tokenOut,
        uint256 amountOutCovered,
        uint256 premium
    ) external onlyGuardian {
        Order storage order = orders[tokenIn][tokenOut];
        uint256 newBudget = budget[tokenOut] + amountOutCovered * premium - order.amountOutCovered * order.premium;
        if (IERC20(tokenOut).balanceOf(address(this)) < newBudget) revert InvalidParam();
        budget[tokenOut] = newBudget;
        orders[tokenIn][tokenOut].amountOutCovered = amountOutCovered;
        orders[tokenIn][tokenOut].premium = premium;
    }

    function _computeSubsidy(
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) internal view returns (uint256 subsidy, uint256 newAmountCovered) {
        Order memory order = orders[tokenIn][tokenOut];
        newAmountCovered = order.amountOutCovered;
        uint256 covered = amountOut > newAmountCovered ? newAmountCovered : amountOut;
        if (covered > 0) {
            subsidy = covered * order.premium;
            newAmountCovered -= covered;
        }
    }
}
