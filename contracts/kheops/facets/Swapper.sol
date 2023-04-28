// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.0;

import { LibSwapper as Lib } from "../libraries/LibSwapper.sol";
import { Storage as s } from "../libraries/Storage.sol";
import "../Storage.sol";

contract Swapper {
    function swapExactInput(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external returns (uint amountOut) {
        return Lib.swap(amountIn, amountOutMin, tokenIn, tokenOut, to, deadline, true);
    }

    function swapExactOutput(
        uint256 amountOut,
        uint256 amountInMax,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external returns (uint amountIn) {
        return Lib.swap(amountOut, amountInMax, tokenIn, tokenOut, to, deadline, false);
    }

    function quoteIn(uint256 amountIn, address tokenIn, address tokenOut) external view returns (uint256) {
        (bool mint, Collateral memory collatInfo) = Lib.getMintBurn(tokenIn, tokenOut);
        if (mint) return Lib.quoteMintExactInput(collatInfo, amountIn);
        else {
            uint256 amountOut = Lib.quoteBurnExactInput(collatInfo, amountIn);
            Lib.checkAmounts(tokenOut, collatInfo, amountOut);
            return amountOut;
        }
    }

    function quoteOut(uint256 amountOut, address tokenIn, address tokenOut) external view returns (uint256) {
        (bool mint, Collateral memory collatInfo) = Lib.getMintBurn(tokenIn, tokenOut);
        if (mint) return Lib.quoteMintExactOutput(collatInfo, amountOut);
        else {
            Lib.checkAmounts(tokenOut, collatInfo, amountOut);
            return Lib.quoteBurnExactOutput(collatInfo, amountOut);
        }
    }
}
