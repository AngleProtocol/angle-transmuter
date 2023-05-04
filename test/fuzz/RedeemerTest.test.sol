// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "../mock/MockTokenPermit.sol";
import "../Fixture.sol";

contract RedeemerTest is Fixture {
    using SafeERC20 for IERC20;

    IERC20[] internal _collaterals;
    AggregatorV3Interface[] internal _oracles;
    uint256[] internal _maxTokenAmount;

    function setUp() public override {
        super.setUp();

        // set Fees to 0 on all collaterals
        uint64[] memory xFeeMint = new uint64[](1);
        xFeeMint[0] = uint64(0);
        uint64[] memory xFeeBurn = new uint64[](1);
        xFeeBurn[0] = uint64(BASE_9);
        int64[] memory yFee = new int64[](1);
        yFee[0] = 0;
        uint64[] memory yFeeRedemption = new uint64[](1);
        yFeeRedemption[0] = uint64(BASE_9);
        vm.startPrank(governor);
        kheops.setFees(address(eurA), xFeeMint, yFee, true);
        kheops.setFees(address(eurA), xFeeBurn, yFee, false);
        kheops.setFees(address(eurB), xFeeMint, yFee, true);
        kheops.setFees(address(eurB), xFeeBurn, yFee, false);
        kheops.setFees(address(eurY), xFeeMint, yFee, true);
        kheops.setFees(address(eurY), xFeeBurn, yFee, false);
        kheops.setRedemptionCurveParams(xFeeMint, yFeeRedemption);
        vm.stopPrank();

        _collaterals.push(eurA);
        _collaterals.push(eurB);
        _collaterals.push(eurY);
        _oracles.push(oracleA);
        _oracles.push(oracleB);
        _oracles.push(oracleY);

        _maxTokenAmount.push(10 ** 15 * 10 ** IERC20Metadata(address(_collaterals[0])).decimals());
        _maxTokenAmount.push(10 ** 15 * 10 ** IERC20Metadata(address(_collaterals[1])).decimals());
        _maxTokenAmount.push(10 ** 15 * 10 ** IERC20Metadata(address(_collaterals[2])).decimals());
    }

    // ================================ QUOTEREDEEM ================================

    function testQuoteRedemptionCurve(uint256[3] memory initialAmounts, uint256 transferProportion) public {
        // let's first load the reserves of the protocol
        uint256 mintedStables;
        vm.startPrank(alice);
        for (uint256 i; i < _collaterals.length; i++) {
            initialAmounts[i] = bound(initialAmounts[i], 0, _maxTokenAmount[i]);
            deal(address(_collaterals[i]), alice, initialAmounts[i]);
            _collaterals[i].approve(address(kheops), initialAmounts[i]);
            mintedStables += kheops.swapExactInput(
                initialAmounts[i],
                0,
                address(_collaterals[i]),
                address(agToken),
                alice,
                block.timestamp * 2
            );
        }

        // Send a proportion of these to another user just to complexify the case
        transferProportion = bound(transferProportion, 0, BASE_9);
        agToken.transfer(dylan, (mintedStables * transferProportion) / BASE_9);
        vm.stopPrank();

        // check collateral ratio first
        (uint64 collatRatio, uint256 reservesValue) = kheops.getCollateralRatio();
        assertEq(collatRatio, BASE_9);
        assertEq(reservesValue, mintedStables);

        // currently oracles are all set to 1 --> collateral ratio = 1
        // --> redemption should be exactly in proportion of current balances
        vm.startPrank(alice);
        uint256 amountBurnt = agToken.balanceOf(alice);
        if (mintedStables == 0) vm.expectRevert("Division or modulo by 0");
        (address[] memory tokens, uint256[] memory amounts) = kheops.quoteRedemptionCurve(amountBurnt);
        vm.stopPrank();

        if (mintedStables == 0) return;

        assertEq(tokens.length, 3);
        assertEq(tokens.length, amounts.length);
        assertEq(tokens[0], address(eurA));
        assertEq(tokens[1], address(eurB));
        assertEq(tokens[2], address(eurY));

        assertEq(amounts[0], (eurA.balanceOf(address(kheops)) * amountBurnt) / mintedStables);
        assertEq(amounts[1], (eurB.balanceOf(address(kheops)) * amountBurnt) / mintedStables);
        assertEq(amounts[2], (eurY.balanceOf(address(kheops)) * amountBurnt) / mintedStables);
    }
}
