// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import { IERC20 } from "oz/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "oz/token/ERC20/extensions/IERC20Metadata.sol";
import { AggregatorV3Interface } from "interfaces/external/chainlink/AggregatorV3Interface.sol";

import { Fixture } from "../Fixture.sol";
import { Trader } from "./actors/Trader.t.sol";
import { Arbitrager } from "./actors/Arbitrager.t.sol";
import { Governance } from "./actors/Governance.t.sol";

//solhint-disable
import { console } from "forge-std/console.sol";

contract BasicInvariants is Fixture {
    uint256 internal constant _NUM_TRADER = 2;
    uint256 internal constant _NUM_ARB = 2;

    Trader internal _traderHandler;
    Arbitrager internal _arbitragerHandler;
    Governance internal _governanceHandler;

    address[] internal _collaterals;
    AggregatorV3Interface[] internal _oracles;

    function setUp() public virtual override {
        super.setUp();

        _collaterals.push(address(eurA));
        _collaterals.push(address(eurB));
        _collaterals.push(address(eurY));
        _oracles.push(oracleA);
        _oracles.push(oracleB);
        _oracles.push(oracleY);

        _traderHandler = new Trader(transmuter, _collaterals, _oracles, _NUM_TRADER);
        _arbitragerHandler = new Arbitrager(transmuter, _collaterals, _oracles, _NUM_ARB);
        _governanceHandler = new Governance(transmuter, _collaterals, _oracles);
        targetContract(address(_traderHandler));
        targetContract(address(_arbitragerHandler));
        targetContract(address(_governanceHandler));

        {
            bytes4[] memory selectors = new bytes4[](1);
            selectors[0] = Trader.swap.selector;
            targetSelector(FuzzSelector({ addr: address(_traderHandler), selectors: selectors }));
        }

        {
            bytes4[] memory selectors = new bytes4[](2);
            selectors[0] = Arbitrager.swap.selector;
            selectors[1] = Arbitrager.redeem.selector;
            targetSelector(FuzzSelector({ addr: address(_arbitragerHandler), selectors: selectors }));
        }
    }

    function systemState() public view {
        console.log("");
        console.log("SYSTEM STATE");
        console.log("");
        console.log("Calls summary:");
        console.log("-------------------");
        console.log("swap", _traderHandler.calls("swap"));
        console.log("oracle", _governanceHandler.calls("oracle"));
        console.log("-------------------");
        console.log("");

        (uint256 issuedA, uint256 issued) = transmuter.getIssuedByCollateral(address(eurA));
        (uint256 issuedB, ) = transmuter.getIssuedByCollateral(address(eurB));
        (uint256 issuedY, ) = transmuter.getIssuedByCollateral(address(eurY));
        console.log("Issued A: ", issuedA);
        console.log("Issued B: ", issuedB);
        console.log("Issued Y: ", issuedY);
        console.log("Issued Total: ", issued);
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

    function invariant_IssuedCoherent() public {
        (uint256 issuedA, uint256 issued) = transmuter.getIssuedByCollateral(address(eurA));
        (uint256 issuedB, ) = transmuter.getIssuedByCollateral(address(eurB));
        (uint256 issuedY, ) = transmuter.getIssuedByCollateral(address(eurY));
        assertEq(issued, issuedA + issuedB + issuedY);
    }

    function invariant_SystemState() public view {
        systemState();
    }

    // Use the following invariant to inspect logs and the stack trace
    // function invariant_failure() public {
    //     assertLe(calls["swap"], 15);
    // }
}
