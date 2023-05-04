// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { QuoteType } from "../../contracts/kheops/Storage.sol";
import "../../contracts/utils/Constants.sol";

import { MockChainlinkOracle } from "../mock/MockChainlinkOracle.sol";
import { Fixture } from "../Fixture.sol";

import { console } from "forge-std/console.sol";

contract Calls is Fixture {
    mapping(bytes32 => uint256) public calls;

    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    function systemState() public view {
        console.log("");
        console.log("SYSTEM STATE");
        console.log("");
        console.log("Calls summary:");
        console.log("-------------------");
        console.log("swap", calls["swap"]);
        console.log("oracle", calls["oracle"]);
        console.log("-------------------");
        console.log("");

        (uint256 issuedA, uint256 issued) = kheops.getIssuedByCollateral(address(eurA));
        (uint256 issuedB, ) = kheops.getIssuedByCollateral(address(eurB));
        (uint256 issuedY, ) = kheops.getIssuedByCollateral(address(eurY));
        console.log("Issued A: ", issuedA);
        console.log("Issued B: ", issuedB);
        console.log("Issued Y: ", issuedY);
        console.log("Issued Total: ", issued);
    }

    function swap(uint256 quoteTypeUint, uint256 collatNumber, uint256 amount) public countCall("swap") {
        QuoteType quoteType = QuoteType(bound(collatNumber, 0, 3));
        collatNumber = bound(collatNumber, 0, 2);
        amount = bound(amount, 1, 10 ** 18);

        address collateral;
        if (collatNumber == 0) {
            collateral = address(eurA);
        } else if (collatNumber == 1) {
            collateral = address(eurB);
        } else {
            collateral = address(eurY);
        }
        uint8 decimals = IERC20Metadata(collateral).decimals();

        uint256 amountIn;
        uint256 amountOut;
        address tokenIn;
        address tokenOut;

        console.log("");
        console.log("=========");

        if (quoteType == QuoteType.MintExactInput) {
            console.log("Mint - Input");
            tokenIn = collateral;
            tokenOut = address(agToken);
            amountIn = amount * 10 ** decimals;
            amountOut = kheops.quoteIn(amountIn, tokenIn, tokenOut);
        } else if (quoteType == QuoteType.BurnExactInput) {
            console.log("Burn - Input");
            tokenIn = address(agToken);
            tokenOut = collateral;
            amountIn = amount * BASE_18;
            amountOut = kheops.quoteIn(amountIn, tokenIn, tokenOut);
        } else if (quoteType == QuoteType.MintExactOutput) {
            console.log("Mint - Output");
            tokenIn = collateral;
            tokenOut = address(agToken);
            amountOut = amount * BASE_18;
            amountIn = kheops.quoteOut(amountOut, tokenIn, tokenOut);
        } else if (quoteType == QuoteType.BurnExactOutput) {
            console.log("Burn - Output");
            tokenIn = address(agToken);
            tokenOut = collateral;
            amountOut = amount * 10 ** decimals;
            amountIn = kheops.quoteOut(amountOut, tokenIn, tokenOut);
        }

        console.log("Amount In: ", amountIn);
        console.log("Amount Out: ", amountOut);
        console.log("=========");
        console.log("");

        // If burning we can't burn more than the reserves
        if (quoteType == QuoteType.BurnExactInput || quoteType == QuoteType.BurnExactOutput) {
            if (amountOut > IERC20(tokenOut).balanceOf(address(kheops))) {
                return;
            }
        }

        // Deal tokens to msg.sender if needed
        if (IERC20(tokenIn).balanceOf(msg.sender) < amountIn) {
            deal(address(tokenIn), msg.sender, amountIn - IERC20(tokenIn).balanceOf(msg.sender));
        }

        // Approval
        hoax(msg.sender);
        IERC20(tokenIn).approve(address(kheops), amountIn);

        // Swap
        hoax(msg.sender);
        if (quoteType == QuoteType.MintExactInput || quoteType == QuoteType.BurnExactInput) {
            kheops.swapExactInput(amountIn, amountOut, tokenIn, tokenOut, msg.sender, block.timestamp + 1 hours);
        } else {
            kheops.swapExactOutput(amountOut, amountIn, tokenIn, tokenOut, msg.sender, block.timestamp + 1 hours);
        }
    }

    // Random oracle change of at most 1%
    function changeOracle(uint256 collatNumber, uint256 change) public countCall("oracle") {
        collatNumber = bound(collatNumber, 0, 2);
        change = bound(change, 0, (2 * BASE_18) / 100); // Between 0 and 2%

        MockChainlinkOracle oracle;
        if (collatNumber == 0) {
            oracle = MockChainlinkOracle(address(oracleA));
        } else if (collatNumber == 1) {
            oracle = MockChainlinkOracle(address(oracleB));
        } else {
            oracle = MockChainlinkOracle(address(oracleY));
        }

        (, int256 answer, , , ) = oracle.latestRoundData();
        answer = (answer * int256(change + (99 * BASE_18) / 100)) / int256(BASE_18);
        oracle.setLatestAnswer(answer);
    }
}
