// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { stdError } from "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "../mock/MockTokenPermit.sol";
import "../Fixture.sol";
import "../utils/FunctionUtils.sol";

contract RedeemerTest is Fixture, FunctionUtils {
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

    function testQuoteRedemptionCurveAllAtPeg(uint256[3] memory initialAmounts, uint256 transferProportion) public {
        // let's first load the reserves of the protocol
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
            initialAmounts,
            transferProportion
        );

        // check collateral ratio first
        (uint64 collatRatio, uint256 reservesValue) = kheops.getCollateralRatio();
        assertEq(collatRatio, BASE_9);
        assertEq(reservesValue, mintedStables);

        // currently oracles are all set to 1 --> collateral ratio = 1
        // --> redemption should be exactly in proportion of current balances
        vm.startPrank(alice);
        uint256 amountBurnt = agToken.balanceOf(alice);
        if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
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

    function testQuoteRedemptionCurveGlobalAtPeg(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256[2] memory latestOracleValue
    ) public {
        // let's first load the reserves of the protocol
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
            initialAmounts,
            transferProportion
        );

        // change oracle value but such that total collateralisation is still == 1
        for (uint256 i; i < latestOracleValue.length; i++) {
            latestOracleValue[i] = bound(latestOracleValue[i], 1, BASE_18);
            MockChainlinkOracle(address(_oracles[i])).setLatestAnswer(int256(latestOracleValue[i]));
        }
        uint256 collateralisation;
        for (uint256 i; i < latestOracleValue.length; i++) {
            collateralisation += (latestOracleValue[i] * collateralMintedStables[i]) / BASE_8;
        }

        // compensate as much as possible last oracle value to make collateralRatio == 1
        // it can be impossible if one of the other oracle value is already high enough to make the system over collateralise by itself
        // or if there wasn't any minted via the last collateral
        if (mintedStables > collateralisation && collateralMintedStables[2] > 0) {
            MockChainlinkOracle(address(_oracles[2])).setLatestAnswer(
                int256(((mintedStables - collateralisation) * BASE_8) / collateralMintedStables[2])
            );

            // check collateral ratio first
            (uint64 collatRatio, uint256 reservesValue) = kheops.getCollateralRatio();
            assertApproxEqAbs(collatRatio, BASE_9, 10 wei);
            assertEq(reservesValue, mintedStables);

            // currently oracles are all set to 1 --> collateral ratio = 1
            // --> redemption should be exactly in proportion of current balances
            vm.startPrank(alice);
            uint256 amountBurnt = agToken.balanceOf(alice);
            if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
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

    function testQuoteRedemptionCurveRandomOracles(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256[3] memory latestOracleValue
    ) public {
        // let's first load the reserves of the protocol
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
            initialAmounts,
            transferProportion
        );

        // change oracle value but such that total collateralisation is still == 1
        for (uint256 i; i < latestOracleValue.length; i++) {
            latestOracleValue[i] = bound(latestOracleValue[i], 1, BASE_18);
            MockChainlinkOracle(address(_oracles[i])).setLatestAnswer(int256(latestOracleValue[i]));
        }

        uint256 collateralisation;
        for (uint256 i; i < latestOracleValue.length; i++) {
            collateralisation += (latestOracleValue[i] * collateralMintedStables[i]) / BASE_8;
        }
        uint256 computedCollatRatio;
        if (mintedStables > 0) computedCollatRatio = (collateralisation * BASE_9) / mintedStables;
        else computedCollatRatio = type(uint64).max;

        // check collateral ratio first
        (uint64 collatRatio, uint256 reservesValue) = kheops.getCollateralRatio();
        assertEq(collatRatio, computedCollatRatio);
        assertEq(reservesValue, mintedStables);

        vm.startPrank(alice);
        uint256 amountBurnt = agToken.balanceOf(alice);
        if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
        (address[] memory tokens, uint256[] memory amounts) = kheops.quoteRedemptionCurve(amountBurnt);
        vm.stopPrank();

        if (mintedStables == 0) return;

        assertEq(tokens.length, 3);
        assertEq(tokens.length, amounts.length);
        assertEq(tokens[0], address(eurA));
        assertEq(tokens[1], address(eurB));
        assertEq(tokens[2], address(eurY));

        // we should also receive  in value collatRatio*amountBurnt
        uint256 amountInValueReceived;
        for (uint256 i; i < _oracles.length; i++) {
            console.log("amount received from ", i, amounts[i]);
            (, int256 value, , , ) = _oracles[i].latestRoundData();
            uint8 decimals = IERC20Metadata(address(_collaterals[i])).decimals();
            amountInValueReceived +=
                (uint256(value) * 10 ** 10 * _convertDecimalTo(amounts[i], decimals, 18)) /
                BASE_18;
            console.log("amountInValueReceived ", amountInValueReceived);
        }
        console.log("amountInValueReceived ", amountInValueReceived);
        console.log("collatRatio ", collatRatio);
        console.log("amountBurnt ", amountBurnt);
        if (collatRatio <= BASE_9) {
            //     assertEq(amounts[0], (eurA.balanceOf(address(kheops)) * amountBurnt) / mintedStables);
            //     assertEq(amounts[1], (eurB.balanceOf(address(kheops)) * amountBurnt) / mintedStables);
            //     assertEq(amounts[2], (eurY.balanceOf(address(kheops)) * amountBurnt) / mintedStables);
            //     assertApproxEqAbs(amountInValueReceived, (collatRatio * amountBurnt) / BASE_9, 1 wei);
            //     // assertEq(amountInValueReceived, (BASE_9 * amountBurnt) / collatRatio);
        } else {
            assertEq(
                amounts[0],
                (eurA.balanceOf(address(kheops)) * amountBurnt * BASE_9) / (mintedStables * collatRatio)
            );
            assertEq(
                amounts[1],
                (eurB.balanceOf(address(kheops)) * amountBurnt * BASE_9) / (mintedStables * collatRatio)
            );
            assertEq(
                amounts[2],
                (eurY.balanceOf(address(kheops)) * amountBurnt * BASE_9) / (mintedStables * collatRatio)
            );
            assertLe(amountInValueReceived, amountBurnt);
            // rounding can make you have large difference, let's say you have minted with 1 wei from a collateral with 10 decimals
            // at an oracle of BASE_8, now the same oracle is now at BASE_8+ 1 wei, if you try to redeem
            // you will get 0 instead of 10**(18-10)-1 in value
            // Here we set the delta to 10**12 as the smallest decimals is 6 over all collaterals
            assertApproxEqAbs(amountInValueReceived, amountBurnt, _collaterals.length * 10 ** 12);
        }
    }

    // =================================== UTILS ===================================

    function _loadReserves(
        uint256[3] memory initialAmounts,
        uint256 transferProportion
    ) internal returns (uint256 mintedStables, uint256[] memory collateralMintedStables) {
        collateralMintedStables = new uint256[](_collaterals.length);

        vm.startPrank(alice);
        for (uint256 i; i < _collaterals.length; i++) {
            initialAmounts[i] = bound(initialAmounts[i], 0, _maxTokenAmount[i]);
            deal(address(_collaterals[i]), alice, initialAmounts[i]);
            _collaterals[i].approve(address(kheops), initialAmounts[i]);

            collateralMintedStables[i] = kheops.swapExactInput(
                initialAmounts[i],
                0,
                address(_collaterals[i]),
                address(agToken),
                alice,
                block.timestamp * 2
            );
            mintedStables += collateralMintedStables[i];
        }

        // Send a proportion of these to another user just to complexify the case
        transferProportion = bound(transferProportion, 0, BASE_9);
        agToken.transfer(dylan, (mintedStables * transferProportion) / BASE_9);
        vm.stopPrank();
    }
}
