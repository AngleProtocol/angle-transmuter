// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../../../contracts/utils/CurveHelper.sol";

contract Simulations is Test {
    CurveHelper public helper = new CurveHelper();

    function setUp() public {}
    /*
    function testPriceForImbalance() public {
        for (uint256 i = 1; i < 10; i++) {
            (uint256 balance0, uint256 balance1, uint256 imbalance, uint256 price) = helper.priceForImbalance(
                100,
                1e17 * i
            );
            console.log("====DATA====");
            console.log("balance0", balance0);
            console.log("balance1", balance1);
            console.log("imbalance", imbalance);
            console.log("price", price);
            console.log("====END====");
        }
    }
    */
}
