// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import "contracts/utils/Constants.sol";
import { BaseActor, ITransmuter, AggregatorV3Interface, IERC20, IERC20Metadata } from "./BaseActor.t.sol";
import { QuoteType } from "contracts/transmuter/Storage.sol";
import { console } from "forge-std/console.sol";

contract Arbitrager is BaseActor {
    constructor(
        ITransmuter transmuter,
        address[] memory collaterals,
        AggregatorV3Interface[] memory oracles,
        uint256 nbrTrader
    ) BaseActor(nbrTrader, "Arb", transmuter, collaterals, oracles) {}

    function swap(
        uint256 collatNumber,
        uint256 actionType,
        uint256 amount,
        uint256 actorIndex
    ) public useActor(actorIndex) countCall("swap") returns (uint256 amountIn, uint256 amountOut) {
        QuoteType quoteType = QuoteType(bound(actionType, 0, 3));
        collatNumber = bound(collatNumber, 0, 2);
        amount = bound(amount, 1, 10 ** 15);
        address collateral = _collaterals[collatNumber];

        uint8 decimals = IERC20Metadata(collateral).decimals();

        if (
            (quoteType == QuoteType.BurnExactInput || quoteType == QuoteType.BurnExactOutput) &&
            agToken.balanceOf(_currentActor) == 0
        ) return (0, 0);

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
            amountOut = _transmuter.quoteIn(amountIn, tokenIn, tokenOut);
        } else if (quoteType == QuoteType.BurnExactInput) {
            console.log("Burn - Input");
            tokenIn = address(agToken);
            tokenOut = collateral;
            amountIn = bound(amount * BASE_18, 1, agToken.balanceOf(_currentActor));
            amountOut = _transmuter.quoteIn(amountIn, tokenIn, tokenOut);
        } else if (quoteType == QuoteType.MintExactOutput) {
            console.log("Mint - Output");
            tokenIn = collateral;
            tokenOut = address(agToken);
            amountOut = amount * BASE_18;
            amountIn = _transmuter.quoteOut(amountOut, tokenIn, tokenOut);
        } else if (quoteType == QuoteType.BurnExactOutput) {
            console.log("Burn - Output");
            tokenIn = address(agToken);
            tokenOut = collateral;
            amountOut = amount * 10 ** decimals;
            amountIn = _transmuter.quoteOut(amountOut, tokenIn, tokenOut);
            // we need to decrease the amountOut wanted
            uint256 actorBalance = agToken.balanceOf(_currentActor);
            if (actorBalance < amountIn) {
                amountIn = actorBalance;
                amountOut = _transmuter.quoteIn(actorBalance, tokenIn, tokenOut);
            }
        }

        console.log("Amount In: ", amountIn);
        console.log("Amount Out: ", amountOut);
        console.log("=========");
        console.log("");

        // If burning we can't burn more than the reserves
        if (quoteType == QuoteType.BurnExactInput || quoteType == QuoteType.BurnExactOutput) {
            if (amountOut > IERC20(tokenOut).balanceOf(address(_transmuter))) {
                return (0, 0);
            }
        }

        if (quoteType == QuoteType.MintExactInput || quoteType == QuoteType.MintExactOutput) {
            // Deal tokens to _currentActor if needed
            if (IERC20(tokenIn).balanceOf(_currentActor) < amountIn) {
                deal(address(tokenIn), _currentActor, amountIn);
            }
        }

        // Approval
        IERC20(tokenIn).approve(address(_transmuter), amountIn);

        // Memory previous balances
        uint256 balanceAgToken = agToken.balanceOf(_currentActor);
        uint256 balanceCollateral = IERC20(collateral).balanceOf(_currentActor);

        // Swap
        if (quoteType == QuoteType.MintExactInput || quoteType == QuoteType.BurnExactInput) {
            _transmuter.swapExactInput(
                amountIn,
                amountOut,
                tokenIn,
                tokenOut,
                _currentActor,
                block.timestamp + 1 hours
            );
        } else {
            _transmuter.swapExactOutput(
                amountOut,
                amountIn,
                tokenIn,
                tokenOut,
                _currentActor,
                block.timestamp + 1 hours
            );
        }

        if (quoteType == QuoteType.MintExactInput || quoteType == QuoteType.MintExactOutput) {
            assertEq(IERC20(collateral).balanceOf(_currentActor), balanceCollateral - amountIn);
            assertEq(agToken.balanceOf(_currentActor), balanceAgToken + amountOut);
        } else {
            assertEq(IERC20(collateral).balanceOf(_currentActor), balanceCollateral + amountOut);
            assertEq(agToken.balanceOf(_currentActor), balanceAgToken - amountIn);
        }
    }

    function redeem(
        bool[3] memory isForfeitTokens,
        uint256 amount,
        uint256 actorIndex
    ) public useActor(actorIndex) countCall("redeem") {
        uint256 balanceAgToken = agToken.balanceOf(_currentActor);
        amount = bound(amount, 0, balanceAgToken);
        if (amount == 0) return;

        address[] memory forfeitTokens;
        {
            uint256 count;
            for (uint256 i; i < isForfeitTokens.length; ++i) if (isForfeitTokens[i]) count++;
            forfeitTokens = new address[](count);
            count = 0;
            for (uint256 i; i < isForfeitTokens.length; ++i)
                if (isForfeitTokens[i]) {
                    forfeitTokens[count] = _collaterals[i];
                    count++;
                }
        }

        uint256[] memory balanceTokens = new uint256[](_collaterals.length);
        for (uint256 i; i < balanceTokens.length; ++i)
            balanceTokens[i] = IERC20(_collaterals[i]).balanceOf(_currentActor);

        console.log("");
        console.log("========= Redeem =========");

        uint256[] memory redeemAmounts;
        {
            // don't care about slippage
            uint256[] memory minAmountOuts = new uint256[](_collaterals.length);
            address[] memory redeemTokens;
            (redeemTokens, redeemAmounts) = _transmuter.redeemWithForfeit(
                amount,
                _currentActor,
                block.timestamp * 2,
                minAmountOuts,
                forfeitTokens
            );
        }

        assertEq(agToken.balanceOf(_currentActor), balanceAgToken - amount);
        for (uint256 i; i < balanceTokens.length; ++i) {
            if (!isForfeitTokens[i])
                assertEq(IERC20(_collaterals[i]).balanceOf(_currentActor), balanceTokens[i] + redeemAmounts[i]);
            else assertEq(IERC20(_collaterals[i]).balanceOf(_currentActor), balanceTokens[i]);
        }
    }
}
