// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ISwapper } from "../interfaces/ISwapper.sol";

import { LibSwapper as Lib } from "../libraries/LibSwapper.sol";
import { LibStorage as s } from "../libraries/LibStorage.sol";
import { LibHelper } from "../libraries/LibHelper.sol";

import "../Storage.sol";
import "../../utils/Errors.sol";
import "../../utils/Constants.sol";

/// @title Swapper
/// @author Angle Labs, Inc.
contract Swapper is ISwapper {
    event Swap(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address from,
        address indexed to
    );
    using SafeERC20 for IERC20;

    /// @inheritdoc ISwapper
    function swapExactInput(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut) {
        KheopsStorage storage ks = s.kheopsStorage();
        if (block.timestamp > deadline) revert TooLate();
        (bool mint, Collateral memory collatInfo) = Lib.getMintBurn(tokenIn, tokenOut);

        amountOut = mint
            ? Lib.quoteMintExactInput(collatInfo, amountIn)
            : Lib.quoteBurnExactInput(tokenOut, collatInfo, amountIn);
        if (amountOut < amountOutMin) revert TooSmallAmountOut();

        if (mint) {
            uint128 changeAmount = uint128((amountOut * BASE_27) / ks.normalizer);
            ks.collaterals[tokenIn].normalizedStables += uint224(changeAmount);
            ks.normalizedStables += changeAmount;
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
            IAgToken(tokenOut).mint(to, amountOut);
        } else {
            uint128 changeAmount = uint128((amountIn * BASE_27) / ks.normalizer);
            ks.collaterals[tokenOut].normalizedStables -= uint224(changeAmount);
            ks.normalizedStables -= changeAmount;
            IAgToken(tokenIn).burnSelf(amountIn, msg.sender);
            ManagerStorage memory emptyManagerData;
            LibHelper.transferCollateral(
                tokenOut,
                to,
                amountOut,
                true,
                collatInfo.isManaged > 0 ? collatInfo.managerData : emptyManagerData
            );
        }
        emit Swap(tokenIn, tokenOut, amountIn, amountOut, msg.sender, to);
    }

    /// @inheritdoc ISwapper
    function swapExactOutput(
        uint256 amountOut,
        uint256 amountInMax,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external returns (uint256 amountIn) {
        KheopsStorage storage ks = s.kheopsStorage();
        if (block.timestamp > deadline) revert TooLate();
        (bool mint, Collateral memory collatInfo) = Lib.getMintBurn(tokenIn, tokenOut);

        amountIn = mint
            ? Lib.quoteMintExactOutput(collatInfo, amountOut)
            : Lib.quoteBurnExactOutput(tokenOut, collatInfo, amountOut);
        if (amountIn > amountInMax) revert TooBigAmountIn();

        if (mint) {
            uint128 changeAmount = uint128((amountOut * BASE_27) / ks.normalizer);
            ks.collaterals[tokenIn].normalizedStables += uint224(changeAmount);
            ks.normalizedStables += changeAmount;
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
            IAgToken(tokenOut).mint(to, amountOut);
        } else {
            uint128 changeAmount = uint128((amountIn * BASE_27) / ks.normalizer);
            ks.collaterals[tokenOut].normalizedStables -= uint224(changeAmount);
            ks.normalizedStables -= changeAmount; // Will underflow if the operation is impossible
            IAgToken(tokenIn).burnSelf(amountIn, msg.sender);
            {
                ManagerStorage memory emptyManagerData;
                LibHelper.transferCollateral(
                    tokenOut,
                    to,
                    amountOut,
                    true,
                    collatInfo.isManaged > 0 ? collatInfo.managerData : emptyManagerData
                );
            }
        }
        emit Swap(tokenIn, tokenOut, amountIn, amountOut, msg.sender, to);
    }

    /// @inheritdoc ISwapper
    function quoteIn(uint256 amountIn, address tokenIn, address tokenOut) external view returns (uint256) {
        (bool mint, Collateral memory collatInfo) = Lib.getMintBurn(tokenIn, tokenOut);
        if (mint) return Lib.quoteMintExactInput(collatInfo, amountIn);
        else {
            uint256 amountOut = Lib.quoteBurnExactInput(tokenOut, collatInfo, amountIn);
            Lib.checkAmounts(tokenOut, collatInfo, amountOut);
            return amountOut;
        }
    }

    /// @inheritdoc ISwapper
    function quoteOut(uint256 amountOut, address tokenIn, address tokenOut) external view returns (uint256) {
        (bool mint, Collateral memory collatInfo) = Lib.getMintBurn(tokenIn, tokenOut);
        if (mint) return Lib.quoteMintExactOutput(collatInfo, amountOut);
        else {
            Lib.checkAmounts(tokenOut, collatInfo, amountOut);
            return Lib.quoteBurnExactOutput(tokenOut, collatInfo, amountOut);
        }
    }
}
