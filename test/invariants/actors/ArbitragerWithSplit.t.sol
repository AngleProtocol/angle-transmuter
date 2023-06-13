// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import "contracts/utils/Constants.sol";
import { AggregatorV3Interface, BaseActor, IERC20, IERC20Metadata, ITransmuter, TestStorage } from "./BaseActor.t.sol";
import { QuoteType } from "contracts/transmuter/Storage.sol";
import { console } from "forge-std/console.sol";

contract ArbitragerWithSplit is BaseActor {
    bool public withForfeit;

    constructor(
        ITransmuter transmuter,
        ITransmuter transmuterSplit,
        address[] memory collaterals,
        AggregatorV3Interface[] memory oracles,
        uint256 nbrTrader
    ) BaseActor(nbrTrader, "Arb", transmuter, transmuterSplit, collaterals, oracles) {}

    function swap(
        uint256 collatNumber,
        uint256 actionType,
        uint256 amount,
        uint256 splitProportion,
        uint256 actorIndex
    ) public useActor(actorIndex) countCall("swap") returns (uint256, uint256) {
        QuoteType quoteType = QuoteType(bound(actionType, 0, 3));
        collatNumber = bound(collatNumber, 0, 2);
        amount = bound(amount, 1, 10 ** 12);
        {
            // if the number of stablecoins issued is null don't split the trades as in the solifity
            // we consider it as a different case by setting constant fees
            uint256 stablecoinIssued = _transmuter.getTotalIssued();
            if (stablecoinIssued < 10 wei) splitProportion = BASE_9;
            else splitProportion = bound(splitProportion, 1, BASE_9);
        }

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
            // divided by 2 because we need to do for both the transmuter and the replica
            testS.amountIn = bound(amount * BASE_18, 1, agToken.balanceOf(_currentActor) / 2);
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
            // divided by 2 because we need to do for both the transmuter and the replica
            uint256 actorBalance = agToken.balanceOf(_currentActor) / 2;
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
            if (IERC20(testS.tokenIn).balanceOf(_currentActor) < 2 * testS.amountIn) {
                deal(testS.tokenIn, _currentActor, 2 * testS.amountIn);
            }
        }

        // Approval only usefull for QuoteType.MintExactInput and QuoteType.MintExactOutput
        IERC20(testS.tokenIn).approve(address(_transmuter), testS.amountIn);
        IERC20(testS.tokenIn).approve(address(_transmuterSplit), testS.amountIn);

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
            // send the received tokens to the sweeper
            // replicate on the other transmuter but split the orders
            {
                testS.amountInSplit1 = (testS.amountIn * splitProportion) / BASE_9;
                testS.amountOutSplit1 = _transmuterSplit.quoteIn(testS.amountInSplit1, testS.tokenIn, testS.tokenOut);
                _transmuterSplit.swapExactInput(
                    testS.amountInSplit1,
                    testS.amountOutSplit1,
                    testS.tokenIn,
                    testS.tokenOut,
                    sweeper,
                    block.timestamp + 1 hours
                );

                testS.amountInSplit2 = testS.amountIn - testS.amountInSplit1;
                testS.amountOutSplit2 = _transmuterSplit.quoteIn(testS.amountInSplit2, testS.tokenIn, testS.tokenOut);
                _transmuterSplit.swapExactInput(
                    testS.amountInSplit2,
                    testS.amountOutSplit2,
                    testS.tokenIn,
                    testS.tokenOut,
                    sweeper,
                    block.timestamp + 1 hours
                );
            }
        } else {
            _transmuter.swapExactOutput(
                testS.amountOut,
                testS.amountIn,
                testS.tokenIn,
                testS.tokenOut,
                _currentActor,
                block.timestamp + 1 hours
            );
            // replicate on the other transmuter but wplit the orders
            {
                testS.amountOutSplit1 = (testS.amountOut * splitProportion) / BASE_9;
                testS.amountInSplit1 = _transmuterSplit.quoteOut(testS.amountOutSplit1, testS.tokenIn, testS.tokenOut);
                {
                    // We can be missing either stablecoins or amountIn in the case of BurnExactOutput and MintExactOutput respectiveley
                    // Making revert the tx due to rounding errors. We increase balances have non reverting txs
                    uint256 actorBalance = agToken.balanceOf(_currentActor);
                    if (quoteType == QuoteType.BurnExactOutput && actorBalance < testS.amountInSplit1) {
                        testS.amountInSplit1 = actorBalance;
                        testS.amountOutSplit1 = _transmuterSplit.quoteIn(
                            testS.amountInSplit1,
                            testS.tokenIn,
                            testS.tokenOut
                        );
                    } else if (
                        quoteType == QuoteType.MintExactOutput &&
                        IERC20(testS.tokenIn).balanceOf(_currentActor) < testS.amountInSplit1
                    ) {
                        deal(testS.tokenIn, _currentActor, testS.amountInSplit1);
                        IERC20(testS.tokenIn).approve(address(_transmuterSplit), testS.amountInSplit1);
                    }
                }
                _transmuterSplit.swapExactOutput(
                    testS.amountOutSplit1,
                    testS.amountInSplit1,
                    testS.tokenIn,
                    testS.tokenOut,
                    sweeper,
                    block.timestamp + 1 hours
                );

                testS.amountOutSplit2 = testS.amountOut - testS.amountOutSplit1;
                testS.amountInSplit2 = _transmuterSplit.quoteOut(testS.amountOutSplit2, testS.tokenIn, testS.tokenOut);
                {
                    uint256 actorBalance = agToken.balanceOf(_currentActor);
                    if (quoteType == QuoteType.BurnExactOutput && actorBalance < testS.amountInSplit2) {
                        testS.amountInSplit2 = actorBalance;
                        testS.amountOutSplit2 = _transmuterSplit.quoteIn(
                            testS.amountInSplit2,
                            testS.tokenIn,
                            testS.tokenOut
                        );
                    } else if (
                        quoteType == QuoteType.MintExactOutput &&
                        IERC20(testS.tokenIn).balanceOf(_currentActor) < testS.amountInSplit2
                    ) {
                        deal(testS.tokenIn, _currentActor, testS.amountInSplit2);
                        IERC20(testS.tokenIn).approve(address(_transmuterSplit), testS.amountInSplit2);
                    }
                }
                _transmuterSplit.swapExactOutput(
                    testS.amountOutSplit2,
                    testS.amountInSplit2,
                    testS.tokenIn,
                    testS.tokenOut,
                    sweeper,
                    block.timestamp + 1 hours
                );
            }
        }

        return (testS.amountIn, testS.amountOut);
    }

    function redeem(
        bool[3] memory isForfeitTokens,
        uint256 amount,
        uint256 splitProportion,
        uint256 actorIndex
    ) public useActor(actorIndex) countCall("redeem") {
        uint256 balanceAgToken = agToken.balanceOf(_currentActor);
        amount = bound(amount, 0, balanceAgToken / 2);
        splitProportion = bound(splitProportion, 1, BASE_9);
        if (amount == 0) return;

        address[] memory forfeitTokens;
        // Redeem on the true transmuter
        {
            uint256[] memory balanceTokens = new uint256[](_collaterals.length);
            for (uint256 i; i < balanceTokens.length; ++i)
                balanceTokens[i] = IERC20(_collaterals[i]).balanceOf(_currentActor);

            console.log("");
            console.log("========= Redeem =========");

            (uint64 prevCollateralRatio, ) = _transmuter.getCollateralRatio();
            uint256[] memory redeemAmounts;
            {
                // don't care about slippage
                uint256[] memory minAmountOuts = new uint256[](_collaterals.length);
                address[] memory redeemTokens;
                (redeemTokens, redeemAmounts) = _transmuter.redeemWithForfeit(
                    amount,
                    _currentActor,
                    block.timestamp + 1 hours,
                    minAmountOuts,
                    forfeitTokens
                );
            }

            // if it is a burn it should always increase the collateral ratio
            (uint64 collateralRatio, ) = _transmuter.getCollateralRatio();
            assertGe(collateralRatio, prevCollateralRatio);
            assertEq(agToken.balanceOf(_currentActor), balanceAgToken - amount);
            balanceAgToken -= amount;
            for (uint256 i; i < balanceTokens.length; ++i) {
                if (!isForfeitTokens[i])
                    assertEq(IERC20(_collaterals[i]).balanceOf(_currentActor), balanceTokens[i] + redeemAmounts[i]);
                else assertEq(IERC20(_collaterals[i]).balanceOf(_currentActor), balanceTokens[i]);
            }
        }

        // Redeem on the replica transmuter
        {
            uint256[] memory balanceTokens = new uint256[](_collaterals.length);
            for (uint256 i; i < balanceTokens.length; ++i)
                balanceTokens[i] = IERC20(_collaterals[i]).balanceOf(_currentActor);

            console.log("");
            console.log("========= Redeem Split =========");

            (uint64 prevCollateralRatio, ) = _transmuterSplit.getCollateralRatio();
            uint256[] memory redeemAmountsSplit1;
            uint256[] memory redeemAmountsSplit2;
            {
                // don't care about slippage
                uint256[] memory minAmountOuts = new uint256[](_collaterals.length);
                address[] memory redeemTokens;

                uint256 amountSplit = (amount * splitProportion) / BASE_9;
                (redeemTokens, redeemAmountsSplit1) = _transmuterSplit.redeemWithForfeit(
                    amountSplit,
                    _currentActor,
                    block.timestamp + 1 hours,
                    minAmountOuts,
                    forfeitTokens
                );
                amountSplit = amount - amountSplit;
                (, redeemAmountsSplit2) = _transmuterSplit.redeemWithForfeit(
                    amountSplit,
                    _currentActor,
                    block.timestamp + 1 hours,
                    minAmountOuts,
                    forfeitTokens
                );
            }

            // if it is a burn it should always increase the collateral ratio
            (uint64 collateralRatio, ) = _transmuterSplit.getCollateralRatio();
            assertGe(collateralRatio, prevCollateralRatio);
            assertEq(agToken.balanceOf(_currentActor), balanceAgToken - amount);
            for (uint256 i; i < balanceTokens.length; ++i) {
                if (!isForfeitTokens[i])
                    assertEq(
                        IERC20(_collaterals[i]).balanceOf(_currentActor),
                        balanceTokens[i] + redeemAmountsSplit1[i] + redeemAmountsSplit2[i]
                    );
                else assertEq(IERC20(_collaterals[i]).balanceOf(_currentActor), balanceTokens[i]);
            }
        }
    }
}
