// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import "contracts/utils/Constants.sol";
import { BaseActor, ITransmuter, AggregatorV3Interface, IERC20, IERC20Metadata } from "./BaseActor.t.sol";
import { QuoteType } from "contracts/transmuter/Storage.sol";

import { console } from "forge-std/console.sol";

contract Trader is BaseActor {
    constructor(
        ITransmuter transmuter,
        address[] memory collaterals,
        AggregatorV3Interface[] memory oracles,
        uint256 nbrTrader
    ) BaseActor(nbrTrader, "Trader", transmuter, collaterals, oracles) {}

    function swap(
        uint256 collatNumber,
        uint256 actionType,
        uint256 amount,
        uint256 actorIndex,
        uint256 recipientIndex
    ) public useActor(actorIndex) countCall("swap") returns (uint256 amountIn, uint256 amountOut) {
        QuoteType quoteType = QuoteType(bound(actionType, 0, 3));
        collatNumber = bound(collatNumber, 0, 2);
        amount = bound(amount, 1, 10 ** 15);
        address collateral = _collaterals[collatNumber];

        uint8 decimals = IERC20Metadata(collateral).decimals();

        amountIn;
        amountOut;
        address tokenIn;
        address tokenOut;

        console.log("");
        console.log("=========");

        if (quoteType == QuoteType.MintExactInput) {
            console.log("Mint - Input");
            tokenIn = collateral;
            tokenOut = address(agToken);
            amountIn = amount * 10 ** decimals;
            amountOut = transmuter.quoteIn(amountIn, tokenIn, tokenOut);
        } else if (quoteType == QuoteType.BurnExactInput) {
            console.log("Burn - Input");
            tokenIn = address(agToken);
            tokenOut = collateral;
            amountIn = bound(amount * BASE_18, 1, agToken.balanceOf(_currentActor));
            amountOut = transmuter.quoteIn(amountIn, tokenIn, tokenOut);
        } else if (quoteType == QuoteType.MintExactOutput) {
            console.log("Mint - Output");
            tokenIn = collateral;
            tokenOut = address(agToken);
            amountOut = amount * BASE_18;
            amountIn = transmuter.quoteOut(amountOut, tokenIn, tokenOut);
        } else if (quoteType == QuoteType.BurnExactOutput) {
            console.log("Burn - Output");
            tokenIn = address(agToken);
            tokenOut = collateral;
            amountOut = amount * 10 ** decimals;
            amountIn = transmuter.quoteOut(amountOut, tokenIn, tokenOut);
            // we need to decrease the amountOut wanted
            uint256 actorBalance = agToken.balanceOf(_currentActor);
            if (actorBalance < amountIn) amountOut = transmuter.quoteIn(actorBalance, tokenIn, tokenOut);
        }

        console.log("Amount In: ", amountIn);
        console.log("Amount Out: ", amountOut);
        console.log("=========");
        console.log("");

        // If burning we can't burn more than the reserves
        if (quoteType == QuoteType.BurnExactInput || quoteType == QuoteType.BurnExactOutput) {
            if (amountOut > IERC20(tokenOut).balanceOf(address(transmuter))) {
                return (0, 0);
            }
        }

        if (quoteType == QuoteType.MintExactInput || quoteType == QuoteType.MintExactOutput) {
            // Deal tokens to _currentActor if needed
            if (IERC20(tokenIn).balanceOf(_currentActor) < amountIn) {
                deal(address(tokenIn), _currentActor, amountIn - IERC20(tokenIn).balanceOf(_currentActor));
            }
        }

        // Approval
        hoax(_currentActor);
        IERC20(tokenIn).approve(address(transmuter), amountIn);

        // Memory previous balances
        uint256 balanceAgToken = agToken.balanceOf(_currentActor);
        uint256 balanceCollateral = IERC20(collateral).balanceOf(_currentActor);

        // Swap
        hoax(_currentActor);
        if (quoteType == QuoteType.MintExactInput || quoteType == QuoteType.BurnExactInput) {
            transmuter.swapExactInput(amountIn, amountOut, tokenIn, tokenOut, _currentActor, block.timestamp + 1 hours);
        } else {
            transmuter.swapExactOutput(
                amountOut,
                amountIn,
                tokenIn,
                tokenOut,
                _currentActor,
                block.timestamp + 1 hours
            );
        }

        if (quoteType == QuoteType.MintExactInput || quoteType == QuoteType.BurnExactInput) {
            assertEq(IERC20(collateral).balanceOf(_currentActor), balanceCollateral - amountIn);
            assertEq(agToken.balanceOf(_currentActor), balanceAgToken + amountOut);
        } else {
            assertEq(IERC20(collateral).balanceOf(_currentActor), balanceCollateral + amountOut);
            assertEq(agToken.balanceOf(_currentActor), balanceAgToken - amountIn);
        }
    }
}
