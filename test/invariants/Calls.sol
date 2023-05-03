// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { QuoteType } from "../../contracts/kheops/Storage.sol";
import "../../contracts/utils/Constants.sol";

import { Fixture } from "../Fixture.sol";

import { console } from "forge-std/console.sol";

contract Calls is Fixture {
    mapping(bytes32 => uint256) public calls;

    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    function callSummary() public view {
        console.log("");
        console.log("Call summary:");
        console.log("-------------------");
        console.log("swap", calls["swap"]);
        console.log("-------------------");
    }

    function swap(QuoteType quoteType, uint256 collatNumber, uint256 amount) public countCall("swap") {
        console.log("Test");
        // collatNumber = bound(collatNumber, 0, 2);

        // address collateral;
        // if (collatNumber == 0) {
        //     collateral = address(eurA);
        // } else if (collatNumber == 1) {
        //     collateral = address(eurB);
        // } else {
        //     collateral = address(eurY);
        // }
        // uint8 decimals = IERC20Metadata(collateral).decimals();

        // uint256 amountIn;
        // uint256 amountOut;
        // address tokenIn;
        // address tokenOut;

        // console.log("Swap type: ", uint256(quoteType));

        // if (quoteType == QuoteType.MintExactInput) {
        //     tokenIn = collateral;
        //     tokenOut = address(agToken);
        //     amountIn = amount * 10 ** decimals;
        //     amountOut = kheops.quoteIn(amountIn, tokenIn, tokenOut);
        // } else if (quoteType == QuoteType.BurnExactInput) {
        //     tokenIn = address(agToken);
        //     tokenOut = collateral;
        //     amountIn = amount * BASE_18;
        //     amountOut = kheops.quoteIn(amountIn, tokenIn, tokenOut);
        // } else if (quoteType == QuoteType.MintExactOutput) {
        //     tokenIn = collateral;
        //     tokenOut = address(agToken);
        //     amountOut = amount * 10 ** BASE_18;
        //     amountIn = kheops.quoteOut(amountOut, tokenIn, tokenOut);
        // } else if (quoteType == QuoteType.BurnExactOutput) {
        //     tokenIn = address(agToken);
        //     tokenOut = collateral;
        //     amountOut = amount * 10 ** decimals;
        //     amountIn = kheops.quoteOut(amountOut, tokenIn, tokenOut);
        // }

        // console.log("Quote successful");

        // // If burning we can't burn more than the reserves
        // if (quoteType == QuoteType.BurnExactInput || quoteType == QuoteType.BurnExactOutput) {
        //     if (amountOut > IERC20(tokenOut).balanceOf(address(kheops))) {
        //         return;
        //     }
        // }

        // // Deal tokens to msg.sender if needed
        // if (IERC20(tokenIn).balanceOf(msg.sender) < amountIn)
        //     deal(address(tokenIn), msg.sender, amountIn - IERC20(tokenIn).balanceOf(msg.sender));

        // // Swap
        // startHoax(msg.sender);
        // IERC20(tokenIn).approve(address(kheops), amountIn);
        // if (quoteType == QuoteType.MintExactInput || quoteType == QuoteType.BurnExactInput) {
        //     kheops.swapExactInput(amountIn, amountOut, tokenIn, tokenOut, msg.sender, block.timestamp + 1 hours);
        // } else {
        //     kheops.swapExactInput(amountOut, amountIn, tokenIn, tokenOut, msg.sender, block.timestamp + 1 hours);
        // }
        // console.log("Swap result: ", IERC20(tokenOut).balanceOf(msg.sender));
    }
}
