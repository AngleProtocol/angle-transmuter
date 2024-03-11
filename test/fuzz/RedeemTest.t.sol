// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "oz/token/ERC20/utils/SafeERC20.sol";
import { Math } from "oz/utils/math/Math.sol";
import "oz/utils/Strings.sol";

import { stdError } from "forge-std/Test.sol";

import { MockManager } from "mock/MockManager.sol";
import { IERC20Metadata } from "mock/MockTokenPermit.sol";

import { ManagerStorage, WhitelistType } from "contracts/transmuter/Storage.sol";
import "contracts/transmuter/libraries/LibHelpers.sol";
import "contracts/utils/Errors.sol" as Errors;

import "../Fixture.sol";
import "../utils/FunctionUtils.sol";

struct SubCollateralStorage {
    // The collateral corresponding to the manager must also be in the list
    IERC20[] subCollaterals;
    AggregatorV3Interface[] oracles;
}

struct AssertQuoteParams {
    uint256 amountInValueReceived;
    bool lastCheck;
    uint256 count;
    uint256 maxValue;
    uint256 minValue;
    uint256 maxOracle;
    uint256 minOracle;
}

contract RedeemTest is Fixture, FunctionUtils {
    using Math for uint256;
    using SafeERC20 for IERC20;

    uint256 internal _maxAmountWithoutDecimals = 10 ** 15;
    // making this value smaller worsen rounding and make test harder to pass.
    // Trade off between bullet proof against all oracles and all interactions
    uint256 internal _minOracleValue = 10 ** 3; // 10**(-6)
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
        transmuter.setFees(address(eurA), xFeeMint, yFee, true);
        transmuter.setFees(address(eurA), xFeeBurn, yFee, false);
        transmuter.setFees(address(eurB), xFeeMint, yFee, true);
        transmuter.setFees(address(eurB), xFeeBurn, yFee, false);
        transmuter.setFees(address(eurY), xFeeMint, yFee, true);
        transmuter.setFees(address(eurY), xFeeBurn, yFee, false);
        transmuter.setRedemptionCurveParams(xFeeMint, yFeeRedemption);
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

    function testFuzz_QuoteRedeemAllAtPeg(uint256[3] memory initialAmounts, uint256 transferProportion) public {
        // let's first load the reserves of the protocol
        (uint256 mintedStables, ) = _loadReserves(initialAmounts, transferProportion);

        // check collateral ratio first
        (uint64 collatRatio, uint256 stablecoinsIssued) = transmuter.getCollateralRatio();
        if (mintedStables > 0) assertEq(collatRatio, BASE_9);
        else assertEq(collatRatio, type(uint64).max);
        assertEq(stablecoinsIssued, mintedStables);

        // currently oracles are all set to 1 --> collateral ratio = 1
        // --> redemption should be exactly in proportion of current balances
        vm.startPrank(alice);
        uint256 amountBurnt = agToken.balanceOf(alice);
        if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
        (address[] memory tokens, uint256[] memory amounts) = transmuter.quoteRedemptionCurve(amountBurnt);
        vm.stopPrank();

        if (mintedStables == 0) return;

        _assertSizes(tokens, amounts);
        _assertQuoteAmounts(uint64(BASE_9), mintedStables, amountBurnt, uint64(BASE_9), amounts);
    }

    function testFuzz_QuoteRedeemGlobalAtPeg(
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
            (uint64 collatRatio, uint256 stablecoinsIssued) = transmuter.getCollateralRatio();
            if (mintedStables > 0) assertApproxEqAbs(collatRatio, BASE_9, 1e5);
            else assertEq(collatRatio, type(uint64).max);
            assertEq(stablecoinsIssued, mintedStables);

            // currently oracles are all set to 1 --> collateral ratio = 1
            // --> redemption should be exactly in proportion of current balances
            vm.startPrank(alice);
            uint256 amountBurnt = agToken.balanceOf(alice);
            if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
            (address[] memory tokens, uint256[] memory amounts) = transmuter.quoteRedemptionCurve(amountBurnt);
            vm.stopPrank();

            if (mintedStables == 0) return;

            _assertSizes(tokens, amounts);
            _assertQuoteAmounts(collatRatio, mintedStables, amountBurnt, uint64(BASE_9), amounts);
        }
    }

    function testFuzz_QuoteRedeemRandomOracles(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256[3] memory latestOracleValue
    ) public {
        // let's first load the reserves of the protocol
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
            initialAmounts,
            transferProportion
        );
        uint64 collatRatio;
        {
            bool reverted;
            (collatRatio, reverted) = _updateOracles(latestOracleValue, mintedStables, collateralMintedStables);
            if (reverted) return;
        }

        vm.startPrank(alice);
        uint256 amountBurnt = agToken.balanceOf(alice);
        if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
        (address[] memory tokens, uint256[] memory amounts) = transmuter.quoteRedemptionCurve(amountBurnt);
        vm.stopPrank();

        if (mintedStables == 0) return;

        _assertSizes(tokens, amounts);
        _assertQuoteAmounts(collatRatio, mintedStables, amountBurnt, uint64(BASE_9), amounts);
    }

    function testFuzz_QuoteRedeemAtPegRandomFees(
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
        (address[] memory tokens, uint256[] memory amounts) = transmuter.quoteRedemptionCurve(amountBurnt);
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

    function testFuzz_QuoteRedeemRandomFees(
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
        uint64 collatRatio;
        {
            bool reverted;
            (collatRatio, reverted) = _updateOracles(latestOracleValue, mintedStables, collateralMintedStables);
            if (reverted) return;
        }
        (uint64[] memory xFeeRedeem, int64[] memory yFeeRedeem) = _randomRedeemptionFees(
            xFeeRedeemUnbounded,
            yFeeRedeemUnbounded
        );

        vm.startPrank(alice);
        uint256 amountBurnt = agToken.balanceOf(alice);
        if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
        (address[] memory tokens, uint256[] memory amounts) = transmuter.quoteRedemptionCurve(amountBurnt);
        vm.stopPrank();

        if (mintedStables == 0) return;

        // compute fee at current collatRatio
        _assertSizes(tokens, amounts);
        uint64 fee;
        if (collatRatio >= BASE_9) fee = uint64(yFeeRedeem[yFeeRedeem.length - 1]);
        else fee = uint64(LibHelpers.piecewiseLinear(collatRatio, xFeeRedeem, yFeeRedeem));
        _assertQuoteAmounts(collatRatio, mintedStables, amountBurnt, fee, amounts);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        REDEEM                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_RedeemAllAtPeg(uint256[3] memory initialAmounts, uint256 transferProportion) public {
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
        (, uint256[] memory quoteAmounts) = transmuter.quoteRedemptionCurve(amountBurnt);
        if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
        // uint256[] memory forfeitTokens = new uint256[](0);
        uint256[] memory minAmountOuts = new uint256[](_collaterals.length);
        (address[] memory tokens, uint256[] memory amounts) = transmuter.redeem(
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

        // Testing implicitly the ts.normalizer and ts.normalizedStables
        for (uint256 i; i < _collaterals.length; ++i) {
            (uint256 stableIssuedByCollateral, uint256 totalStable) = transmuter.getIssuedByCollateral(_collaterals[i]);
            assertApproxEqAbs(
                stableIssuedByCollateral,
                (collateralMintedStables[i] * (mintedStables - amountBurnt)) / mintedStables,
                1 wei
            );
            assertApproxEqAbs(totalStable, mintedStables - amountBurnt, 3 wei);
        }
    }

    function testFuzz_RedeemRandomFees(
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
        uint64 collatRatio;
        {
            bool reverted;
            (collatRatio, reverted) = _updateOracles(latestOracleValue, mintedStables, collateralMintedStables);
            if (reverted) return;
        }

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
        (, uint256[] memory quoteAmounts) = transmuter.quoteRedemptionCurve(amountBurnt);
        if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
        address[] memory tokens;
        uint256[] memory amounts;
        {
            // uint256[] memory forfeitTokens = new uint256[](0);
            uint256[] memory minAmountOuts = new uint256[](_collaterals.length);
            (tokens, amounts) = transmuter.redeem(amountBurnt, alice, block.timestamp + 1 days, minAmountOuts);
        }
        vm.stopPrank();

        if (mintedStables == 0) return;

        // compute fee at current collatRatio
        assertEq(amounts, quoteAmounts);
        _assertSizes(tokens, amounts);
        _assertTransfers(alice, _collaterals, amounts);

        // Testing implicitly the ts.normalizer and ts.normalizedStables
        for (uint256 i; i < _collaterals.length; ++i) {
            (uint256 stableIssuedByCollateral, uint256 totalStable) = transmuter.getIssuedByCollateral(_collaterals[i]);
            assertApproxEqAbs(
                stableIssuedByCollateral,
                (collateralMintedStables[i] * (mintedStables - amountBurnt)) / mintedStables,
                1 wei
            );
            assertApproxEqAbs(totalStable, mintedStables - amountBurnt, 3 wei);
        }
    }

    function testFuzz_MultiRedemptionCurveRandomRedemptionFees(
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
        {
            (, bool reverted) = _updateOracles(latestOracleValue, mintedStables, collateralMintedStables);
            if (reverted) return;
        }
        _randomRedeemptionFees(xFeeRedeemUnbounded, yFeeRedeemUnbounded);
        _sweepBalances(alice, _collaterals);
        _sweepBalances(bob, _collaterals);

        // first redeem
        vm.startPrank(alice);
        uint256 amountBurnt = agToken.balanceOf(alice);
        uint256 amountBurntBob;
        uint256[] memory quoteAmounts;
        {
            bool shouldReturn;
            {
                uint256 totalCollateralization = _computeCollateralisation();
                if (
                    mintedStables > 0 &&
                    (totalCollateralization.mulDiv(BASE_9, mintedStables, Math.Rounding.Up)) > type(uint64).max
                ) {
                    vm.expectRevert(bytes("SafeCast: value doesn't fit in 64 bits"));
                    shouldReturn = true;
                } else if (amountBurnt > mintedStables) {
                    vm.expectRevert(Errors.TooBigAmountIn.selector);
                } else if (mintedStables == 0) {
                    vm.expectRevert(stdError.divisionError);
                }
            }
            (, quoteAmounts) = transmuter.quoteRedemptionCurve(amountBurnt);
            if (shouldReturn) return;
        }
        if (amountBurnt > mintedStables) vm.expectRevert(Errors.TooBigAmountIn.selector);
        else if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
        {
            address[] memory tokens;
            uint256[] memory amounts;
            {
                uint256[] memory minAmountOuts = new uint256[](_collaterals.length);
                (tokens, amounts) = transmuter.redeem(amountBurnt, alice, block.timestamp + 1 days, minAmountOuts);
            }
            vm.stopPrank();

            if (mintedStables == 0 || amountBurnt > mintedStables) return;

            // compute fee at current collatRatio
            assertEq(amounts, quoteAmounts);
            _assertSizes(tokens, amounts);
            _assertTransfers(alice, _collaterals, amounts);

            // Testing implicitly the ts.normalizer and ts.normalizedStables
            for (uint256 i; i < _collaterals.length; ++i) {
                (uint256 stableIssuedByCollateral, uint256 totalStable) = transmuter.getIssuedByCollateral(
                    _collaterals[i]
                );
                assertApproxEqAbs(
                    stableIssuedByCollateral,
                    (collateralMintedStables[i] * (mintedStables - amountBurnt)) / mintedStables,
                    1 wei
                );
                assertApproxEqAbs(totalStable, mintedStables - amountBurnt, 3 wei);
            }

            // Compute mintedStables while rounding up
            uint128 normalizedStables = uint128(
                uint256(vm.load(address(transmuter), bytes32(uint256(TRANSMUTER_STORAGE_POSITION) + 1)))
            );
            uint128 normalizer = uint128(
                uint256(vm.load(address(transmuter), bytes32(uint256(TRANSMUTER_STORAGE_POSITION) + 1)) >> 128)
            );
            mintedStables = uint256(normalizedStables).mulDiv(normalizer, BASE_27, Math.Rounding.Up);

            // now do a second redeem to test with non trivial ts.normalizer and ts.normalizedStables
            vm.startPrank(bob);
            redeemProportion = bound(redeemProportion, 0, BASE_9);
            amountBurntBob = (agToken.balanceOf(bob) * redeemProportion) / BASE_9;
            {
                bool shouldReturn;
                {
                    uint256 totalCollateralization = _computeCollateralisation();
                    if (
                        mintedStables > 0 &&
                        (totalCollateralization.mulDiv(BASE_9, mintedStables, Math.Rounding.Up)) > type(uint64).max
                    ) {
                        vm.expectRevert(bytes("SafeCast: value doesn't fit in 64 bits"));
                        shouldReturn = true;
                    } else if (amountBurntBob > mintedStables) {
                        vm.expectRevert(Errors.TooBigAmountIn.selector);
                    } else if (mintedStables == 0) {
                        vm.expectRevert(stdError.divisionError);
                    }
                }
                (, quoteAmounts) = transmuter.quoteRedemptionCurve(amountBurntBob);
                if (shouldReturn) return;
            }

            if (amountBurntBob > mintedStables) vm.expectRevert(Errors.TooBigAmountIn.selector);
            else if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
            {
                uint256[] memory minAmountOuts = new uint256[](_collaterals.length);
                (tokens, amounts) = transmuter.redeem(amountBurntBob, bob, block.timestamp + 1 days, minAmountOuts);
            }
            vm.stopPrank();

            if (mintedStables == 0 || amountBurntBob > mintedStables) return;

            // compute fee at current collatRatio
            assertEq(amounts, quoteAmounts);
            _assertSizes(tokens, amounts);
            _assertTransfers(bob, _collaterals, amounts);
        }

        // Testing implicitly the ts.normalizer and ts.normalizedStables
        uint256 totalStable2;
        for (uint256 i; i < _collaterals.length; ++i) {
            uint256 stableIssuedByCollateral;
            (stableIssuedByCollateral, totalStable2) = transmuter.getIssuedByCollateral(_collaterals[i]);
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
            _MAX_PERCENTAGE_DEVIATION * 10,
            18
        );
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                  REDEEM WITH MANAGER                                               
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_QuoteRedemptionCurveWithManagerRandomRedemptionFees(
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
            if (subCollaterals.length > 0) {
                _subCollaterals[_collaterals[i]] = SubCollateralStorage(subCollaterals, oracles);
            }
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
        uint64 collatRatio;
        {
            bool reverted;
            (collatRatio, reverted) = _updateOraclesWithSubCollaterals(
                latestOracleValue,
                mintedStables,
                collateralMintedStables,
                airdropAmounts
            );
            if (reverted) return;
        }

        (uint64[] memory xFeeRedeem, int64[] memory yFeeRedeem) = _randomRedeemptionFees(
            xFeeRedeemUnbounded,
            yFeeRedeemUnbounded
        );

        vm.startPrank(alice);
        uint256 amountBurnt = agToken.balanceOf(alice);
        address[] memory tokens;
        uint256[] memory amounts;
        {
            bool shouldReturn;
            {
                uint256 totalCollateralization = _computeCollateralisation();
                if (
                    mintedStables > 0 &&
                    (totalCollateralization.mulDiv(BASE_9, mintedStables, Math.Rounding.Up)) > type(uint64).max
                ) {
                    vm.expectRevert(bytes("SafeCast: value doesn't fit in 64 bits"));
                    shouldReturn = true;
                } else if (mintedStables == 0) {
                    vm.expectRevert(stdError.divisionError);
                }
            }
            (tokens, amounts) = transmuter.quoteRedemptionCurve(amountBurnt);
            if (shouldReturn) return;
        }
        vm.stopPrank();

        if (mintedStables == 0) return;

        // compute fee at current collatRatio
        _assertSizesWithManager(tokens, amounts);
        uint64 fee;
        if (collatRatio >= BASE_9) fee = uint64(yFeeRedeem[yFeeRedeem.length - 1]);
        else fee = uint64(LibHelpers.piecewiseLinear(collatRatio, xFeeRedeem, yFeeRedeem));
        _assertQuoteAmountsWithManager(amountBurnt, fee, amounts);
    }

    function testFuzz_MultiRedemptionCurveWithManagerRandomRedemptionFees(
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
        uint256[] memory quoteAmounts;
        {
            bool shouldReturn;
            {
                uint256 totalCollateralization = _computeCollateralisation();
                if (
                    mintedStables > 0 &&
                    (totalCollateralization.mulDiv(BASE_9, mintedStables, Math.Rounding.Up)) > type(uint64).max
                ) {
                    vm.expectRevert(bytes("SafeCast: value doesn't fit in 64 bits"));
                    shouldReturn = true;
                } else if (mintedStables == 0) {
                    vm.expectRevert(stdError.divisionError);
                }
            }
            (, quoteAmounts) = transmuter.quoteRedemptionCurve(amountBurnt);
            if (shouldReturn) return;
        }
        if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
        {
            address[] memory tokens;
            uint256[] memory amounts;
            {
                uint256[] memory minAmountOuts = new uint256[](quoteAmounts.length);
                (tokens, amounts) = transmuter.redeem(amountBurnt, alice, block.timestamp + 1 days, minAmountOuts);
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
            // Testing implicitly the ts.normalizer and ts.normalizedStables
            for (uint256 i; i < _collaterals.length; ++i) {
                (uint256 stableIssuedByCollateral, uint256 totalStable) = transmuter.getIssuedByCollateral(
                    _collaterals[i]
                );
                assertApproxEqAbs(
                    stableIssuedByCollateral,
                    (collateralMintedStables[i] * (mintedStables - amountBurnt)) / mintedStables,
                    1 wei
                );
                assertApproxEqAbs(totalStable, mintedStables - amountBurnt, 3 wei);
            }
            mintedStables = transmuter.getTotalIssued();

            // now do a second redeem to test with non trivial ts.normalizer and ts.normalizedStables
            vm.startPrank(bob);
            redeemProportion = bound(redeemProportion, 0, BASE_9);
            amountBurntBob = (agToken.balanceOf(bob) * redeemProportion) / BASE_9;
            {
                bool shouldReturn;
                {
                    uint256 totalCollateralization = _computeCollateralisation();
                    if (
                        mintedStables > 0 &&
                        (totalCollateralization.mulDiv(BASE_9, mintedStables, Math.Rounding.Up)) > type(uint64).max
                    ) {
                        vm.expectRevert(bytes("SafeCast: value doesn't fit in 64 bits"));
                        shouldReturn = true;
                    } else if (amountBurntBob > mintedStables) {
                        vm.expectRevert(Errors.TooBigAmountIn.selector);
                    } else if (mintedStables == 0) {
                        vm.expectRevert(stdError.divisionError);
                    }
                }
                (, quoteAmounts) = transmuter.quoteRedemptionCurve(amountBurntBob);
                if (shouldReturn) return;
            }
            if (amountBurntBob > mintedStables) vm.expectRevert(Errors.TooBigAmountIn.selector);
            else if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
            {
                uint256[] memory minAmountOuts = new uint256[](quoteAmounts.length);
                (tokens, amounts) = transmuter.redeem(amountBurntBob, bob, block.timestamp + 1 days, minAmountOuts);
            }
            vm.stopPrank();

            if (mintedStables == 0 || amountBurntBob > mintedStables) return;

            // compute fee at current collatRatio
            assertEq(amounts, quoteAmounts);
            _assertSizesWithManager(tokens, amounts);
            {
                address[] memory forfeitTokens;
                _assertTransfersWithManager(bob, _collaterals, forfeitTokens, amounts);
            }
        }

        // Testing implicitly the ts.normalizer and ts.normalizedStables
        uint256 totalStable2;
        for (uint256 i; i < _collaterals.length; ++i) {
            uint256 stableIssuedByCollateral;
            (stableIssuedByCollateral, totalStable2) = transmuter.getIssuedByCollateral(_collaterals[i]);
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

    function test_RevertWhen_RedeemInvalidArrayLengths(
        uint256[3] memory initialAmounts,
        uint256 transferProportion
    ) public {
        // let's first load the reserves of the protocol
        (uint256 mintedStables, ) = _loadReserves(initialAmounts, transferProportion);

        // check collateral ratio first
        if (mintedStables == 0) return;
        vm.startPrank(alice);
        uint256 amountBurnt = agToken.balanceOf(alice);
        {
            uint256[] memory minAmountOuts;
            {
                (, uint256[] memory quoteAmounts) = transmuter.quoteRedemptionCurve(amountBurnt);
                minAmountOuts = new uint256[](quoteAmounts.length - 1);
            }
            vm.expectRevert(Errors.InvalidLengths.selector);
            transmuter.redeem(amountBurnt, alice, block.timestamp * 2, minAmountOuts);
        }
        {
            uint256[] memory minAmountOuts;
            {
                (, uint256[] memory quoteAmounts) = transmuter.quoteRedemptionCurve(amountBurnt);
                minAmountOuts = new uint256[](quoteAmounts.length + 1);
            }
            vm.expectRevert(Errors.InvalidLengths.selector);
            transmuter.redeem(amountBurnt, alice, block.timestamp * 2, minAmountOuts);
        }
        vm.stopPrank();
    }

    function testFuzz_MultiForfeitRedemptionCurveWithManagerRandomRedemptionFees(
        uint256[6] memory initialValue, // initialAmounts of size 3 / nbrSubCollaterals of size 3
        bool[3] memory isManaged,
        uint256[3 * _MAX_SUB_COLLATERALS] memory airdropAmounts,
        uint256[3 * _MAX_SUB_COLLATERALS] memory latestSubCollatOracleValue,
        uint256[3 * _MAX_SUB_COLLATERALS] memory subCollatDecimals,
        bool[3 * (_MAX_SUB_COLLATERALS + 1)] memory areForfeit,
        uint256 transferProportion,
        uint256 redeemProportion,
        uint256[3] memory latestOracleValue,
        uint64[10] memory xFeeRedeemUnbounded, // X and Y arrays of length 10 each
        int64[10] memory yFeeRedeemUnbounded // X and Y arrays of length 10 each
    ) public {
        for (uint256 i; i < _collaterals.length; ++i) {
            // Randomly set subcollaterals and manager if needed
            (IERC20[] memory subCollaterals, AggregatorV3Interface[] memory oracles) = _createManager(
                _collaterals[i],
                initialValue[3 + i],
                isManaged[i],
                i * _MAX_SUB_COLLATERALS,
                latestSubCollatOracleValue,
                subCollatDecimals
            );
            _subCollaterals[_collaterals[i]] = SubCollateralStorage(subCollaterals, oracles);
        }

        // let's first load the reserves of the protocol
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
            [initialValue[0], initialValue[1], initialValue[2]],
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
        uint256[] memory quoteAmounts;
        {
            bool shouldReturn;
            {
                uint256 totalCollateralization = _computeCollateralisation();
                if (
                    mintedStables > 0 &&
                    (totalCollateralization.mulDiv(BASE_9, mintedStables, Math.Rounding.Up)) > type(uint64).max
                ) {
                    vm.expectRevert(bytes("SafeCast: value doesn't fit in 64 bits"));
                    shouldReturn = true;
                } else if (mintedStables == 0) {
                    vm.expectRevert(stdError.divisionError);
                }
            }
            (, quoteAmounts) = transmuter.quoteRedemptionCurve(amountBurnt);
            if (shouldReturn) return;
        }
        {
            address[] memory tokens;
            uint256[] memory amounts;
            address[] memory forfeitTokens = _getForfeitTokens(areForfeit);
            {
                uint256[] memory minAmountOuts = new uint256[](quoteAmounts.length);
                if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
                (tokens, amounts) = transmuter.redeemWithForfeit(
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

            // Testing implicitly the ts.normalizer and ts.normalizedStables
            for (uint256 i; i < _collaterals.length; ++i) {
                (uint256 stableIssuedByCollateral, uint256 totalStable) = transmuter.getIssuedByCollateral(
                    _collaterals[i]
                );
                assertApproxEqAbs(
                    stableIssuedByCollateral,
                    (collateralMintedStables[i] * (mintedStables - amountBurnt)) / mintedStables,
                    1 wei
                );
                assertApproxEqAbs(totalStable, mintedStables - amountBurnt, 3 wei);
            }
            mintedStables = transmuter.getTotalIssued();

            // now do a second redeem to test with non trivial ts.normalizer and ts.normalizedStables
            vm.startPrank(bob);
            redeemProportion = bound(redeemProportion, 0, BASE_9);
            amountBurntBob = (agToken.balanceOf(bob) * redeemProportion) / BASE_9;
            {
                bool shouldReturn;
                uint256 totalCollateralization = _computeCollateralisation();
                if (
                    mintedStables > 0 &&
                    (totalCollateralization.mulDiv(BASE_9, mintedStables, Math.Rounding.Up)) > type(uint64).max
                ) {
                    vm.expectRevert(bytes("SafeCast: value doesn't fit in 64 bits"));
                    shouldReturn = true;
                } else if (amountBurntBob > mintedStables) {
                    vm.expectRevert(Errors.TooBigAmountIn.selector);
                } else if (mintedStables == 0) {
                    vm.expectRevert(stdError.divisionError);
                }
                (, quoteAmounts) = transmuter.quoteRedemptionCurve(amountBurntBob);
                if (shouldReturn) return;
            }

            if (amountBurntBob > mintedStables) vm.expectRevert(Errors.TooBigAmountIn.selector);
            else if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
            {
                uint256[] memory minAmountOuts = new uint256[](quoteAmounts.length);
                (tokens, amounts) = transmuter.redeem(amountBurntBob, bob, block.timestamp + 1 days, minAmountOuts);
            }
            vm.stopPrank();

            if (mintedStables == 0 || amountBurntBob > mintedStables) return;

            // compute fee at current collatRatio
            assertEq(amounts, quoteAmounts);
            _assertSizesWithManager(tokens, amounts);
            {
                address[] memory forfeitTokens2;
                _assertTransfersWithManager(bob, _collaterals, forfeitTokens2, amounts);
            }
        }

        // Testing implicitly the ts.normalizer and ts.normalizedStables
        {
            uint256 totalStable2;
            for (uint256 i; i < _collaterals.length; ++i) {
                uint256 stableIssuedByCollateral;
                (stableIssuedByCollateral, totalStable2) = transmuter.getIssuedByCollateral(_collaterals[i]);
                uint256 realStableIssueByCollateralLeft = (collateralMintedStables[i] *
                    (mintedStables - amountBurntBob)) / (mintedStables + amountBurnt);

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
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                               REDEEM WITH WHITELISTING                                             
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_WithWhitelistedToken(uint256[3] memory initialAmounts, uint256 transferProportion) public {
        // let's first load the reserves of the protocol
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
            initialAmounts,
            transferProportion
        );

        _sweepBalances(alice, _collaterals);

        bytes memory emptyData;
        bytes memory whitelistData = abi.encode(WhitelistType.BACKED, emptyData);
        hoax(governor);
        transmuter.setWhitelistStatus(address(eurA), 1, whitelistData);

        vm.startPrank(alice);
        uint256 amountBurnt = agToken.balanceOf(alice);
        if (mintedStables == 0 || amountBurnt < BASE_18) return;
        (, uint256[] memory quoteAmounts) = transmuter.quoteRedemptionCurve(amountBurnt);
        // There should be a non zero amount of EURA to transfer
        if (quoteAmounts[0] == 0) return;
        vm.expectRevert(Errors.NotWhitelisted.selector);

        uint256[] memory minAmountOuts = new uint256[](_collaterals.length);
        transmuter.redeem(amountBurnt, alice, block.timestamp + 1 days, minAmountOuts);
        vm.stopPrank();

        hoax(guardian);
        transmuter.toggleWhitelist(WhitelistType.BACKED, alice);

        vm.startPrank(alice);
        vm.expectRevert(Errors.NotWhitelisted.selector);
        transmuter.redeem(amountBurnt, bob, block.timestamp + 1 days, minAmountOuts);

        (address[] memory tokens, uint256[] memory amounts) = transmuter.redeem(
            amountBurnt,
            alice,
            block.timestamp + 1 days,
            minAmountOuts
        );
        vm.stopPrank();

        assertEq(amounts, quoteAmounts);
        _assertSizes(tokens, amounts);
        _assertTransfers(alice, _collaterals, amounts);

        // Testing implicitly the ts.normalizer and ts.normalizedStables
        for (uint256 i; i < _collaterals.length; ++i) {
            (uint256 stableIssuedByCollateral, uint256 totalStable) = transmuter.getIssuedByCollateral(_collaterals[i]);
            assertApproxEqAbs(
                stableIssuedByCollateral,
                (collateralMintedStables[i] * (mintedStables - amountBurnt)) / mintedStables,
                1 wei
            );
            assertApproxEqAbs(totalStable, mintedStables - amountBurnt, 3 wei);
        }
    }

    function testFuzz_WithForfeitAndWhitelistedTokens(
        uint256[3] memory initialAmounts,
        uint256 transferProportion
    ) public {
        // let's first load the reserves of the protocol
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
            initialAmounts,
            transferProportion
        );

        _sweepBalances(alice, _collaterals);
        {
            bytes memory emptyData;
            bytes memory whitelistData = abi.encode(WhitelistType.BACKED, emptyData);
            hoax(governor);
            transmuter.setWhitelistStatus(address(eurA), 1, whitelistData);
            hoax(governor);
            transmuter.setWhitelistStatus(address(eurB), 1, whitelistData);
        }
        uint256 amountBurnt = agToken.balanceOf(alice);
        if (mintedStables == 0 || amountBurnt == 0) return;
        (, uint256[] memory quoteAmounts) = transmuter.quoteRedemptionCurve(amountBurnt);
        if (quoteAmounts[0] == 0 || quoteAmounts[1] == 0) return;
        uint256[] memory minAmountOuts = new uint256[](_collaterals.length);
        {
            vm.startPrank(alice);
            address[] memory forfeitTokens = new address[](0);
            vm.expectRevert(Errors.NotWhitelisted.selector);
            transmuter.redeemWithForfeit(amountBurnt, alice, block.timestamp + 1 days, minAmountOuts, forfeitTokens);

            address[] memory forfeitTokens1 = new address[](1);
            forfeitTokens1[0] = address(eurA);
            vm.expectRevert(Errors.NotWhitelisted.selector);
            transmuter.redeemWithForfeit(amountBurnt, alice, block.timestamp + 1 days, minAmountOuts, forfeitTokens);
            vm.stopPrank();
            hoax(guardian);
            transmuter.toggleWhitelist(WhitelistType.BACKED, alice);
            vm.startPrank(alice);
            vm.expectRevert(Errors.NotWhitelisted.selector);
            transmuter.redeemWithForfeit(amountBurnt, bob, block.timestamp + 1 days, minAmountOuts, forfeitTokens);
        }

        address[] memory forfeitTokens2 = new address[](2);
        forfeitTokens2[0] = address(eurA);
        forfeitTokens2[1] = address(eurB);
        (address[] memory tokens, uint256[] memory amounts) = transmuter.redeemWithForfeit(
            amountBurnt,
            bob,
            block.timestamp + 1 days,
            minAmountOuts,
            forfeitTokens2
        );
        vm.stopPrank();

        assertEq(amounts, quoteAmounts);
        _assertSizes(tokens, amounts);
        assertEq(IERC20(address(eurA)).balanceOf(bob), 0);
        assertEq(IERC20(address(eurB)).balanceOf(bob), 0);
        assertEq(IERC20(address(eurY)).balanceOf(bob), amounts[2]);

        for (uint256 i; i < _collaterals.length; ++i) {
            (uint256 stableIssuedByCollateral, uint256 totalStable) = transmuter.getIssuedByCollateral(_collaterals[i]);
            assertApproxEqAbs(
                stableIssuedByCollateral,
                (collateralMintedStables[i] * (mintedStables - amountBurnt)) / mintedStables,
                1 wei
            );
            assertApproxEqAbs(totalStable, mintedStables - amountBurnt, 3 wei);
        }
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
                if (!_inList(forfeitTokens, address(listSubCollaterals[k]))) {
                    assertEq(listSubCollaterals[k].balanceOf(owner), amounts[count]);
                } else {
                    assertEq(IERC20(listSubCollaterals[k]).balanceOf(owner), 0);
                }
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
        AssertQuoteParams memory quoteStorage;
        {
            for (uint256 i; i < _oracles.length; ++i) {
                (, int256 value, , , ) = _oracles[i].latestRoundData();
                uint8 decimals = IERC20Metadata(_collaterals[i]).decimals();
                if (uint256(value) > quoteStorage.maxOracle) quoteStorage.maxOracle = uint256(value);
                if (amounts[i] > quoteStorage.maxValue) quoteStorage.maxValue = amounts[i] / 10 ** decimals;
                if (amounts[i] < quoteStorage.minValue || quoteStorage.minValue == 0) {
                    quoteStorage.minValue = amounts[i] / 10 ** decimals;
                }
                if (quoteStorage.minOracle == 0 || uint256(value) < quoteStorage.minOracle) {
                    quoteStorage.minOracle = uint256(value);
                }
                if (uint256(value) > BASE_18 || amounts[i] < 10 ** 4) quoteStorage.lastCheck = true;
                quoteStorage.amountInValueReceived += (uint256(value) * _convertDecimalTo(amounts[i], decimals, 18));
            }
            // Otherwise there can be rounding errors that make the last check not precise at all
            if (
                quoteStorage.maxValue > quoteStorage.minValue * 10 ** 14 ||
                quoteStorage.maxOracle > quoteStorage.minOracle * 10 ** 14 ||
                quoteStorage.minOracle < 10 ** 5 ||
                quoteStorage.maxOracle > 10 ** 13
            ) quoteStorage.lastCheck = true;
        }
        quoteStorage.amountInValueReceived = quoteStorage.amountInValueReceived / BASE_8;

        uint256 denom = (mintedStables * BASE_9);
        uint256 valueCheck = (collatRatio * amountBurnt * fee) / BASE_18;
        if (collatRatio >= BASE_9) {
            denom = (mintedStables * collatRatio);
            // for rounding errors
            assertLe(quoteStorage.amountInValueReceived, amountBurnt + 1);
            valueCheck = (amountBurnt * fee) / BASE_9;
        }
        assertApproxEqAbs(amounts[0], (eurA.balanceOf(address(transmuter)) * amountBurnt * fee) / denom, 1 wei);
        assertApproxEqAbs(amounts[1], (eurB.balanceOf(address(transmuter)) * amountBurnt * fee) / denom, 1 wei);
        assertApproxEqAbs(amounts[2], (eurY.balanceOf(address(transmuter)) * amountBurnt * fee) / denom, 1 wei);
        if (collatRatio < BASE_9) {
            assertLe(quoteStorage.amountInValueReceived, (collatRatio * amountBurnt) / BASE_9 + 1);
        }

        if (quoteStorage.amountInValueReceived >= _minWallet && !quoteStorage.lastCheck) {
            assertApproxEqRelDecimal(quoteStorage.amountInValueReceived, valueCheck, _MAX_PERCENTAGE_DEVIATION, 18);
        }
    }

    function _assertQuoteAmountsWithManager(uint256 amountBurnt, uint64 fee, uint256[] memory amounts) internal {
        // we should also receive  in value `min(collatRatio*amountBurnt,amountBurnt)`
        AssertQuoteParams memory quoteStorage;
        {
            for (uint256 i; i < _collaterals.length; ++i) {
                (, int256 oracleValue, , , ) = _oracles[i].latestRoundData();
                {
                    uint8 decimals = IERC20Metadata(_collaterals[i]).decimals();
                    quoteStorage.amountInValueReceived +=
                        (uint256(oracleValue) * _convertDecimalTo(amounts[quoteStorage.count++], decimals, 18)) /
                        BASE_8;
                    if (uint256(oracleValue) > quoteStorage.maxOracle) quoteStorage.maxOracle = uint256(oracleValue);
                    if (amounts[i] > quoteStorage.maxValue) quoteStorage.maxValue = amounts[i] / 10 ** decimals;
                    if (amounts[i] < quoteStorage.minValue || quoteStorage.minValue == 0) {
                        quoteStorage.minValue = amounts[i] / 10 ** decimals;
                    }
                    if (quoteStorage.minOracle == 0 || uint256(oracleValue) < quoteStorage.minOracle) {
                        quoteStorage.minOracle = uint256(oracleValue);
                    }
                    if (uint256(oracleValue) > BASE_18 || amounts[i] < 10 ** 4) quoteStorage.lastCheck = true;
                }
                // we don't double count the real collateral
                uint256 subCollateralValue;
                for (uint256 k = 1; k < _subCollaterals[_collaterals[i]].subCollaterals.length; k++) {
                    (, int256 value, , , ) = _subCollaterals[_collaterals[i]].oracles[k - 1].latestRoundData();
                    uint8 decimals = IERC20Metadata(address(_subCollaterals[_collaterals[i]].subCollaterals[k]))
                        .decimals();
                    subCollateralValue +=
                        (uint256(value) *
                            _convertDecimalTo(
                                amounts[quoteStorage.count++],
                                decimals,
                                IERC20Metadata(_collaterals[i]).decimals()
                            )) /
                        BASE_8;
                    if (uint256(value) > quoteStorage.maxOracle) quoteStorage.maxOracle = uint256(value);
                    if (amounts[i] > quoteStorage.maxValue) quoteStorage.maxValue = amounts[i] / 10 ** decimals;
                    if (amounts[i] < quoteStorage.minValue || quoteStorage.minValue == 0) {
                        quoteStorage.minValue = amounts[i] / 10 ** decimals;
                    }
                    if (quoteStorage.minOracle == 0 || uint256(value) < quoteStorage.minOracle) {
                        quoteStorage.minOracle = uint256(value);
                    }
                    if (uint256(value) > BASE_18 || amounts[i] < 10 ** 4) quoteStorage.lastCheck = true;
                }
                quoteStorage.amountInValueReceived +=
                    (_convertDecimalTo(subCollateralValue, IERC20Metadata(_collaterals[i]).decimals(), 18) *
                        uint256(oracleValue)) /
                    BASE_8;
            }
            if (
                quoteStorage.maxValue > quoteStorage.minValue * 10 ** 14 ||
                quoteStorage.maxOracle > quoteStorage.minOracle * 10 ** 14 ||
                quoteStorage.minOracle < 10 ** 5 ||
                quoteStorage.maxOracle > 10 ** 13
            ) quoteStorage.lastCheck = true;
        }

        uint256 count2;
        bool reverted;
        {
            uint256 totalCollateralization = _computeCollateralisation();
            uint256 trueMintedStables = transmuter.getTotalIssued();
            if (
                trueMintedStables > 0 &&
                totalCollateralization.mulDiv(BASE_9, trueMintedStables, Math.Rounding.Up) > type(uint64).max
            ) {
                reverted = true;
                vm.expectRevert(bytes("SafeCast: value doesn't fit in 64 bits"));
            }
        }
        (uint256 collatRatio, uint256 mintedStables) = transmuter.getCollateralRatio();
        if (reverted) return;

        for (uint256 i; i < _oracles.length; ++i) {
            IERC20[] memory listSubCollaterals = _subCollaterals[_collaterals[i]].subCollaterals;
            for (uint256 k = 0; k < listSubCollaterals.length; ++k) {
                uint256 expect;
                uint256 subCollateralBalance;
                if (address(_managers[_collaterals[i]]) == address(0)) {
                    subCollateralBalance = listSubCollaterals[k].balanceOf(address(transmuter));
                } else {
                    subCollateralBalance = listSubCollaterals[k].balanceOf(address(_managers[_collaterals[i]]));
                }
                if (collatRatio < BASE_9) {
                    expect = (subCollateralBalance * amountBurnt * fee) / (mintedStables * BASE_9);
                } else {
                    expect = (subCollateralBalance * amountBurnt * fee) / (mintedStables * collatRatio);
                }
                assertEq(amounts[count2++], expect);
            }
        }
        uint256 valueCheck = (amountBurnt * fee) / BASE_9;
        if (collatRatio < BASE_9) {
            assertLe(quoteStorage.amountInValueReceived, (collatRatio * amountBurnt) / BASE_9);
            valueCheck = (collatRatio * amountBurnt * fee) / BASE_18;
        }
        if (quoteStorage.amountInValueReceived >= _minWallet && !quoteStorage.lastCheck) {
            assertApproxEqRelDecimal(quoteStorage.amountInValueReceived, valueCheck, _MAX_PERCENTAGE_DEVIATION, 18);
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
            initialAmounts[i] = bound(initialAmounts[i], 1e16, _maxTokenAmount[i]);
            deal(_collaterals[i], alice, initialAmounts[i]);
            IERC20(_collaterals[i]).approve(address(transmuter), initialAmounts[i]);

            collateralMintedStables[i] = transmuter.swapExactInput(
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
    ) internal returns (uint64 collatRatio, bool reverted) {
        for (uint256 i; i < latestOracleValue.length; ++i) {
            latestOracleValue[i] = bound(latestOracleValue[i], _minOracleValue, BASE_18);
            MockChainlinkOracle(address(_oracles[i])).setLatestAnswer(int256(latestOracleValue[i]));
        }

        uint256 collateralisation;
        for (uint256 i; i < latestOracleValue.length; ++i) {
            collateralisation += (latestOracleValue[i] * collateralMintedStables[i]) / BASE_8;
        }

        // check collateral ratio first
        uint256 stablecoinsIssued;
        {
            uint256 totalCollateralization = _computeCollateralisation();
            uint256 trueMintedStables = transmuter.getTotalIssued();
            if (
                trueMintedStables > 0 &&
                totalCollateralization.mulDiv(BASE_9, trueMintedStables, Math.Rounding.Up) > type(uint64).max
            ) {
                reverted = true;
                vm.expectRevert(bytes("SafeCast: value doesn't fit in 64 bits"));
            }
            (collatRatio, stablecoinsIssued) = transmuter.getCollateralRatio();
            if (reverted) return (collatRatio, true);
        }

        if (mintedStables > 0) {
            // This is the computed collateral ratio
            assertApproxEqAbs(collatRatio, uint64((collateralisation * BASE_9) / mintedStables), 1 wei);
        } else {
            assertEq(collatRatio, type(uint64).max);
        }
        assertEq(stablecoinsIssued, mintedStables);
    }

    function _updateOraclesWithSubCollaterals(
        uint256[3] memory latestOracleValue,
        uint256 mintedStables,
        uint256[] memory collateralMintedStables,
        uint256[3 * _MAX_SUB_COLLATERALS] memory airdropAmounts
    ) internal returns (uint64 collatRatio, bool reverted) {
        uint256 collateralisation;
        for (uint256 i; i < latestOracleValue.length; ++i) {
            latestOracleValue[i] = bound(latestOracleValue[i], _minOracleValue, BASE_18);
            MockChainlinkOracle(address(_oracles[i])).setLatestAnswer(int256(latestOracleValue[i]));

            IERC20[] memory listSubCollaterals = _subCollaterals[_collaterals[i]].subCollaterals;
            if (listSubCollaterals.length <= 1) {
                collateralisation += (latestOracleValue[i] * collateralMintedStables[i]) / BASE_8;
            } else {
                // we don't double count the real collaterals
                uint256 subCollateralValue = IERC20Metadata(address(listSubCollaterals[0])).balanceOf(
                    address(_managers[_collaterals[i]])
                );
                for (uint256 k = 1; k < listSubCollaterals.length; k++) {
                    (, int256 oracleValue, , , ) = MockChainlinkOracle(
                        address(_subCollaterals[_collaterals[i]].oracles[k - 1])
                    ).latestRoundData();
                    subCollateralValue +=
                        (uint256(oracleValue) *
                            _convertDecimalTo(
                                airdropAmounts[i * _MAX_SUB_COLLATERALS + k - 1],
                                IERC20Metadata(address(listSubCollaterals[k])).decimals(),
                                IERC20Metadata(address(listSubCollaterals[0])).decimals()
                            )) /
                        BASE_8;
                }
                collateralisation +=
                    (((BASE_18 * latestOracleValue[i]) / BASE_8) *
                        _convertDecimalTo(
                            subCollateralValue,
                            IERC20Metadata(address(listSubCollaterals[0])).decimals(),
                            18
                        )) /
                    BASE_18;
            }
        }

        {
            uint256 trueMintedStables = transmuter.getTotalIssued();
            if (
                trueMintedStables > 0 &&
                _computeCollateralisation().mulDiv(BASE_9, trueMintedStables, Math.Rounding.Up) > type(uint64).max
            ) {
                reverted = true;
                vm.expectRevert(bytes("SafeCast: value doesn't fit in 64 bits"));
            }
            uint256 stablecoinsIssued;
            (collatRatio, stablecoinsIssued) = transmuter.getCollateralRatio();
            if (reverted) return (0, true);
            assertEq(stablecoinsIssued, mintedStables);
        }

        if (mintedStables > 0) {
            assertApproxEqAbs(collatRatio, uint64((collateralisation * BASE_9) / mintedStables), 1 wei);
        } else {
            assertEq(collatRatio, type(uint64).max);
        }
    }

    function _randomRedeemptionFees(
        uint64[10] memory xFeeRedeemUnbounded,
        int64[10] memory yFeeRedeemUnbounded
    ) internal returns (uint64[] memory xFeeRedeem, int64[] memory yFeeRedeem) {
        (xFeeRedeem, yFeeRedeem) = _generateCurves(
            xFeeRedeemUnbounded,
            yFeeRedeemUnbounded,
            true,
            false,
            0,
            int256(BASE_9)
        );
        vm.prank(governor);
        transmuter.setRedemptionCurveParams(xFeeRedeem, yFeeRedeem);
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
                if (areForfeited[i * (_MAX_SUB_COLLATERALS + 1) + k]) {
                    forfeitTokens[index++] = address(listSubCollaterals[k]);
                }
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
        transmuter.setCollateralManager(token, managerData);
    }

    function _computeCollateralisation() internal view returns (uint256 totalCollateralization) {
        address[] memory collateralList = transmuter.getCollateralList();
        uint256 collateralListLength = collateralList.length;

        for (uint256 i; i < collateralListLength; ++i) {
            Collateral memory collateral = transmuter.getCollateralInfo(collateralList[i]);
            uint256 collateralBalance;
            if (collateral.isManaged > 0) {
                (, bytes memory data) = abi.decode(collateral.managerData.config, (ManagerType, bytes));
                (, collateralBalance) = abi.decode(data, (IManager)).totalAssets();
            } else {
                collateralBalance = IERC20(collateralList[i]).balanceOf(address(transmuter));
            }

            (, , , , uint256 oracleValue) = transmuter.getOracleValues(collateralList[i]);
            totalCollateralization +=
                (oracleValue * LibHelpers.convertDecimalTo(collateralBalance, collateral.decimals, 18)) /
                BASE_18;
        }
    }
}
