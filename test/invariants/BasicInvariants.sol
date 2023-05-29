// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

import { IERC20 } from "oz/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "oz/token/ERC20/extensions/IERC20Metadata.sol";

//solhint-disable
import { console } from "forge-std/console.sol";

import { Calls } from "./Calls.sol";

contract BasicInvariants is Calls {
    function setUp() public virtual override {
        super.setUp();

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = Calls.swap.selector;
        selectors[1] = Calls.changeOracle.selector;

        targetSelector(FuzzSelector({ addr: address(this), selectors: selectors }));
        targetSelector(FuzzSelector({ addr: address(this), selectors: selectors }));
        targetContract(address(this));
    }

    // function invariantReservesAboveIssued() public {
    //     (uint256 issuedA, ) = transmuter.getIssuedByCollateral(address(eurA));
    //     assertLe(
    //         issuedA,
    //         IERC20(eurA).balanceOf(address(transmuter)) * 10 ** (18 - IERC20Metadata(address(eurA)).decimals())
    //     );
    //     (uint256 issuedB, ) = transmuter.getIssuedByCollateral(address(eurB));
    //     assertLe(
    //         issuedB,
    //         IERC20(eurB).balanceOf(address(transmuter)) * 10 ** (18 - IERC20Metadata(address(eurB)).decimals())
    //     );
    // }

    function invariantIssuedCoherent() public {
        (uint256 issuedA, uint256 issued) = transmuter.getIssuedByCollateral(address(eurA));
        (uint256 issuedB, ) = transmuter.getIssuedByCollateral(address(eurB));
        (uint256 issuedY, ) = transmuter.getIssuedByCollateral(address(eurY));
        assertEq(issued, issuedA + issuedB + issuedY);
    }

    function invariantSystemState() public view {
        systemState();
    }

    // Use the following invariant to inspect logs and the stack trace
    // function invariant_failure() public {
    //     assertLe(calls["swap"], 15);
    // }
}
