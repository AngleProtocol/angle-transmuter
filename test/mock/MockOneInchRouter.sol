// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import "oz/token/ERC20/IERC20.sol";
import "oz/token/ERC20/utils/SafeERC20.sol";

import { LibHelpers } from "../../contracts/transmuter/libraries/LibHelpers.sol";
import { LibOracle, AggregatorV3Interface } from "../../contracts/transmuter/libraries/LibOracle.sol";

import "../../contracts/utils/Constants.sol";
import "../../contracts/utils/Errors.sol";

contract MockOneInchRouter {
    using SafeERC20 for IERC20;
    bool public setRevert;
    bool public setRevertWithMessage;

    function swap(uint256 amountIn, uint256 amountOut, address tokenIn, address tokenOut) external returns (uint256) {
        if (setRevert) require(false);
        if (setRevertWithMessage) revert("wrong swap");
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
        return amountOut;
    }

    function setRevertStatuses(bool _setRevert, bool _setRevertWithMessage) external {
        setRevert = _setRevert;
        setRevertWithMessage = _setRevertWithMessage;
    }
}
