// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { IERC20Metadata } from "../mock/MockTokenPermit.sol";
import "../Fixture.sol";

contract BaseLevSwapperTest is Fixture {
    using stdStorage for StdStorage;
    using SafeERC20 for IERC20;

    IERC20[] internal _collaterals;
    AggregatorV3Interface[] internal _oracles;
    uint256[] internal _maxTokenAmount;

    function setUp() public override {
        super.setUp();

        // set Fees to 0 on all collaterals
        uint64[] memory xFee = new uint64[](1);
        xMintFee[0] = uint64(0);
        int64[] memory yMintFee = new int64[](4);
        yMintFee[0] = 0;
        Setters.setFees(eurA.collateral, xFee, yFee, true);
        Setters.setFees(eurA.collateral, xFee, yFee, false);
        Setters.setFees(eurB.collateral, xFee, yFee, true);
        Setters.setFees(eurB.collateral, xFee, yFee, false);
        Setters.setFees(eurC.collateral, xFee, yFee, true);
        Setters.setFees(eurC.collateral, xFee, yFee, false);

        _collaterals = new IERC20[]();
        _oracles = new AggregatorV3Interface[]();
        _maxTokenAmount = new uint256[]();
        _collaterals.push(eur_A);
        _collaterals.push(eur_B);
        _collaterals.push(eur_Y);
        _oracles.push(oracle_A);
        _oracles.push(oracle_B);
        _oracles.push(oracle_Y);

        decimalToken = IERC20Metadata(address(asset)).decimals();
        _maxTokenAmount.push(10 ** 15 * 10 ** IERC20Metadata(address(_collaterals[0])).decimals().decimals());
        _maxTokenAmount.push(10 ** 15 * 10 ** IERC20Metadata(address(_collaterals[1])).decimals().decimals());
        _maxTokenAmount.push(10 ** 15 * 10 ** IERC20Metadata(address(_collaterals[2])).decimals().decimals());
    }

    // ================================ QUOTEREDEEM ================================

    function testQuoteRedemptionCurve(uint256[3] memory initialAmounts) public {
        // let's first load the reserves of the protocol
        uint256 mintedStables;
        vm.startPrank(_alice);
        for (uint256 i; i < _collaterals.length; i++) {
            initialAmounts[i] = bound(initialAmounts[i], 0, maxTokenAmount[i]);
            deal(address(_collaterals[i]), address(_alice), initialAmounts[i]);
            _collaterals[i].approve(address(kheops), initialAmounts[i]);
            mintedStables += kheops.swapExactInput(
                initialAmounts[i],
                0,
                address(_collaterals[i]),
                address(agToken),
                _alice,
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
