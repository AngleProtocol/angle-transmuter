// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import "contracts/utils/Constants.sol";
import { AggregatorV3Interface, BaseActor, IERC20, IERC20Metadata, ITransmuter, TestStorage } from "./BaseActor.t.sol";
import { QuoteType } from "contracts/transmuter/Storage.sol";

import { console } from "forge-std/console.sol";

contract Trader is BaseActor {
    constructor(
        ITransmuter transmuter,
        ITransmuter transmuterSplit,
        address[] memory collaterals,
        AggregatorV3Interface[] memory oracles,
        uint256 nbrTrader
    ) BaseActor(nbrTrader, "Trader", transmuter, transmuterSplit, collaterals, oracles) {}

    function swap(
        uint256 collatNumber,
        uint256 actionType,
        uint256 amount,
        uint256 actorIndex
    ) public useActor(actorIndex) countCall("swap") returns (uint256, uint256) {
        QuoteType quoteType = QuoteType(bound(actionType, 0, 3));
        collatNumber = bound(collatNumber, 0, 2);
        amount = bound(amount, 1, 10 ** 12);
        address collateral = _collaterals[collatNumber];

        if (
            (quoteType == QuoteType.BurnExactInput || quoteType == QuoteType.BurnExactOutput) &&
            agToken.balanceOf(_currentActor) == 0
        ) return (0, 0);

        TestStorage memory testS;

        console.log("");
        console.log("=========");

        if (quoteType == QuoteType.MintExactInput) {
            console.log("Mint - Input");
            testS.tokenIn = collateral;
            testS.tokenOut = address(agToken);
            testS.amountIn = amount * 10 ** IERC20Metadata(collateral).decimals();
            testS.amountOut = _transmuter.quoteIn(testS.amountIn, testS.tokenIn, testS.tokenOut);
        } else if (quoteType == QuoteType.BurnExactInput) {
            console.log("Burn - Input");
            testS.tokenIn = address(agToken);
            testS.tokenOut = collateral;
            testS.amountIn = bound(amount * BASE_18, 1, agToken.balanceOf(_currentActor));
            testS.amountOut = _transmuter.quoteIn(testS.amountIn, testS.tokenIn, testS.tokenOut);
        } else if (quoteType == QuoteType.MintExactOutput) {
            console.log("Mint - Output");
            testS.tokenIn = collateral;
            testS.tokenOut = address(agToken);
            testS.amountOut = amount * BASE_18;
            testS.amountIn = _transmuter.quoteOut(testS.amountOut, testS.tokenIn, testS.tokenOut);
        } else if (quoteType == QuoteType.BurnExactOutput) {
            console.log("Burn - Output");
            testS.tokenIn = address(agToken);
            testS.tokenOut = collateral;
            testS.amountOut = amount * 10 ** IERC20Metadata(collateral).decimals();
            testS.amountIn = _transmuter.quoteOut(testS.amountOut, testS.tokenIn, testS.tokenOut);
            uint256 actorBalance = agToken.balanceOf(_currentActor);
            // we need to decrease the amountOut wanted
            if (actorBalance < testS.amountIn) {
                testS.amountIn = actorBalance;
                testS.amountOut = _transmuter.quoteIn(actorBalance, testS.tokenIn, testS.tokenOut);
            }
        }

        console.log("Amount In: ", testS.amountIn);
        console.log("Amount Out: ", testS.amountOut);
        console.log("=========");
        console.log("");

        // If burning we can't burn more than the reserves
        if (quoteType == QuoteType.BurnExactInput || quoteType == QuoteType.BurnExactOutput) {
            (uint256 stablecoinsFromCollateral, uint256 totalStables) = _transmuter.getIssuedByCollateral(collateral);
            if (
                testS.amountOut > IERC20(testS.tokenOut).balanceOf(address(_transmuter)) ||
                testS.amountIn > stablecoinsFromCollateral ||
                testS.amountIn > totalStables
            ) {
                return (0, 0);
            }
        }

        if (quoteType == QuoteType.MintExactInput || quoteType == QuoteType.MintExactOutput) {
            // Deal tokens to _currentActor if needed
            if (IERC20(testS.tokenIn).balanceOf(_currentActor) < testS.amountIn) {
                deal(testS.tokenIn, _currentActor, testS.amountIn);
            }
        }

        // Approval only usefull for QuoteType.MintExactInput and QuoteType.MintExactOutput
        IERC20(testS.tokenIn).approve(address(_transmuter), testS.amountIn);
        IERC20(testS.tokenIn).approve(address(_transmuterSplit), testS.amountIn);

        // Memory previous balances
        uint256 balanceAgToken = agToken.balanceOf(_currentActor);
        uint256 balanceCollateral = IERC20(collateral).balanceOf(_currentActor);
        (uint64 prevCollateralRatio, ) = _transmuter.getCollateralRatio();

        // Swap
        if (quoteType == QuoteType.MintExactInput || quoteType == QuoteType.BurnExactInput) {
            _transmuter.swapExactInput(
                testS.amountIn,
                testS.amountOut,
                testS.tokenIn,
                testS.tokenOut,
                _currentActor,
                block.timestamp + 1 hours
            );
        } else {
            _transmuter.swapExactOutput(
                testS.amountOut,
                testS.amountIn,
                testS.tokenIn,
                testS.tokenOut,
                _currentActor,
                block.timestamp + 1 hours
            );
        }

        if (quoteType == QuoteType.MintExactInput || quoteType == QuoteType.MintExactOutput) {
            assertEq(IERC20(collateral).balanceOf(_currentActor), balanceCollateral - testS.amountIn);
            assertEq(agToken.balanceOf(_currentActor), balanceAgToken + testS.amountOut);
            // if it is a mint and the previous collateral ratio was lower than  it should always increase the collateral ratio
            (uint64 collateralRatio, ) = _transmuter.getCollateralRatio();
            if (prevCollateralRatio <= BASE_9) assertGe(collateralRatio, prevCollateralRatio);
            else assertGe(collateralRatio, BASE_9);
        } else {
            assertEq(IERC20(collateral).balanceOf(_currentActor), balanceCollateral + testS.amountOut);
            assertEq(agToken.balanceOf(_currentActor), balanceAgToken - testS.amountIn);
            // if it is a burn it should always increase the collateral ratio
            (uint64 collateralRatio, ) = _transmuter.getCollateralRatio();
            assertGe(collateralRatio, prevCollateralRatio);
        }

        return (testS.amountIn, testS.amountOut);
    }
}
