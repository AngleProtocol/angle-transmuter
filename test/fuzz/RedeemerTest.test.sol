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
        yFeeRedemption[0] = 0;
        vm.startPrank(governor);
        kheops.setFees(address(eurA), xFeeMint, yFee, true);
        kheops.setFees(address(eurA), xFeeBurn, yFee, false);
        kheops.setFees(address(eurB), xFeeMint, yFee, true);
        kheops.setFees(address(eurB), xFeeBurn, yFee, false);
        kheops.setFees(address(eurY), xFeeMint, yFee, true);
        kheops.setFees(address(eurY), xFeeBurn, yFee, false);
        kheops.setRedemptionCurveParams(xFeeMint, yFeeRedemption);
        vm.stopPrank();

        // _collaterals = new IERC20[]();
        // _oracles = new AggregatorV3Interface[]();
        // _maxTokenAmount = new uint256[]();
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

    function testQuoteRedemptionCurve(uint256[3] memory initialAmounts) public {
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
        vm.stopPrank();

        // currently oracles are all set to 1 --> collateral ratio = 1 -->

        // assertEq(staker.balanceOf(_alice), amount);
        // assertEq(staker.balanceOf(address(swapper)), 0);
        // assertEq(asset.balanceOf(_alice), 0);
        // assertEq(asset.balanceOf(address(swapper)), 0);
        // assertEq(asset.balanceOf(address(staker)), amount);
    }
}
