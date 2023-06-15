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

    function call(bytes memory payload) external returns (bool success, bytes memory result) {
        (uint256 amountIn, uint256 amountOut, address tokenIn, address tokenOut) = abi.decode(
            payload,
            (uint256, uint256, address, address)
        );
        bytes memory data;
        if (setRevert) return (false, data);
        if (setRevertWithMessage) return (false, abi.encode("wrong swap"));
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
        return (true, data);
    }

    function setRevertStatuses(bool _setRevert, bool _setRevertWithMessage) external {
        setRevert = _setRevert;
        setRevertWithMessage = _setRevertWithMessage;
    }
}
