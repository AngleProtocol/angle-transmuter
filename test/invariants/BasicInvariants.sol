// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Calls } from "./Calls.sol";

import { console } from "forge-std/console.sol";

contract BasicInvariants is Calls {
    function setUp() public virtual override {
        super.setUp();

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = Calls.swap.selector;

        targetSelector(FuzzSelector({ addr: address(this), selectors: selectors }));
        targetContract(address(this));
    }

    function invariantReservesAboveIssued() public {
        (uint256 issued, ) = kheops.getIssuedByCollateral(address(eurA));
        assertLe(
            issued,
            IERC20(eurA).balanceOf(address(kheops)) * 10 ** (18 - IERC20Metadata(address(eurA)).decimals())
        );
        assertLe(
            issued,
            IERC20(eurB).balanceOf(address(kheops)) * 10 ** (18 - IERC20Metadata(address(eurB)).decimals())
        );
    }

    function invariant_callSummary() public view {
        callSummary();
    }

    // Use the following invariant to inspect logs and the stack trace
    function invariant_failure() public {
        assertLe(calls["swap"], 10);
    }
}
