// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { IERC20 } from "oz/token/ERC20/IERC20.sol";
import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";

import { ISwapper } from "interfaces/ISwapper.sol";

import { LibHelpers } from "../libraries/LibHelpers.sol";
import { LibStorage as s } from "../libraries/LibStorage.sol";
import { LibSwapper } from "../libraries/LibSwapper.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import "../Storage.sol";

/// @title Swapper
/// @author Angle Labs, Inc.
contract Swapper is ISwapper {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                               EXTERNAL ACTION FUNCTIONS                                            
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// The two functions below can be used for both mint and burn operations. In both cases, one of `tokenIn` or
    /// `tokenOut` must be the stablecoin, and the other must be an accepted collateral: the functions revert otherwise.
    /// They may be paused for some collateral assets (for either mint or burn), in which case they will revert.
    /// An approval of `tokenIn` for this contract is also needed before interacting with it.

    /// @inheritdoc ISwapper
    /// @dev `msg.sender` must have approved this contract for at least `amountIn` for `tokenIn`
    function swapExactInput(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut) {
        if (block.timestamp > deadline) revert TooLate();
        // Check whether this is a mint or a burn operation, and whether the collateral provided
        // is paused or not
        (bool mint, Collateral memory collatInfo) = LibSwapper.getMintBurn(tokenIn, tokenOut);
        // Get the `amountOut`
        amountOut = mint
            ? LibSwapper.quoteMintExactInput(collatInfo, amountIn)
            : LibSwapper.quoteBurnExactInput(tokenOut, collatInfo, amountIn);
        if (amountOut < amountOutMin) revert TooSmallAmountOut();
        // Once the exact amounts are known, the system needs to update its internal metrics and process the transfers
        LibSwapper.swap(amountIn, amountOut, tokenIn, tokenOut, to, collatInfo.isManaged, mint);
    }

    /// @inheritdoc ISwapper
    /// @dev `msg.sender` must have approved this contract for an amount bigger than what `amountIn` will
    /// be before calling this function. Approving the contract for `tokenIn` with `amountInMax` will always be enough.
    function swapExactOutput(
        uint256 amountOut,
        uint256 amountInMax,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external returns (uint256 amountIn) {
        if (block.timestamp > deadline) revert TooLate();
        (bool mint, Collateral memory collatInfo) = LibSwapper.getMintBurn(tokenIn, tokenOut);
        amountIn = mint
            ? LibSwapper.quoteMintExactOutput(collatInfo, amountOut)
            : LibSwapper.quoteBurnExactOutput(tokenOut, collatInfo, amountOut);
        if (amountIn > amountInMax) revert TooBigAmountIn();
        LibSwapper.swap(amountIn, amountOut, tokenIn, tokenOut, to, collatInfo.isManaged, mint);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                     VIEW HELPERS                                                   
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// The functions below revert if neither of `tokenIn` and `tokenOut` are the stablecoin, and if neither
    /// of `tokenOut` and `tokenIn` are an accepted collateral.
    /// In case of a burn, they will also revert if the system does not have enough of `amountOut` for `tokenOut`.
    /// This balance must be available either directly on the contract or through the underlying strategies that manage
    /// the collateral.
    /// In case of a burn again, they will also revert if the call concerns a collateral that requires a whitelist but
    /// the calling address does not have it.

    /// @inheritdoc ISwapper
    function quoteIn(uint256 amountIn, address tokenIn, address tokenOut) external view returns (uint256 amountOut) {
        (bool mint, Collateral memory collatInfo) = LibSwapper.getMintBurn(tokenIn, tokenOut);
        if (mint) return LibSwapper.quoteMintExactInput(collatInfo, amountIn);
        else {
            amountOut = LibSwapper.quoteBurnExactInput(tokenOut, collatInfo, amountIn);
            LibSwapper.checkAmounts(collatInfo, amountOut);
        }
    }

    /// @inheritdoc ISwapper
    function quoteOut(uint256 amountOut, address tokenIn, address tokenOut) external view returns (uint256 amountIn) {
        (bool mint, Collateral memory collatInfo) = LibSwapper.getMintBurn(tokenIn, tokenOut);
        if (mint) return LibSwapper.quoteMintExactOutput(collatInfo, amountOut);
        else {
            LibSwapper.checkAmounts(collatInfo, amountOut);
            return LibSwapper.quoteBurnExactOutput(tokenOut, collatInfo, amountOut);
        }
    }
}
