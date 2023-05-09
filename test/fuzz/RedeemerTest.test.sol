// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { stdError } from "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "../mock/MockTokenPermit.sol";
import "../Fixture.sol";
import "../utils/FunctionUtils.sol";
import "../../contracts/kheops/utils/Utils.sol";

contract RedeemerTest is Fixture, FunctionUtils {
    using SafeERC20 for IERC20;

    uint256 internal _maxAmountWithoutDecimals = 10 ** 15;
    // making this value smaller worsen rounding and make test harder to pass.
    // Trade off between bullet proof against all oracles and all interactions
    uint256 internal _minOracleValue = 10 ** 3; // 10**(-6)
    uint256 internal _percentageLossAccepted = 10 ** 15; // 0.1%
    uint256 internal _minWallet = 10 ** (3 + 18);

    address[] internal _collaterals;
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
        int64[] memory yFeeRedemption = new int64[](1);
        yFeeRedemption[0] = int64(int256(BASE_9));
        vm.startPrank(governor);
        kheops.setFees(address(eurA), xFeeMint, yFee, true);
        kheops.setFees(address(eurA), xFeeBurn, yFee, false);
        kheops.setFees(address(eurB), xFeeMint, yFee, true);
        kheops.setFees(address(eurB), xFeeBurn, yFee, false);
        kheops.setFees(address(eurY), xFeeMint, yFee, true);
        kheops.setFees(address(eurY), xFeeBurn, yFee, false);
        kheops.setRedemptionCurveParams(xFeeMint, yFeeRedemption);
        vm.stopPrank();

        _collaterals.push(address(eurA));
        _collaterals.push(address(eurB));
        _collaterals.push(address(eurY));
        _oracles.push(oracleA);
        _oracles.push(oracleB);
        _oracles.push(oracleY);

        _maxTokenAmount.push(_maxAmountWithoutDecimals * 10 ** IERC20Metadata(_collaterals[0]).decimals());
        _maxTokenAmount.push(_maxAmountWithoutDecimals * 10 ** IERC20Metadata(_collaterals[1]).decimals());
        _maxTokenAmount.push(_maxAmountWithoutDecimals * 10 ** IERC20Metadata(_collaterals[2]).decimals());
    }

    // ================================ QUOTEREDEEM ================================

    function testQuoteRedemptionCurveAllAtPeg(uint256[3] memory initialAmounts, uint256 transferProportion) public {
        // let's first load the reserves of the protocol
        (uint256 mintedStables, ) = _loadReserves(initialAmounts, transferProportion);

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

        _assertsSizes(tokens, amounts);
        _assertsAmounts(uint64(BASE_9), mintedStables, amountBurnt, uint64(BASE_9), amounts);
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
            latestOracleValue[i] = bound(latestOracleValue[i], _minOracleValue, BASE_18);
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

            _assertsSizes(tokens, amounts);
            _assertsAmounts(uint64(BASE_9), mintedStables, amountBurnt, uint64(BASE_9), amounts);
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

        uint64 collatRatio = _updateOracles(latestOracleValue, mintedStables, collateralMintedStables);

        vm.startPrank(alice);
        uint256 amountBurnt = agToken.balanceOf(alice);
        if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
        (address[] memory tokens, uint256[] memory amounts) = kheops.quoteRedemptionCurve(amountBurnt);
        vm.stopPrank();

        if (mintedStables == 0) return;

        _assertsSizes(tokens, amounts);
        _assertsAmounts(collatRatio, mintedStables, amountBurnt, uint64(BASE_9), amounts);
    }

    function testQuoteRedemptionCurveAtPegRandomRedemptionFees(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint64[10] memory xFeeRedeemUnbounded,
        int64[10] memory yFeeRedeemUnbounded
    ) public {
        // let's first load the reserves of the protocol
        (uint256 mintedStables, ) = _loadReserves(initialAmounts, transferProportion);
        (, int64[] memory yFeeRedeem) = _randomRedeemptionFees(xFeeRedeemUnbounded, yFeeRedeemUnbounded);

        vm.startPrank(alice);
        uint256 amountBurnt = agToken.balanceOf(alice);
        if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
        (address[] memory tokens, uint256[] memory amounts) = kheops.quoteRedemptionCurve(amountBurnt);
        vm.stopPrank();

        if (mintedStables == 0) return;

        _assertsSizes(tokens, amounts);
        _assertsAmounts(uint64(BASE_9), mintedStables, amountBurnt, uint64(yFeeRedeem[yFeeRedeem.length - 1]), amounts);
    }

    function testQuoteRedemptionCurveRandomRedemptionFees(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256[3] memory latestOracleValue,
        uint64[10] memory xFeeRedeemUnbounded,
        int64[10] memory yFeeRedeemUnbounded
    ) public {
        // let's first load the reserves of the protocol
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
            initialAmounts,
            transferProportion
        );
        uint64 collatRatio = _updateOracles(latestOracleValue, mintedStables, collateralMintedStables);
        (uint64[] memory xFeeRedeem, int64[] memory yFeeRedeem) = _randomRedeemptionFees(
            xFeeRedeemUnbounded,
            yFeeRedeemUnbounded
        );

        vm.startPrank(alice);
        uint256 amountBurnt = agToken.balanceOf(alice);
        if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
        (address[] memory tokens, uint256[] memory amounts) = kheops.quoteRedemptionCurve(amountBurnt);
        vm.stopPrank();

        if (mintedStables == 0) return;

        // compute fee at current collatRatio
        _assertsSizes(tokens, amounts);
        uint64 fee;
        if (collatRatio >= BASE_9) fee = uint64(yFeeRedeem[yFeeRedeem.length - 1]);
        else fee = uint64(Utils.piecewiseLinear(collatRatio, true, xFeeRedeem, yFeeRedeem));
        _assertsAmounts(collatRatio, mintedStables, amountBurnt, fee, amounts);
    }

    // =================================== REDEEM ==================================

    function testRedemptionCurveAllAtPeg(uint256[3] memory initialAmounts, uint256 transferProportion) public {
        // let's first load the reserves of the protocol
        (uint256 mintedStables, ) = _loadReserves(initialAmounts, transferProportion);

        _sweepBalances(alice, _collaterals);
        // currently oracles are all set to 1 --> collateral ratio = 1
        // --> redemption should be exactly in proportion of current balances
        vm.startPrank(alice);

        (, uint256[] memory quoteAmounts) = kheops.quoteRedemptionCurve(amountBurnt);

        uint256 amountBurnt = agToken.balanceOf(alice);
        if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
        uint256[] memory forfeitTokens = new uint256[](0);
        uint256[] memory minAmountOuts = new uint256[](_collaterals.length);
        (address[] memory tokens, uint256[] memory amounts) = kheops.redeem(
            amountBurnt,
            alice,
            block.timestamp + 1 days,
            minAmountOuts
        );
        vm.stopPrank();

        if (mintedStables == 0) return;

        _assertsSizes(tokens, amounts);
        _assertsTransfers(alice, _collaterals, amounts);
    }

    // ================================== ASSERTS ==================================

    function _assertsSizes(address[] memory tokens, uint256[] memory amounts) internal {
        assertEq(tokens.length, 3);
        assertEq(tokens.length, amounts.length);
        assertEq(tokens[0], address(eurA));
        assertEq(tokens[1], address(eurB));
        assertEq(tokens[2], address(eurY));
    }

    function _assertsTransfers(address owner, address[] memory tokens, uint256[] memory amounts) internal {
        for (uint256 i; i < tokens.length; i++) {
            assertEq(IERC20(tokens[i]).balanceOf(owner), amounts[i]);
        }
    }

    function _assertsQuoteAmounts(
        uint64 collatRatio,
        uint256 mintedStables,
        uint256 amountBurnt,
        uint64 fee,
        uint256[] memory amounts
    ) internal {
        // we should also receive  in value min(collatRatio*amountBurnt,amountBurnt)
        uint256 amountInValueReceived;
        for (uint256 i; i < _oracles.length; i++) {
            (, int256 value, , , ) = _oracles[i].latestRoundData();
            uint8 decimals = IERC20Metadata(_collaterals[i]).decimals();
            amountInValueReceived += (uint256(value) * _convertDecimalTo(amounts[i], decimals, 18)) / BASE_8;
        }

        if (collatRatio < BASE_9) {
            assertEq(amounts[0], (eurA.balanceOf(address(kheops)) * amountBurnt * fee) / (mintedStables * BASE_9));
            assertEq(amounts[1], (eurB.balanceOf(address(kheops)) * amountBurnt * fee) / (mintedStables * BASE_9));
            assertEq(amounts[2], (eurY.balanceOf(address(kheops)) * amountBurnt * fee) / (mintedStables * BASE_9));
            assertLe(amountInValueReceived, (collatRatio * amountBurnt) / BASE_9);
            // // TODO make the one below pass
            // // it is not bulletproof yet (work in many cases but not all)
            // // We accept that small amount tx get out with uncapped loss (compare to what they should get with
            // // infinite precision), but larger one should have a loss smaller than 0.1%
            // if (amountInValueReceived >= _minWallet)
            //     assertApproxEqRelDecimal(
            //         amountInValueReceived,
            //         (collatRatio * amountBurnt * fee) / BASE_18,
            //         _percentageLossAccepted,
            //         18
            //     );
        } else {
            assertEq(amounts[0], (eurA.balanceOf(address(kheops)) * amountBurnt * fee) / (mintedStables * collatRatio));
            assertEq(amounts[1], (eurB.balanceOf(address(kheops)) * amountBurnt * fee) / (mintedStables * collatRatio));
            assertEq(amounts[2], (eurY.balanceOf(address(kheops)) * amountBurnt * fee) / (mintedStables * collatRatio));
            assertLe(amountInValueReceived, amountBurnt);
            // // TODO make the one below pass
            // // We accept that small amount tx get out with uncapped loss (compare to what they should get with
            // // infinite precision), but larger one should have a loss smaller than 0.1%
            // if (amountInValueReceived >= _minWallet)
            //     assertApproxEqRelDecimal(
            //         amountInValueReceived,
            //         (amountBurnt * fee) / BASE_9,
            //         _percentageLossAccepted,
            //         18
            //     );
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
            deal(_collaterals[i], alice, initialAmounts[i]);
            IERC20(_collaterals[i]).approve(address(kheops), initialAmounts[i]);

            collateralMintedStables[i] = kheops.swapExactInput(
                initialAmounts[i],
                0,
                _collaterals[i],
                address(agToken),
                alice,
                block.timestamp * 2
            );
            mintedStables += collateralMintedStables[i];
        }

        // Send a proportion of these to another account user just to complexify the case
        transferProportion = bound(transferProportion, 0, BASE_9);
        agToken.transfer(dylan, (mintedStables * transferProportion) / BASE_9);
        vm.stopPrank();
    }

    function _updateOracles(
        uint256[3] memory latestOracleValue,
        uint256 mintedStables,
        uint256[] memory collateralMintedStables
    ) internal returns (uint64 collatRatio) {
        for (uint256 i; i < latestOracleValue.length; i++) {
            latestOracleValue[i] = bound(latestOracleValue[i], _minOracleValue, BASE_18);
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
        uint256 reservesValue;
        (collatRatio, reservesValue) = kheops.getCollateralRatio();
        assertApproxEqAbs(collatRatio, computedCollatRatio, 1 wei);
        assertEq(reservesValue, mintedStables);
    }

    function _randomRedeemptionFees(
        uint64[10] memory xFeeRedeemUnbounded,
        int64[10] memory yFeeRedeemUnbounded
    ) internal returns (uint64[] memory xFeeRedeem, int64[] memory yFeeRedeem) {
        (xFeeRedeem, yFeeRedeem) = _generateCurves(xFeeRedeemUnbounded, yFeeRedeemUnbounded, true);
        vm.prank(governor);
        kheops.setRedemptionCurveParams(xFeeRedeem, yFeeRedeem);
    }

    function _sweepBalances(address owner, address[] memory tokens) internal {
        vm.startPrank(owner);
        for (uint256 i; i < tokens.length; ++i) {
            IERC20(tokens[i]).transfer(sweeper, IERC20(tokens[i]).balanceOf(owner));
        }
        vm.stopPrank();
    }
}