// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import { IERC20 } from "oz/token/ERC20/IERC20.sol";
import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";

import { ISwapper } from "interfaces/ISwapper.sol";
import { IPermit2, PermitTransferFrom, SignatureTransferDetails, TokenPermissions } from "interfaces/external/permit2/IPermit2.sol";

import { LibHelpers } from "../libraries/LibHelpers.sol";
import { LibStorage as s } from "../libraries/LibStorage.sol";
import { LibSwapper } from "../libraries/LibSwapper.sol";
import { LibManager } from "../libraries/LibManager.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import "../Storage.sol";

/// @title Swapper
/// @author Angle Labs, Inc.
/// @dev In all the functions of this contract, one of `tokenIn` or `tokenOut` must be the stablecoin, and
/// one of `tokenOut` or `tokenIn` must be an accepted collateral. Depending on the `tokenIn` or `tokenOut` given,
/// the functions will either handle a mint or a burn operation
/// @dev In case of a burn, they will also revert if the system does not have enough of `amountOut` for `tokenOut`.
/// This balance must be available either directly on the contract or, when applicable, through the underlying
/// strategies that manage the collateral
/// @dev Functions here may be paused for some collateral assets (for either mint or burn), in which case they'll revert
/// @dev In case of a burn again, the swap functions will revert if the call concerns a collateral that requires a
/// whitelist but the `to` address does not have it. The quote functions will not revert in this case.
contract Swapper is ISwapper {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                               EXTERNAL ACTION FUNCTIONS                                            
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    // For the two functions below, a value of `0` for the `deadline` parameters means that there will be no timestamp
    // check for when the swap is actually executed.

    /// @inheritdoc ISwapper
    /// @dev `msg.sender` must have approved this contract for at least `amountIn` for `tokenIn`
    function swapExactInput(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external returns (uint256) {
        return swapExactInputWithPermit(amountIn, amountOutMin, tokenIn, tokenOut, to, deadline, "");
    }

    function swapExactInputWithPermit(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline,
        bytes memory permitData
    ) public returns (uint256 amountOut) {
        (bool mint, Collateral storage collatInfo) = LibSwapper.getMintBurn(tokenIn, tokenOut, deadline);
        // Building the permit2 payload here to avoid a stack too deep
        if (permitData.length > 0) {
            Permit2Details memory details;
            if (collatInfo.isManaged > 0) {
                details.to = LibManager.transferRecipient(collatInfo.managerData.config);
            } else {
                details.to = address(this);
            }
            (details.nonce, details.signature) = abi.decode(permitData, (uint256, bytes));
            permitData = abi.encodeWithSelector(
                IPermit2.permitTransferFrom.selector,
                PermitTransferFrom({
                    permitted: TokenPermissions({ token: tokenIn, amount: amountIn }),
                    nonce: details.nonce,
                    deadline: deadline
                }),
                SignatureTransferDetails({ to: details.to, requestedAmount: amountIn }),
                msg.sender,
                details.signature
            );
        }
        amountOut = mint
            ? LibSwapper.quoteMintExactInput(collatInfo, amountIn)
            : LibSwapper.quoteBurnExactInput(tokenOut, collatInfo, amountIn);
        if (amountOut < amountOutMin) revert TooSmallAmountOut();
        LibSwapper.swap(amountIn, amountOut, tokenIn, tokenOut, to, mint, collatInfo, permitData);
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
    ) external returns (uint256) {
        return swapExactOutputWithPermit(amountOut, amountInMax, tokenIn, tokenOut, to, deadline, "");
    }

    function swapExactOutputWithPermit(
        uint256 amountOut,
        uint256 amountInMax,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline,
        bytes memory permitData
    ) public returns (uint256 amountIn) {
        (bool mint, Collateral storage collatInfo) = LibSwapper.getMintBurn(tokenIn, tokenOut, deadline);
        amountIn = mint
            ? LibSwapper.quoteMintExactOutput(collatInfo, amountOut)
            : LibSwapper.quoteBurnExactOutput(tokenOut, collatInfo, amountOut);
        if (amountIn > amountInMax) revert TooBigAmountIn();
        if (permitData.length > 0) {
            Permit2Details memory details;
            if (collatInfo.isManaged > 0) {
                details.to = LibManager.transferRecipient(collatInfo.managerData.config);
            } else {
                details.to = address(this);
            }
            (details.nonce, details.signature) = abi.decode(permitData, (uint256, bytes));
            permitData = abi.encodeWithSelector(
                IPermit2.permitTransferFrom.selector,
                PermitTransferFrom({
                    permitted: TokenPermissions({ token: tokenIn, amount: amountInMax }),
                    nonce: details.nonce,
                    deadline: deadline
                }),
                SignatureTransferDetails({ to: details.to, requestedAmount: amountIn }),
                msg.sender,
                details.signature
            );
        }
        LibSwapper.swap(amountIn, amountOut, tokenIn, tokenOut, to, mint, collatInfo, permitData);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                     VIEW HELPERS                                                   
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    // If these functions return a null `amountOut` or `amountIn` value, then calling one of the swap functions above
    // at the exact same block will not do anything.

    /// @inheritdoc ISwapper
    function quoteIn(uint256 amountIn, address tokenIn, address tokenOut) external view returns (uint256 amountOut) {
        (bool mint, Collateral storage collatInfo) = LibSwapper.getMintBurn(tokenIn, tokenOut, 0);
        if (mint) return LibSwapper.quoteMintExactInput(collatInfo, amountIn);
        else {
            amountOut = LibSwapper.quoteBurnExactInput(tokenOut, collatInfo, amountIn);
            LibSwapper.checkAmounts(collatInfo, amountOut);
        }
    }

    /// @inheritdoc ISwapper
    function quoteOut(uint256 amountOut, address tokenIn, address tokenOut) external view returns (uint256 amountIn) {
        (bool mint, Collateral storage collatInfo) = LibSwapper.getMintBurn(tokenIn, tokenOut, 0);
        if (mint) return LibSwapper.quoteMintExactOutput(collatInfo, amountOut);
        else {
            LibSwapper.checkAmounts(collatInfo, amountOut);
            return LibSwapper.quoteBurnExactOutput(tokenOut, collatInfo, amountOut);
        }
    }
}
