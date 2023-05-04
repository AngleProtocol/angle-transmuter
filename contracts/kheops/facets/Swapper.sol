// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { LibSwapper as Lib } from "../libraries/LibSwapper.sol";
import { Storage as s } from "../libraries/Storage.sol";
import { Helper as LibHelper } from "../libraries/Helper.sol";
import "../libraries/LibManager.sol";
import "../Storage.sol";

import "../../utils/Errors.sol";
import "../../utils/Constants.sol";

contract Swapper {
    using SafeERC20 for IERC20;

    function swapExactInput(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external returns (uint amountOut) {
        KheopsStorage storage ks = s.kheopsStorage();
        if (block.timestamp > deadline) revert TooLate();
        (bool mint, Collateral memory collatInfo) = Lib.getMintBurn(tokenIn, tokenOut);

        amountOut = mint
            ? Lib.quoteMintExactInput(collatInfo, amountIn)
            : Lib.quoteBurnExactInput(collatInfo, amountIn);
        if (amountOut < amountOutMin) revert TooSmallAmountOut();

        if (mint) {
            uint256 changeAmount = (amountOut * BASE_27) / ks.normalizer;
            ks.collaterals[tokenIn].normalizedStables += changeAmount;
            ks.normalizedStables += changeAmount;
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
            IAgToken(tokenOut).mint(to, amountOut);
        } else {
            uint256 changeAmount = (amountIn * BASE_27) / ks.normalizer;
            ks.collaterals[tokenOut].normalizedStables -= changeAmount;
            ks.normalizedStables -= changeAmount;
            IAgToken(tokenIn).burnSelf(amountIn, msg.sender);
            LibHelper.transferCollateral(
                tokenOut,
                collatInfo.hasManager > 0 ? tokenOut : address(0),
                to,
                amountOut,
                true
            );
        }
    }

    function swapExactOutput(
        uint256 amountOut,
        uint256 amountInMax,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external returns (uint amountIn) {
        KheopsStorage storage ks = s.kheopsStorage();
        if (block.timestamp > deadline) revert TooLate();
        (bool mint, Collateral memory collatInfo) = Lib.getMintBurn(tokenIn, tokenOut);

        amountIn = mint
            ? Lib.quoteMintExactOutput(collatInfo, amountOut)
            : Lib.quoteBurnExactOutput(collatInfo, amountOut);
        if (amountIn > amountInMax) revert TooBigAmountIn();

        if (mint) {
            uint256 changeAmount = (amountOut * BASE_27) / ks.normalizer;
            ks.collaterals[tokenIn].normalizedStables += changeAmount;
            ks.normalizedStables += changeAmount;
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
            IAgToken(tokenOut).mint(to, amountOut);
        } else {
            uint256 changeAmount = (amountIn * BASE_27) / ks.normalizer;
            ks.collaterals[tokenOut].normalizedStables -= changeAmount;
            ks.normalizedStables -= changeAmount; // Will overflow if the operation is impossible
            IAgToken(tokenIn).burnSelf(amountIn, msg.sender);
            LibHelper.transferCollateral(
                tokenOut,
                collatInfo.hasManager > 0 ? tokenOut : address(0),
                to,
                amountOut,
                true
            );
        }
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
