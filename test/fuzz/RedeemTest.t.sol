// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "oz/token/ERC20/utils/SafeERC20.sol";
import "oz/utils/Strings.sol";

import { stdError } from "forge-std/Test.sol";

import { IERC20Metadata } from "mock/MockTokenPermit.sol";

import { ManagerStorage } from "contracts/kheops/Storage.sol";
import "contracts/kheops/libraries/LibHelpers.sol";

import "../Fixture.sol";
import "../utils/FunctionUtils.sol";

struct SubCollateralStorage {
    // The collateral corresponding to the manager must also be in the list
    IERC20[] subCollaterals;
    AggregatorV3Interface[] oracles;
}

contract RedeemTest is Fixture, FunctionUtils {
    using SafeERC20 for IERC20;

    uint256 internal _maxAmountWithoutDecimals = 10 ** 15;
    // making this value smaller worsen rounding and make test harder to pass.
    // Trade off between bullet proof against all oracles and all interactions
    uint256 internal _minOracleValue = 10 ** 3; // 10**(-6)
    uint256 internal _percentageLossAccepted = 10 ** 15; // 0.1%
    uint256 internal _minWallet = 10 ** (3 + 18);

    address[] internal _collaterals;
    mapping(address => SubCollateralStorage) internal _subCollaterals;
    AggregatorV3Interface[] internal _oracles;
    uint256[] internal _maxTokenAmount;
    mapping(address => MockManager) internal _managers;

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

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                      QUOTEREDEEM                                                   
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testQuoteRedeemAllAtPeg(uint256[3] memory initialAmounts, uint256 transferProportion) public {
        initialAmounts[0] = 0;
        initialAmounts[1] = 0;
        initialAmounts[2] = 0;
        transferProportion = 0;
        // let's first load the reserves of the protocol
        (uint256 mintedStables, ) = _loadReserves(initialAmounts, transferProportion);

        // check collateral ratio first
        (uint64 collatRatio, uint256 reservesValue) = kheops.getCollateralRatio();
        if (mintedStables > 0) assertEq(collatRatio, BASE_9);
        else assertEq(collatRatio, type(uint64).max);
        assertEq(reservesValue, mintedStables);

        // currently oracles are all set to 1 --> collateral ratio = 1
        // --> redemption should be exactly in proportion of current balances
        vm.startPrank(alice);
        uint256 amountBurnt = agToken.balanceOf(alice);
        if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
        (address[] memory tokens, uint256[] memory amounts) = kheops.quoteRedemptionCurve(amountBurnt);
        vm.stopPrank();

        if (mintedStables == 0) return;

        _assertSizes(tokens, amounts);
        _assertQuoteAmounts(uint64(BASE_9), mintedStables, amountBurnt, uint64(BASE_9), amounts);
    }

    function testQuoteRedeemGlobalAtPeg(
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
        for (uint256 i; i < latestOracleValue.length; ++i) {
            latestOracleValue[i] = bound(latestOracleValue[i], _minOracleValue, BASE_18);
            MockChainlinkOracle(address(_oracles[i])).setLatestAnswer(int256(latestOracleValue[i]));
        }
        uint256 collateralisation;
        for (uint256 i; i < latestOracleValue.length; ++i) {
            collateralisation += (latestOracleValue[i] * collateralMintedStables[i]) / BASE_8;
        }

        // compensate as much as possible last oracle value to make collateralRatio == 1
        // it can be impossible if one of the other oracle value is already high enough to
        // make the system over collateralised by itself or if there wasn't any minted via the last collateral
        if (mintedStables > collateralisation && collateralMintedStables[2] > 0) {
            MockChainlinkOracle(address(_oracles[2])).setLatestAnswer(
                int256(((mintedStables - collateralisation) * BASE_8) / collateralMintedStables[2])
            );

            // check collateral ratio first
            (uint64 collatRatio, uint256 reservesValue) = kheops.getCollateralRatio();
            if (mintedStables > 0) assertApproxEqAbs(collatRatio, BASE_9, 1e5);
            else assertEq(collatRatio, type(uint64).max);
            assertEq(reservesValue, mintedStables);

            // currently oracles are all set to 1 --> collateral ratio = 1
            // --> redemption should be exactly in proportion of current balances
            vm.startPrank(alice);
            uint256 amountBurnt = agToken.balanceOf(alice);
            if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
            (address[] memory tokens, uint256[] memory amounts) = kheops.quoteRedemptionCurve(amountBurnt);
            vm.stopPrank();

            if (mintedStables == 0) return;

            _assertSizes(tokens, amounts);
            _assertQuoteAmounts(uint64(BASE_9), mintedStables, amountBurnt, uint64(BASE_9), amounts);
        }
    }

    function testQuoteRedeemRandomOracles(
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

        _assertSizes(tokens, amounts);
        _assertQuoteAmounts(collatRatio, mintedStables, amountBurnt, uint64(BASE_9), amounts);
    }

    function testQuoteRedeemAtPegRandomFees(
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

        _assertSizes(tokens, amounts);
        _assertQuoteAmounts(
            uint64(BASE_9),
            mintedStables,
            amountBurnt,
            uint64(yFeeRedeem[yFeeRedeem.length - 1]),
            amounts
        );
    }

    function testQuoteRedeemRandomFees(
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
        _assertSizes(tokens, amounts);
        uint64 fee;
        if (collatRatio >= BASE_9) fee = uint64(yFeeRedeem[yFeeRedeem.length - 1]);
        else fee = uint64(LibHelpers.piecewiseLinear(collatRatio, true, xFeeRedeem, yFeeRedeem));
        _assertQuoteAmounts(collatRatio, mintedStables, amountBurnt, fee, amounts);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        REDEEM                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testRedeemAllAtPeg(uint256[3] memory initialAmounts, uint256 transferProportion) public {
        // let's first load the reserves of the protocol
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
            initialAmounts,
            transferProportion
        );

        _sweepBalances(alice, _collaterals);
        // currently oracles are all set to 1 --> collateral ratio = 1
        // --> redemption should be exactly in proportion of current balances
        vm.startPrank(alice);
        uint256 amountBurnt = agToken.balanceOf(alice);
        if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
        (, uint256[] memory quoteAmounts) = kheops.quoteRedemptionCurve(amountBurnt);
        if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
        // uint256[] memory forfeitTokens = new uint256[](0);
        uint256[] memory minAmountOuts = new uint256[](_collaterals.length);
        (address[] memory tokens, uint256[] memory amounts) = kheops.redeem(
            amountBurnt,
            alice,
            block.timestamp + 1 days,
            minAmountOuts
        );
        vm.stopPrank();

        if (mintedStables == 0) return;

        assertEq(amounts, quoteAmounts);
        _assertSizes(tokens, amounts);
        _assertTransfers(alice, _collaterals, amounts);

        // Testing implicitly the ks.normalizer and ks.normalizedStables
        for (uint256 i; i < _collaterals.length; ++i) {
            (uint256 stableIssuedByCollateral, uint256 totalStable) = kheops.getIssuedByCollateral(_collaterals[i]);
            assertApproxEqAbs(
                stableIssuedByCollateral,
                (collateralMintedStables[i] * (mintedStables - amountBurnt)) / mintedStables,
                1 wei
            );
            assertEq(totalStable, mintedStables - amountBurnt);
        }
    }

    function testRedeemRandomFees(
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
        // Mute warnings
        collatRatio;
        xFeeRedeem;
        yFeeRedeem;

        _sweepBalances(alice, _collaterals);

        vm.startPrank(alice);
        uint256 amountBurnt = agToken.balanceOf(alice);
        if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
        (, uint256[] memory quoteAmounts) = kheops.quoteRedemptionCurve(amountBurnt);
        if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
        address[] memory tokens;
        uint256[] memory amounts;
        {
            // uint256[] memory forfeitTokens = new uint256[](0);
            uint256[] memory minAmountOuts = new uint256[](_collaterals.length);
            (tokens, amounts) = kheops.redeem(amountBurnt, alice, block.timestamp + 1 days, minAmountOuts);
        }
        vm.stopPrank();

        if (mintedStables == 0) return;

        // compute fee at current collatRatio
        assertEq(amounts, quoteAmounts);
        _assertSizes(tokens, amounts);
        _assertTransfers(alice, _collaterals, amounts);

        // Testing implicitly the ks.normalizer and ks.normalizedStables
        for (uint256 i; i < _collaterals.length; ++i) {
            (uint256 stableIssuedByCollateral, uint256 totalStable) = kheops.getIssuedByCollateral(_collaterals[i]);
            assertApproxEqAbs(
                stableIssuedByCollateral,
                (collateralMintedStables[i] * (mintedStables - amountBurnt)) / mintedStables,
                1 wei
            );
            assertEq(totalStable, mintedStables - amountBurnt);
        }
    }

    function testMultiRedemptionCurveRandomRedemptionFees(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256 redeemProportion,
        uint256[3] memory latestOracleValue,
        uint64[10] memory xFeeRedeemUnbounded,
        int64[10] memory yFeeRedeemUnbounded
    ) public {
        // let's first load the reserves of the protocol
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
            initialAmounts,
            transferProportion
        );
        _updateOracles(latestOracleValue, mintedStables, collateralMintedStables);
        _randomRedeemptionFees(xFeeRedeemUnbounded, yFeeRedeemUnbounded);
        _sweepBalances(alice, _collaterals);
        _sweepBalances(bob, _collaterals);

        // first redeem
        vm.startPrank(alice);
        uint256 amountBurnt = agToken.balanceOf(alice);
        uint256 amountBurntBob;
        if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
        (, uint256[] memory quoteAmounts) = kheops.quoteRedemptionCurve(amountBurnt);
        if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
        {
            address[] memory tokens;
            uint256[] memory amounts;
            {
                uint256[] memory minAmountOuts = new uint256[](_collaterals.length);
                (tokens, amounts) = kheops.redeem(amountBurnt, alice, block.timestamp + 1 days, minAmountOuts);
            }
            vm.stopPrank();

            if (mintedStables == 0) return;

            // compute fee at current collatRatio
            assertEq(amounts, quoteAmounts);
            _assertSizes(tokens, amounts);
            _assertTransfers(alice, _collaterals, amounts);

            // Testing implicitly the ks.normalizer and ks.normalizedStables
            for (uint256 i; i < _collaterals.length; ++i) {
                (uint256 stableIssuedByCollateral, uint256 totalStable) = kheops.getIssuedByCollateral(_collaterals[i]);
                assertApproxEqAbs(
                    stableIssuedByCollateral,
                    (collateralMintedStables[i] * (mintedStables - amountBurnt)) / mintedStables,
                    1 wei
                );
                assertEq(totalStable, mintedStables - amountBurnt);
            }
            mintedStables -= amountBurnt;

            // now do a second redeem to test with non trivial ks.normalizer and ks.normalizedStables
            vm.startPrank(bob);
            redeemProportion = bound(redeemProportion, 0, BASE_9);
            amountBurntBob = (agToken.balanceOf(bob) * redeemProportion) / BASE_9;
            if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
            (, quoteAmounts) = kheops.quoteRedemptionCurve(amountBurntBob);
            if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
            {
                uint256[] memory minAmountOuts = new uint256[](_collaterals.length);
                (tokens, amounts) = kheops.redeem(amountBurntBob, bob, block.timestamp + 1 days, minAmountOuts);
            }
            vm.stopPrank();

            if (mintedStables == 0) return;

            // compute fee at current collatRatio
            assertEq(amounts, quoteAmounts);
            _assertSizes(tokens, amounts);
            _assertTransfers(bob, _collaterals, amounts);
        }

        // Testing implicitly the ks.normalizer and ks.normalizedStables
        uint256 totalStable2;
        for (uint256 i; i < _collaterals.length; ++i) {
            uint256 stableIssuedByCollateral;
            (stableIssuedByCollateral, totalStable2) = kheops.getIssuedByCollateral(_collaterals[i]);
            uint256 realStableIssueByCollateralLeft = (collateralMintedStables[i] * (mintedStables - amountBurntBob)) /
                (mintedStables + amountBurnt);
            _assertApproxEqRelDecimalWithTolerance(
                realStableIssueByCollateralLeft,
                stableIssuedByCollateral,
                realStableIssueByCollateralLeft,
                _MAX_PERCENTAGE_DEVIATION,
                18
            );
        }
        _assertApproxEqRelDecimalWithTolerance(
            mintedStables - amountBurntBob,
            totalStable2,
            mintedStables - amountBurntBob,
            _MAX_PERCENTAGE_DEVIATION,
            18
        );
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                  REDEEM WITH MANAGER                                               
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testQuoteRedemptionCurveWithManagerRandomRedemptionFees(
        uint256[3] memory initialAmounts,
        uint256[3] memory nbrSubCollaterals,
        bool[3] memory isManaged,
        uint256[3 * _MAX_SUB_COLLATERALS] memory airdropAmounts,
        uint256 transferProportion,
        uint256[3 * _MAX_SUB_COLLATERALS] memory latestSubCollatOracleValue,
        uint256[3 * _MAX_SUB_COLLATERALS] memory subCollatDecimals,
        uint256[3] memory latestOracleValue,
        uint64[10] memory xFeeRedeemUnbounded,
        int64[10] memory yFeeRedeemUnbounded
    ) public {
        for (uint256 i; i < _collaterals.length; ++i) {
            // Randomly set subcollaterals and manager if needed
            (IERC20[] memory subCollaterals, AggregatorV3Interface[] memory oracles) = _createManager(
                _collaterals[i],
                nbrSubCollaterals[i],
                isManaged[i],
                i * _MAX_SUB_COLLATERALS,
                latestSubCollatOracleValue,
                subCollatDecimals
            );
            if (subCollaterals.length > 0)
                _subCollaterals[_collaterals[i]] = SubCollateralStorage(subCollaterals, oracles);
        }

        // let's first load the reserves of the protocol
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
            initialAmounts,
            transferProportion
        );

        // airdrop amounts in the subcollaterals
        for (uint256 i; i < _collaterals.length; ++i) {
            if (_subCollaterals[_collaterals[i]].subCollaterals.length > 0) {
                _loadSubCollaterals(address(_collaterals[i]), airdropAmounts, i * _MAX_SUB_COLLATERALS);
            }
        }

        (uint64 collatRatio, bool collatRatioAboveLimit) = _updateOraclesWithSubCollaterals(
            latestOracleValue,
            mintedStables,
            collateralMintedStables,
            airdropAmounts
        );

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
        _assertSizesWithManager(tokens, amounts);
        uint64 fee;
        if (collatRatio >= BASE_9) fee = uint64(yFeeRedeem[yFeeRedeem.length - 1]);
        else fee = uint64(LibHelpers.piecewiseLinear(collatRatio, true, xFeeRedeem, yFeeRedeem));
        _assertQuoteAmountsWithManager(collatRatio, collatRatioAboveLimit, mintedStables, amountBurnt, fee, amounts);
    }

    function testMultiRedemptionCurveWithManagerRandomRedemptionFees(
        uint256[3] memory initialAmounts,
        uint256[3] memory nbrSubCollaterals,
        bool[3] memory isManaged,
        uint256[3 * _MAX_SUB_COLLATERALS] memory airdropAmounts,
        uint256[3 * _MAX_SUB_COLLATERALS] memory latestSubCollatOracleValue,
        uint256[3 * _MAX_SUB_COLLATERALS] memory subCollatDecimals,
        uint256 transferProportion,
        uint256 redeemProportion,
        uint256[3] memory latestOracleValue,
        uint64[10] memory xFeeRedeemUnbounded,
        int64[10] memory yFeeRedeemUnbounded
    ) public {
        for (uint256 i; i < _collaterals.length; ++i) {
            // Randomly set subcollaterals and manager if needed
            (IERC20[] memory subCollaterals, AggregatorV3Interface[] memory oracles) = _createManager(
                _collaterals[i],
                nbrSubCollaterals[i],
                isManaged[i],
                i * _MAX_SUB_COLLATERALS,
                latestSubCollatOracleValue,
                subCollatDecimals
            );
            _subCollaterals[_collaterals[i]] = SubCollateralStorage(subCollaterals, oracles);
        }

        // let's first load the reserves of the protocol
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
            initialAmounts,
            transferProportion
        );
        // airdrop amounts in the subcollaterals
        for (uint256 i; i < _collaterals.length; ++i) {
            if (_subCollaterals[_collaterals[i]].subCollaterals.length > 0) {
                _loadSubCollaterals(address(_collaterals[i]), airdropAmounts, i * _MAX_SUB_COLLATERALS);
            }
        }
        _updateOraclesWithSubCollaterals(latestOracleValue, mintedStables, collateralMintedStables, airdropAmounts);
        _randomRedeemptionFees(xFeeRedeemUnbounded, yFeeRedeemUnbounded);
        _sweepBalancesWithManager(alice, _collaterals);
        _sweepBalancesWithManager(bob, _collaterals);

        // first redeem
        vm.startPrank(alice);
        uint256 amountBurnt = agToken.balanceOf(alice);
        uint256 amountBurntBob;
        if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
        (, uint256[] memory quoteAmounts) = kheops.quoteRedemptionCurve(amountBurnt);
        if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
        {
            address[] memory tokens;
            uint256[] memory amounts;
            {
                uint256[] memory minAmountOuts = new uint256[](quoteAmounts.length);
                (tokens, amounts) = kheops.redeem(amountBurnt, alice, block.timestamp + 1 days, minAmountOuts);
            }
            vm.stopPrank();

            if (mintedStables == 0) return;

            // compute fee at current collatRatio
            assertEq(amounts, quoteAmounts);
            _assertSizesWithManager(tokens, amounts);
            {
                address[] memory forfeitTokens;
                _assertTransfersWithManager(alice, _collaterals, forfeitTokens, amounts);
            }
            // Testing implicitly the ks.normalizer and ks.normalizedStables
            for (uint256 i; i < _collaterals.length; ++i) {
                (uint256 stableIssuedByCollateral, uint256 totalStable) = kheops.getIssuedByCollateral(_collaterals[i]);
                assertApproxEqAbs(
                    stableIssuedByCollateral,
                    (collateralMintedStables[i] * (mintedStables - amountBurnt)) / mintedStables,
                    1 wei
                );
                assertEq(totalStable, mintedStables - amountBurnt);
            }
            mintedStables -= amountBurnt;

            // now do a second redeem to test with non trivial ks.normalizer and ks.normalizedStables
            vm.startPrank(bob);
            redeemProportion = bound(redeemProportion, 0, BASE_9);
            amountBurntBob = (agToken.balanceOf(bob) * redeemProportion) / BASE_9;
            if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
            (, quoteAmounts) = kheops.quoteRedemptionCurve(amountBurntBob);
            if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
            {
                uint256[] memory minAmountOuts = new uint256[](quoteAmounts.length);
                (tokens, amounts) = kheops.redeem(amountBurntBob, bob, block.timestamp + 1 days, minAmountOuts);
            }
            vm.stopPrank();

            if (mintedStables == 0) return;

            // compute fee at current collatRatio
            assertEq(amounts, quoteAmounts);
            _assertSizesWithManager(tokens, amounts);
            {
                address[] memory forfeitTokens;
                _assertTransfersWithManager(bob, _collaterals, forfeitTokens, amounts);
            }
        }

        // Testing implicitly the ks.normalizer and ks.normalizedStables
        uint256 totalStable2;
        for (uint256 i; i < _collaterals.length; ++i) {
            uint256 stableIssuedByCollateral;
            (stableIssuedByCollateral, totalStable2) = kheops.getIssuedByCollateral(_collaterals[i]);
            uint256 realStableIssueByCollateralLeft = (collateralMintedStables[i] * (mintedStables - amountBurntBob)) /
                (mintedStables + amountBurnt);
            _assertApproxEqRelDecimalWithTolerance(
                realStableIssueByCollateralLeft,
                stableIssuedByCollateral,
                realStableIssueByCollateralLeft,
                _MAX_PERCENTAGE_DEVIATION,
                18
            );
        }
        _assertApproxEqRelDecimalWithTolerance(
            mintedStables - amountBurntBob,
            totalStable2,
            mintedStables - amountBurntBob,
            _MAX_PERCENTAGE_DEVIATION,
            18
        );
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                  REDEEM WITH FORFEIT                                               
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testMultiForfeitRedemptionCurveWithManagerRandomRedemptionFees(
        uint256[3] memory initialAmounts,
        uint256[3] memory nbrSubCollaterals,
        bool[3] memory isManaged,
        uint256[3 * _MAX_SUB_COLLATERALS] memory airdropAmounts,
        uint256[3 * _MAX_SUB_COLLATERALS] memory latestSubCollatOracleValue,
        uint256[3 * _MAX_SUB_COLLATERALS] memory subCollatDecimals,
        bool[3 * (_MAX_SUB_COLLATERALS + 1)] memory areForfeit,
        uint256 transferProportion,
        uint256 redeemProportion,
        uint256[3] memory latestOracleValue,
        uint64[10] memory xFeeRedeemUnbounded,
        int64[10] memory yFeeRedeemUnbounded
    ) public {
        for (uint256 i; i < _collaterals.length; ++i) {
            // Randomly set subcollaterals and manager if needed
            (IERC20[] memory subCollaterals, AggregatorV3Interface[] memory oracles) = _createManager(
                _collaterals[i],
                nbrSubCollaterals[i],
                isManaged[i],
                i * _MAX_SUB_COLLATERALS,
                latestSubCollatOracleValue,
                subCollatDecimals
            );
            _subCollaterals[_collaterals[i]] = SubCollateralStorage(subCollaterals, oracles);
        }

        // let's first load the reserves of the protocol
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
            initialAmounts,
            transferProportion
        );
        // airdrop amounts in the subcollaterals
        for (uint256 i; i < _collaterals.length; ++i) {
            if (_subCollaterals[_collaterals[i]].subCollaterals.length > 0) {
                _loadSubCollaterals(address(_collaterals[i]), airdropAmounts, i * _MAX_SUB_COLLATERALS);
            }
        }
        _updateOraclesWithSubCollaterals(latestOracleValue, mintedStables, collateralMintedStables, airdropAmounts);
        _randomRedeemptionFees(xFeeRedeemUnbounded, yFeeRedeemUnbounded);
        _sweepBalancesWithManager(alice, _collaterals);
        _sweepBalancesWithManager(bob, _collaterals);

        // first redeem
        vm.startPrank(alice);
        uint256 amountBurnt = agToken.balanceOf(alice);
        uint256 amountBurntBob;
        if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
        (, uint256[] memory quoteAmounts) = kheops.quoteRedemptionCurve(amountBurnt);
        {
            address[] memory tokens;
            uint256[] memory amounts;
            address[] memory forfeitTokens = _getForfeitTokens(areForfeit);
            {
                uint256[] memory minAmountOuts = new uint256[](quoteAmounts.length);
                if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
                (tokens, amounts) = kheops.redeemWithForfeit(
                    amountBurnt,
                    alice,
                    block.timestamp + 1 days,
                    minAmountOuts,
                    forfeitTokens
                );
            }
            vm.stopPrank();

            if (mintedStables == 0) return;

            // compute fee at current collatRatio
            assertEq(amounts, quoteAmounts);
            _assertSizesWithManager(tokens, amounts);
            _assertTransfersWithManager(alice, _collaterals, forfeitTokens, amounts);

            // Testing implicitly the ks.normalizer and ks.normalizedStables
            for (uint256 i; i < _collaterals.length; ++i) {
                (uint256 stableIssuedByCollateral, uint256 totalStable) = kheops.getIssuedByCollateral(_collaterals[i]);
                assertApproxEqAbs(
                    stableIssuedByCollateral,
                    (collateralMintedStables[i] * (mintedStables - amountBurnt)) / mintedStables,
                    1 wei
                );
                assertEq(totalStable, mintedStables - amountBurnt);
            }
            mintedStables -= amountBurnt;

            // now do a second redeem to test with non trivial ks.normalizer and ks.normalizedStables
            vm.startPrank(bob);
            redeemProportion = bound(redeemProportion, 0, BASE_9);
            amountBurntBob = (agToken.balanceOf(bob) * redeemProportion) / BASE_9;
            if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
            (, quoteAmounts) = kheops.quoteRedemptionCurve(amountBurntBob);
            if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
            {
                uint256[] memory minAmountOuts = new uint256[](quoteAmounts.length);
                (tokens, amounts) = kheops.redeem(amountBurntBob, bob, block.timestamp + 1 days, minAmountOuts);
            }
            vm.stopPrank();

            if (mintedStables == 0) return;

            // compute fee at current collatRatio
            assertEq(amounts, quoteAmounts);
            _assertSizesWithManager(tokens, amounts);
            {
                address[] memory forfeitTokens2;
                _assertTransfersWithManager(bob, _collaterals, forfeitTokens2, amounts);
            }
        }

        // Testing implicitly the ks.normalizer and ks.normalizedStables
        uint256 totalStable2;
        for (uint256 i; i < _collaterals.length; ++i) {
            uint256 stableIssuedByCollateral;
            (stableIssuedByCollateral, totalStable2) = kheops.getIssuedByCollateral(_collaterals[i]);
            uint256 realStableIssueByCollateralLeft = (collateralMintedStables[i] * (mintedStables - amountBurntBob)) /
                (mintedStables + amountBurnt);
            _assertApproxEqRelDecimalWithTolerance(
                realStableIssueByCollateralLeft,
                stableIssuedByCollateral,
                realStableIssueByCollateralLeft,
                _MAX_PERCENTAGE_DEVIATION,
                18
            );
        }
        _assertApproxEqRelDecimalWithTolerance(
            mintedStables - amountBurntBob,
            totalStable2,
            mintedStables - amountBurntBob,
            _MAX_PERCENTAGE_DEVIATION,
            18
        );
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        ASSERTS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _assertSizes(address[] memory tokens, uint256[] memory amounts) internal {
        assertEq(tokens.length, 3);
        assertEq(tokens.length, amounts.length);
        assertEq(tokens[0], address(eurA));
        assertEq(tokens[1], address(eurB));
        assertEq(tokens[2], address(eurY));
    }

    function _assertSizesWithManager(address[] memory tokens, uint256[] memory amounts) internal {
        uint256 nbrTokens;
        uint256 count;
        for (uint256 i; i < _oracles.length; ++i) {
            IERC20[] memory listSubCollaterals = _subCollaterals[_collaterals[i]].subCollaterals;
            nbrTokens += listSubCollaterals.length > 0 ? listSubCollaterals.length : 1;
            assertEq(tokens[count++], _collaterals[i]);
            // we don't double count the real collateral
            for (uint256 k = 1; k < listSubCollaterals.length; k++) {
                assertEq(tokens[count++], address(listSubCollaterals[k]));
            }
        }
        assertEq(tokens.length, nbrTokens);
        assertEq(tokens.length, amounts.length);
    }

    function _assertTransfers(address owner, address[] memory tokens, uint256[] memory amounts) internal {
        for (uint256 i; i < tokens.length; ++i) {
            assertEq(IERC20(tokens[i]).balanceOf(owner), amounts[i]);
        }
    }

    function _assertTransfersWithManager(
        address owner,
        address[] memory tokens,
        address[] memory forfeitTokens,
        uint256[] memory amounts
    ) internal {
        uint256 count;
        for (uint256 i; i < tokens.length; ++i) {
            IERC20[] memory listSubCollaterals = _subCollaterals[_collaterals[i]].subCollaterals;
            if (!_inList(forfeitTokens, tokens[i])) assertEq(IERC20(tokens[i]).balanceOf(owner), amounts[count]);
            else assertEq(IERC20(tokens[i]).balanceOf(owner), 0);
            count++;
            // we don't double count the real collateral
            for (uint256 k = 1; k < listSubCollaterals.length; k++) {
                if (!_inList(forfeitTokens, address(listSubCollaterals[k])))
                    assertEq(listSubCollaterals[k].balanceOf(owner), amounts[count]);
                else assertEq(IERC20(listSubCollaterals[k]).balanceOf(owner), 0);
                count++;
            }
        }
    }

    function _assertQuoteAmounts(
        uint64 collatRatio,
        uint256 mintedStables,
        uint256 amountBurnt,
        uint64 fee,
        uint256[] memory amounts
    ) internal {
        // we should also receive  in value min(collatRatio*amountBurnt,amountBurnt)
        uint256 amountInValueReceived;
        for (uint256 i; i < _oracles.length; ++i) {
            (, int256 value, , , ) = _oracles[i].latestRoundData();
            uint8 decimals = IERC20Metadata(_collaterals[i]).decimals();
            amountInValueReceived += (uint256(value) * _convertDecimalTo(amounts[i], decimals, 18)) / BASE_8;
        }

        uint256 denom = (mintedStables * BASE_9);
        uint256 valueCheck = (collatRatio * amountBurnt * fee) / BASE_18;
        if (collatRatio >= BASE_9) {
            denom = (mintedStables * collatRatio);
            // for rounding errors
            assertLe(amountInValueReceived, amountBurnt + 1);
            valueCheck = (amountBurnt * fee) / BASE_9;
        }
        assertApproxEqAbs(amounts[0], (eurA.balanceOf(address(kheops)) * amountBurnt * fee) / denom, 1 wei);
        assertApproxEqAbs(amounts[1], (eurB.balanceOf(address(kheops)) * amountBurnt * fee) / denom, 1 wei);
        assertApproxEqAbs(amounts[2], (eurY.balanceOf(address(kheops)) * amountBurnt * fee) / denom, 1 wei);
        if (collatRatio < BASE_9) {
            assertLe(amountInValueReceived, (collatRatio * amountBurnt) / BASE_9);
        }
        // TODO make the one below pass: it is not bulletproof yet (work in many cases but not all)
        // We accept that small amount tx get out with uncapped loss (compare to what they should get with
        // infinite precision), but larger one should have a loss smaller than 0.1%
        // if (amountInValueReceived >= _minWallet)
        //     assertApproxEqRelDecimal(
        //         amountInValueReceived,
        //         valueCheck,
        //         _percentageLossAccepted,
        //         18
        //     );
    }

    function _assertQuoteAmountsWithManager(
        uint64 collatRatio,
        bool collatRatioAboveLimit,
        uint256 mintedStables,
        uint256 amountBurnt,
        uint64 fee,
        uint256[] memory amounts
    ) internal {
        // we should also receive  in value `min(collatRatio*amountBurnt,amountBurnt)`
        uint256 amountInValueReceived;
        {
            uint256 count;
            for (uint256 i; i < _collaterals.length; ++i) {
                {
                    (, int256 value, , , ) = _oracles[i].latestRoundData();
                    uint8 decimals = IERC20Metadata(_collaterals[i]).decimals();
                    amountInValueReceived +=
                        (uint256(value) * _convertDecimalTo(amounts[count++], decimals, 18)) /
                        BASE_8;
                }
                IERC20[] memory listSubCollaterals = _subCollaterals[_collaterals[i]].subCollaterals;
                AggregatorV3Interface[] memory listOracles = _subCollaterals[_collaterals[i]].oracles;
                // we don't double count the real collateral
                for (uint256 k = 1; k < listSubCollaterals.length; k++) {
                    (, int256 value, , , ) = listOracles[k - 1].latestRoundData();
                    uint8 decimals = IERC20Metadata(address(listSubCollaterals[k])).decimals();
                    amountInValueReceived +=
                        (uint256(value) * _convertDecimalTo(amounts[count++], decimals, 18)) /
                        BASE_8;
                }
            }
        }

        uint256 count2;
        for (uint256 i; i < _oracles.length; ++i) {
            IERC20[] memory listSubCollaterals = _subCollaterals[_collaterals[i]].subCollaterals;
            for (uint256 k = 0; k < listSubCollaterals.length; ++k) {
                uint256 expect;
                uint256 subCollateralBalance;
                if (address(_managers[_collaterals[i]]) == address(0))
                    subCollateralBalance = listSubCollaterals[k].balanceOf(address(kheops));
                else subCollateralBalance = listSubCollaterals[k].balanceOf(address(_managers[_collaterals[i]]));
                if (collatRatio < BASE_9) {
                    expect = (subCollateralBalance * amountBurnt * fee) / (mintedStables * BASE_9);
                } else expect = (subCollateralBalance * amountBurnt * fee) / (mintedStables * collatRatio);
                assertEq(amounts[count2++], expect);
            }
        }
        if (collatRatio < BASE_9) assertLe(amountInValueReceived, (collatRatio * amountBurnt) / BASE_9);
        if (!collatRatioAboveLimit) assertLe(amountInValueReceived, amountBurnt);
        if (amountInValueReceived >= _minWallet) {
            // TODO make the ones below pass: it is not bulletproof yet, works in many cases but not all.
            // We accept that small amount tx get out with uncapped loss (compare to what they should get with
            // infinite precision), but larger one should have a loss smaller than 0.1%
            if (collatRatio < BASE_9) {
                //     assertApproxEqRelDecimal(
                //         amountInValueReceived,
                //         (collatRatio * amountBurnt * fee) / BASE_18,
                //         _percentageLossAccepted,
                //         18
                //     );
            } else {
                //     assertApproxEqRelDecimal(
                //         amountInValueReceived,
                //         (amountBurnt * fee) / BASE_9,
                //         _percentageLossAccepted,
                //         18
                //     );
            }
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         UTILS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _loadReserves(
        uint256[3] memory initialAmounts,
        uint256 transferProportion
    ) internal returns (uint256 mintedStables, uint256[] memory collateralMintedStables) {
        collateralMintedStables = new uint256[](_collaterals.length);

        vm.startPrank(alice);
        for (uint256 i; i < _collaterals.length; ++i) {
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
        agToken.transfer(bob, (mintedStables * transferProportion) / BASE_9);
        vm.stopPrank();
    }

    function _loadSubCollaterals(
        address collateral,
        uint256[3 * _MAX_SUB_COLLATERALS] memory airdropAmounts,
        uint256 startIndex
    ) internal {
        IERC20[] memory listSubCollaterals = _subCollaterals[collateral].subCollaterals;
        // skip the first index because it is the collateral itself
        for (uint256 i = 1; i < listSubCollaterals.length; ++i) {
            airdropAmounts[startIndex + i - 1] = bound(
                airdropAmounts[startIndex + i - 1],
                0,
                _maxAmountWithoutDecimals * 10 ** IERC20Metadata(address(listSubCollaterals[i])).decimals()
            );
            deal(address(listSubCollaterals[i]), address(_managers[collateral]), airdropAmounts[startIndex + i - 1]);
        }
    }

    function _updateOracles(
        uint256[3] memory latestOracleValue,
        uint256 mintedStables,
        uint256[] memory collateralMintedStables
    ) internal returns (uint64 collatRatio) {
        for (uint256 i; i < latestOracleValue.length; ++i) {
            latestOracleValue[i] = bound(latestOracleValue[i], _minOracleValue, BASE_18);
            MockChainlinkOracle(address(_oracles[i])).setLatestAnswer(int256(latestOracleValue[i]));
        }

        uint256 collateralisation;
        for (uint256 i; i < latestOracleValue.length; ++i) {
            collateralisation += (latestOracleValue[i] * collateralMintedStables[i]) / BASE_8;
        }
        uint256 computedCollatRatio;
        if (mintedStables > 0) computedCollatRatio = uint64((collateralisation * BASE_9) / mintedStables);
        else computedCollatRatio = type(uint64).max;

        // check collateral ratio first
        uint256 reservesValue;
        (collatRatio, reservesValue) = kheops.getCollateralRatio();
        if (mintedStables > 0) assertApproxEqAbs(collatRatio, computedCollatRatio, 1 wei);
        else assertEq(collatRatio, type(uint64).max);
        assertEq(reservesValue, mintedStables);
    }

    function _updateOraclesWithSubCollaterals(
        uint256[3] memory latestOracleValue,
        uint256 mintedStables,
        uint256[] memory collateralMintedStables,
        uint256[3 * _MAX_SUB_COLLATERALS] memory airdropAmounts
    ) internal returns (uint64 collatRatio, bool collatRatioAboveLimit) {
        for (uint256 i; i < latestOracleValue.length; ++i) {
            latestOracleValue[i] = bound(latestOracleValue[i], _minOracleValue, BASE_18);
            MockChainlinkOracle(address(_oracles[i])).setLatestAnswer(int256(latestOracleValue[i]));
        }

        uint256 collateralisation;
        for (uint256 i; i < latestOracleValue.length; ++i) {
            collateralisation += (latestOracleValue[i] * collateralMintedStables[i]) / BASE_8;
        }

        for (uint256 i; i < latestOracleValue.length; ++i) {
            IERC20[] memory listSubCollaterals = _subCollaterals[_collaterals[i]].subCollaterals;
            AggregatorV3Interface[] memory listOracles = _subCollaterals[_collaterals[i]].oracles;
            // we don't double count the real collaterals
            for (uint256 k = 1; k < listSubCollaterals.length; k++) {
                (, int256 oracleValue, , , ) = MockChainlinkOracle(address(listOracles[k - 1])).latestRoundData();
                uint8 decimals = IERC20Metadata(address(listSubCollaterals[k])).decimals();
                collateralisation += ((airdropAmounts[i * _MAX_SUB_COLLATERALS + k - 1] *
                    10 ** (18 - decimals) *
                    uint256(oracleValue)) / BASE_8);
            }
        }

        uint256 computedCollatRatio = type(uint64).max;
        if (mintedStables > 0) {
            computedCollatRatio = uint64((collateralisation * BASE_9) / mintedStables);
            if ((collateralisation * BASE_9) / mintedStables > type(uint64).max) collatRatioAboveLimit = true;
        }

        // check collateral ratio first
        uint256 reservesValue;
        (collatRatio, reservesValue) = kheops.getCollateralRatio();

        if (mintedStables > 0) assertApproxEqAbs(collatRatio, computedCollatRatio, 1 wei);
        else assertEq(collatRatio, type(uint64).max);
        assertEq(reservesValue, mintedStables);
    }

    function _randomRedeemptionFees(
        uint64[10] memory xFeeRedeemUnbounded,
        int64[10] memory yFeeRedeemUnbounded
    ) internal returns (uint64[] memory xFeeRedeem, int64[] memory yFeeRedeem) {
        (xFeeRedeem, yFeeRedeem) = _generateCurves(xFeeRedeemUnbounded, yFeeRedeemUnbounded, true, false, 0);
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

    function _sweepBalancesWithManager(address owner, address[] memory tokens) internal {
        vm.startPrank(owner);
        for (uint256 i; i < tokens.length; ++i) {
            IERC20[] memory listSubCollaterals = _subCollaterals[_collaterals[i]].subCollaterals;
            IERC20(tokens[i]).transfer(sweeper, IERC20(tokens[i]).balanceOf(owner));
            // we don't double count the real collateral
            for (uint256 k = 1; k < listSubCollaterals.length; k++) {
                listSubCollaterals[k].transfer(sweeper, listSubCollaterals[k].balanceOf(owner));
            }
        }
        vm.stopPrank();
    }

    function _getForfeitTokens(
        bool[3 * (_MAX_SUB_COLLATERALS + 1)] memory areForfeited
    ) internal view returns (address[] memory forfeitTokens) {
        uint256 nbrForfeit;
        for (uint256 i; i < areForfeited.length; ++i) {
            if (areForfeited[i]) nbrForfeit++;
        }
        forfeitTokens = new address[](nbrForfeit);
        uint256 index;
        for (uint256 i; i < _collaterals.length; ++i) {
            IERC20[] memory listSubCollaterals = _subCollaterals[_collaterals[i]].subCollaterals;
            for (uint256 k = 0; k < listSubCollaterals.length; k++) {
                if (areForfeited[i * (_MAX_SUB_COLLATERALS + 1) + k])
                    forfeitTokens[index++] = address(listSubCollaterals[k]);
            }
        }
    }

    function _inList(address[] memory list, address element) internal pure returns (bool) {
        for (uint256 i; i < list.length; ++i) {
            if (list[i] == element) return true;
        }
        return false;
    }

    function _createManager(
        address token,
        uint256 nbrSubCollaterals,
        bool isManaged,
        uint256 startIndex,
        uint256[3 * _MAX_SUB_COLLATERALS] memory subCollateralOracleValue,
        uint256[3 * _MAX_SUB_COLLATERALS] memory subCollateralsDecimals
    ) internal returns (IERC20[] memory subCollaterals, AggregatorV3Interface[] memory oracles) {
        nbrSubCollaterals = bound(nbrSubCollaterals, 0, _MAX_SUB_COLLATERALS);
        subCollaterals = new IERC20[](nbrSubCollaterals + 1);

        oracles = new AggregatorV3Interface[](nbrSubCollaterals);
        subCollaterals[0] = IERC20(token);
        if (nbrSubCollaterals == 0 && isManaged) return (subCollaterals, oracles);
        MockManager manager = new MockManager(token);
        {
            uint8[] memory decimals = new uint8[](nbrSubCollaterals + 1);
            decimals[0] = IERC20Metadata(token).decimals();
            uint32[] memory stalePeriods = new uint32[](nbrSubCollaterals);
            uint8[] memory oracleIsMultiplied = new uint8[](nbrSubCollaterals);
            uint8[] memory chainlinkDecimals = new uint8[](nbrSubCollaterals);
            for (uint256 i = 1; i < nbrSubCollaterals + 1; ++i) {
                decimals[i] = uint8(bound(subCollateralsDecimals[startIndex + i - 1], 5, 18));
                subCollaterals[i] = IERC20(
                    address(
                        new MockTokenPermit(
                            string.concat(IERC20Metadata(token).name(), "_", Strings.toString(i)),
                            string.concat(IERC20Metadata(token).symbol(), "_", Strings.toString(i)),
                            decimals[i]
                        )
                    )
                );
                oracles[i - 1] = AggregatorV3Interface(address(new MockChainlinkOracle()));
                subCollateralOracleValue[startIndex + i - 1] = bound(
                    subCollateralOracleValue[startIndex + i - 1],
                    _minOracleValue,
                    BASE_18
                );
                MockChainlinkOracle(address(oracles[i - 1])).setLatestAnswer(
                    int256(subCollateralOracleValue[startIndex + i - 1])
                );
                stalePeriods[i - 1] = 365 days;
                oracleIsMultiplied[i - 1] = 1;
                chainlinkDecimals[i - 1] = 8;
            }

            manager.setSubCollaterals(
                subCollaterals,
                abi.encode(decimals, oracles, stalePeriods, oracleIsMultiplied, chainlinkDecimals)
            );
        }
        ManagerStorage memory managerData = ManagerStorage(
            subCollaterals,
            abi.encode(ManagerType.EXTERNAL, abi.encode(IManager(address(manager))))
        );
        _managers[token] = manager;

        vm.prank(governor);
        kheops.setCollateralManager(token, managerData);
    }
}
