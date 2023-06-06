// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";
import { stdError } from "forge-std/Test.sol";
import { ManagerStorage, ManagerType } from "contracts/transmuter/Storage.sol";

import "contracts/utils/Errors.sol" as Errors;

import "../Fixture.sol";
import { IERC20Metadata } from "../mock/MockTokenPermit.sol";
import { MockManager } from "../mock/MockManager.sol";
import "../utils/FunctionUtils.sol";
import "../utils/FunctionUtils.sol";

contract BurnTest is Fixture, FunctionUtils {
    using SafeERC20 for IERC20;

    uint256 internal _maxAmountWithoutDecimals = 10 ** 15;
    // making this value smaller worsen rounding and make test harder to pass.
    // Trade off between bullet proof against all oracles and all interactions
    uint256 internal _minOracleValue = 10 ** 3; // 10**(-6)
    uint256 internal _minWallet = 10 ** 18; // in base 18
    uint256 internal _maxWallet = 10 ** (18 + 12); // in base 18
    int64 internal _minBurnFee = -int64(int256(BASE_9 / 2));

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
                                                 GETISSUEDBYCOLLATERAL                                              
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_BurnGetIssuedByCollateral(
        uint256[3] memory initialAmounts,
        uint256[3] memory amounts,
        uint256[3] memory burntAmounts,
        uint256[3] memory latestOracleValue
    ) public {
        // let's first load the reserves of the protocol
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
            charlie,
            sweeper,
            initialAmounts,
            0
        );
        _setMintFeesForNegativeBurnFees(0);
        _updateOracles(latestOracleValue);

        // let's first load the reserves of the protocol
        (uint256 mintedStables2, uint256[] memory collateralMintedStables2) = _loadReserves(
            charlie,
            sweeper,
            amounts,
            0
        );

        (bool succeed, uint256 burntStables, uint256[] memory collateralBurntStables) = _emptyReserves(
            charlie,
            burntAmounts
        );
        if (!succeed) return;

        uint256 computedTotalStable = mintedStables + mintedStables2;
        for (uint256 i; i < collateralMintedStables.length; i++) {
            computedTotalStable -= collateralBurntStables[i];
            (uint256 stablecoinsFromCollateral, ) = transmuter.getIssuedByCollateral(address(_collaterals[i]));
            assertEq(
                collateralMintedStables[i] + collateralMintedStables2[i] - collateralBurntStables[i],
                stablecoinsFromCollateral
            );
        }

        assertEq(computedTotalStable, agToken.totalSupply());
        assertEq(mintedStables + mintedStables2 - burntStables, agToken.totalSupply());
        (, uint256 totalStablecoins) = transmuter.getIssuedByCollateral(address(_collaterals[0]));
        assertEq(computedTotalStable, totalStablecoins);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                  GETCOLLATERALRATIO                                                
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_BurnGetCollateralRatio(
        uint256[3] memory initialAmounts,
        uint256[3] memory amounts,
        uint256[3] memory burntAmounts,
        uint256[3] memory latestOracleValue
    ) public {
        // let's first load the reserves of the protocol
        (uint256 mintedStables, ) = _loadReserves(charlie, sweeper, initialAmounts, 0);
        _setMintFeesForNegativeBurnFees(0);
        _updateOracles(latestOracleValue);

        // let's first load the reserves of the protocol
        (uint256 mintedStables2, ) = _loadReserves(charlie, sweeper, amounts, 0);

        (bool succeed, uint256 burntStables, ) = _emptyReserves(charlie, burntAmounts);
        if (!succeed) return;

        uint256 collateralisation;
        for (uint256 i; i < _collaterals.length; ++i) {
            (, int256 oracleValue, , , ) = MockChainlinkOracle(address(_oracles[i])).latestRoundData();
            uint8 decimals = IERC20Metadata(address(_collaterals[i])).decimals();
            collateralisation += ((IERC20(_collaterals[i]).balanceOf(address(transmuter)) *
                10 ** (18 - decimals) *
                uint256(oracleValue)) / BASE_8);
        }

        uint256 computedCollatRatio = type(uint64).max;
        bool collatRatioAboveLimit;
        if (mintedStables + mintedStables2 - burntStables > 0) {
            computedCollatRatio = uint64(
                (collateralisation * BASE_9) / (mintedStables + mintedStables2 - burntStables)
            );
            if ((collateralisation * BASE_9) / (mintedStables + mintedStables2 - burntStables) > type(uint64).max)
                collatRatioAboveLimit = true;
        }

        (uint64 collatRatio, uint256 reservesValue) = transmuter.getCollateralRatio();
        if (!collatRatioAboveLimit) {
            assertApproxEqAbs(computedCollatRatio, collatRatio, 1 wei);
            assertApproxEqAbs(mintedStables + mintedStables2 - burntStables, reservesValue, 1 wei);
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         BURN                                                       
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_QuoteBurnExactInputSimple(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256 burnAmount,
        uint256 fromToken
    ) public {
        // let's first load the reserves of the protocol
        (, uint256[] memory collateralMintedStables) = _loadReserves(
            charlie,
            sweeper,
            initialAmounts,
            transferProportion
        );

        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        burnAmount = bound(burnAmount, 0, collateralMintedStables[fromToken]);
        uint256 amountOut = transmuter.quoteIn(burnAmount, address(agToken), _collaterals[fromToken]);

        assertEq(_convertDecimalTo(burnAmount, 18, IERC20Metadata(_collaterals[fromToken]).decimals()), amountOut);
    }

    function testFuzz_QuoteBurnExactInputNonNullFees(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        int64 burnFee,
        uint256 burnAmount,
        uint256 fromToken
    ) public {
        // let's first load the reserves of the protocol
        (, uint256[] memory collateralMintedStables) = _loadReserves(
            charlie,
            sweeper,
            initialAmounts,
            transferProportion
        );
        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        burnAmount = bound(burnAmount, 0, collateralMintedStables[fromToken]);
        burnFee = int64(bound(int256(burnFee), 0, int256(BASE_9 - 1)));
        uint64[] memory xFeeBurn = new uint64[](1);
        xFeeBurn[0] = uint64(BASE_9);
        int64[] memory yFeeBurn = new int64[](1);
        yFeeBurn[0] = burnFee;
        vm.prank(governor);
        transmuter.setFees(_collaterals[fromToken], xFeeBurn, yFeeBurn, false);

        if (burnFee >= int256((BASE_9 * 999) / 1000)) vm.expectRevert(Errors.InvalidSwap.selector);
        uint256 amountOut = transmuter.quoteIn(burnAmount, address(agToken), _collaterals[fromToken]);
        if (burnFee >= int256((BASE_9 * 999) / 1000)) return;
        uint256 supposedAmountOut = (
            _convertDecimalTo(
                (burnAmount * (BASE_9 - uint64(burnFee))) / BASE_9,
                18,
                IERC20Metadata(_collaterals[fromToken]).decimals()
            )
        );

        assertEq(supposedAmountOut, amountOut);
    }

    function testFuzz_QuoteBurnReflexivitySimple(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256 burnAmount,
        uint256 fromToken
    ) public {
        // let's first load the reserves of the protocol
        (, uint256[] memory collateralMintedStables) = _loadReserves(
            charlie,
            sweeper,
            initialAmounts,
            transferProportion
        );

        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        burnAmount = bound(burnAmount, 0, collateralMintedStables[fromToken]);
        uint256 amountOut = transmuter.quoteIn(burnAmount, address(agToken), _collaterals[fromToken]);
        uint256 reflexiveBurnAmount = transmuter.quoteOut(amountOut, address(agToken), _collaterals[fromToken]);
        if (amountOut == 0) return;
        _assertApproxEqRelDecimalWithTolerance(
            amountOut,
            _convertDecimalTo(burnAmount, 18, IERC20Metadata(_collaterals[fromToken]).decimals()),
            _convertDecimalTo(burnAmount, 18, IERC20Metadata(_collaterals[fromToken]).decimals()),
            _MAX_PERCENTAGE_DEVIATION,
            18
        );
        if (amountOut > _minWallet) {
            _assertApproxEqRelDecimalWithTolerance(
                burnAmount,
                reflexiveBurnAmount,
                burnAmount,
                _MAX_PERCENTAGE_DEVIATION,
                18
            );
        }
    }

    function testFuzz_QuoteBurnReflexivityRandomOracle(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256[3] memory latestOracleValue,
        uint256 burnAmount,
        uint256 fromToken
    ) public {
        // let's first load the reserves of the protocol
        (, uint256[] memory collateralMintedStables) = _loadReserves(
            charlie,
            sweeper,
            initialAmounts,
            transferProportion
        );
        _updateOracles(latestOracleValue);

        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        burnAmount = bound(burnAmount, 0, collateralMintedStables[fromToken]);
        uint256 supposedAmountOut = _convertDecimalTo(
            _getBurnOracle(burnAmount, fromToken),
            18,
            IERC20Metadata(_collaterals[fromToken]).decimals()
        );
        uint256 amountOut = transmuter.quoteIn(burnAmount, address(agToken), _collaterals[fromToken]);
        uint256 reflexiveBurnAmount = transmuter.quoteOut(amountOut, address(agToken), _collaterals[fromToken]);
        _assertApproxEqRelDecimalWithTolerance(supposedAmountOut, amountOut, amountOut, _MAX_PERCENTAGE_DEVIATION, 18);
        if (amountOut > _minWallet) {
            _assertApproxEqRelDecimalWithTolerance(
                burnAmount,
                reflexiveBurnAmount,
                burnAmount,
                _MAX_PERCENTAGE_DEVIATION,
                18
            );
        }
    }

    function testFuzz_QuoteBurnExactInputReflexivityFees(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        int64 burnFee,
        uint256 burnAmount,
        uint256 fromToken
    ) public {
        // let's first load the reserves of the protocol
        (, uint256[] memory collateralMintedStables) = _loadReserves(
            charlie,
            sweeper,
            initialAmounts,
            transferProportion
        );
        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        burnAmount = bound(burnAmount, 0, collateralMintedStables[fromToken]);
        burnFee = int64(bound(int256(burnFee), 0, int256(BASE_9 - 1)));
        uint64[] memory xFeeBurn = new uint64[](1);
        xFeeBurn[0] = uint64(BASE_9);
        int64[] memory yFeeBurn = new int64[](1);
        yFeeBurn[0] = burnFee;
        vm.prank(governor);
        transmuter.setFees(_collaterals[fromToken], xFeeBurn, yFeeBurn, false);

        uint256 supposedAmountOut = _convertDecimalTo(
            (burnAmount * (BASE_9 - uint64(burnFee))) / BASE_9,
            18,
            IERC20Metadata(_collaterals[fromToken]).decimals()
        );

        if (burnFee >= int256((BASE_9 * 999) / 1000)) vm.expectRevert(Errors.InvalidSwap.selector);
        uint256 amountOut = transmuter.quoteIn(burnAmount, address(agToken), _collaterals[fromToken]);
        if (burnFee >= int256((BASE_9 * 999) / 1000)) vm.expectRevert(Errors.InvalidSwap.selector);
        uint256 reflexiveBurnAmount = transmuter.quoteOut(amountOut, address(agToken), _collaterals[fromToken]);
        if (burnFee >= int256((BASE_9 * 999) / 1000)) return;

        assertEq(supposedAmountOut, amountOut);
        if (amountOut > _minWallet) {
            _assertApproxEqRelDecimalWithTolerance(
                burnAmount,
                reflexiveBurnAmount,
                burnAmount,
                _MAX_PERCENTAGE_DEVIATION,
                18
            );
        }
    }

    function testFuzz_QuoteBurnExactInputReflexivityOracleFees(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256[3] memory latestOracleValue,
        int64 burnFee,
        uint256 burnAmount,
        uint256 fromToken
    ) public {
        // let's first load the reserves of the protocol
        (, uint256[] memory collateralMintedStables) = _loadReserves(
            charlie,
            sweeper,
            initialAmounts,
            transferProportion
        );
        _updateOracles(latestOracleValue);

        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        burnAmount = bound(burnAmount, 0, collateralMintedStables[fromToken]);
        burnFee = int64(bound(int256(burnFee), 0, int256(BASE_9 - 1)));
        uint64[] memory xFeeBurn = new uint64[](1);
        xFeeBurn[0] = uint64(BASE_9);
        int64[] memory yFeeBurn = new int64[](1);
        yFeeBurn[0] = burnFee;
        vm.prank(governor);
        transmuter.setFees(_collaterals[fromToken], xFeeBurn, yFeeBurn, false);

        uint256 supposedAmountOut = _convertDecimalTo(
            _getBurnOracle((burnAmount * (BASE_9 - uint64(burnFee))), fromToken) / BASE_9,
            18,
            IERC20Metadata(_collaterals[fromToken]).decimals()
        );
        uint256 amountOut = transmuter.quoteIn(burnAmount, address(agToken), _collaterals[fromToken]);
        if (amountOut == 0 || burnAmount == 0) return;
        uint256 reflexiveBurnAmount = transmuter.quoteOut(amountOut, address(agToken), _collaterals[fromToken]);

        _assertApproxEqRelDecimalWithTolerance(
            supposedAmountOut,
            amountOut,
            amountOut,
            _MAX_PERCENTAGE_DEVIATION,
            IERC20Metadata(_collaterals[fromToken]).decimals()
        );
        if (amountOut > _minWallet) {
            _assertApproxEqRelDecimalWithTolerance(
                burnAmount,
                reflexiveBurnAmount,
                burnAmount,
                _MAX_PERCENTAGE_DEVIATION,
                18
            );
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                 PIECEWISE LINEAR FEES                                              
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_QuoteBurnExactInputReflexivityFixPiecewiseFees(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256[3] memory latestOracleValue,
        int64 upperFees,
        uint256 stableAmount,
        uint256 fromToken
    ) public {
        // let's first load the reserves of the protocol
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
            charlie,
            sweeper,
            initialAmounts,
            transferProportion
        );
        if (mintedStables == 0) return;
        _updateOracles(latestOracleValue);

        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        stableAmount = bound(stableAmount, 0, collateralMintedStables[fromToken]);
        if (stableAmount == 0) return;
        upperFees = int64(bound(int256(upperFees), 0, int256((BASE_9 * 999) / 1000) - 1));
        uint64[] memory xFeeBurn = new uint64[](3);
        xFeeBurn[0] = uint64(BASE_9);
        xFeeBurn[1] = uint64((BASE_9 * 99) / 100);
        xFeeBurn[2] = uint64(BASE_9 / 2);
        int64[] memory yFeeBurn = new int64[](3);
        yFeeBurn[0] = int64(0);
        yFeeBurn[1] = int64(0);
        yFeeBurn[2] = upperFees;
        vm.prank(governor);
        transmuter.setFees(_collaterals[fromToken], xFeeBurn, yFeeBurn, false);

        uint256 supposedAmountOut;
        {
            uint256 copyStableAmount = stableAmount;
            uint256[] memory exposures = _getExposures(mintedStables, collateralMintedStables);
            (
                uint256 amountFromPrevBreakpoint,
                uint256 amountToNextBreakpoint,
                uint256 lowerIndex
            ) = _amountToPrevAndNextExposure(
                    mintedStables,
                    fromToken,
                    collateralMintedStables,
                    exposures[fromToken],
                    xFeeBurn
                );
            // this is to handle in easy tests
            if (lowerIndex == xFeeBurn.length - 1) return;

            if (lowerIndex == 0) {
                if (copyStableAmount <= amountToNextBreakpoint) {
                    collateralMintedStables[fromToken] -= copyStableAmount;
                    mintedStables -= copyStableAmount;
                    // first burn segment are always constant fees
                    supposedAmountOut += (copyStableAmount * (BASE_9 - uint64(yFeeBurn[0]))) / BASE_9;
                    copyStableAmount = 0;
                } else {
                    collateralMintedStables[fromToken] -= amountToNextBreakpoint;
                    mintedStables -= amountToNextBreakpoint;
                    // first burn segment are always constant fees
                    supposedAmountOut += (amountToNextBreakpoint * (BASE_9 - uint64(yFeeBurn[0]))) / BASE_9;
                    copyStableAmount -= amountToNextBreakpoint;

                    exposures = _getExposures(mintedStables, collateralMintedStables);
                    (amountFromPrevBreakpoint, amountToNextBreakpoint, lowerIndex) = _amountToPrevAndNextExposure(
                        mintedStables,
                        fromToken,
                        collateralMintedStables,
                        exposures[fromToken],
                        xFeeBurn
                    );
                }
            }
            if (copyStableAmount > 0) {
                if (copyStableAmount <= amountToNextBreakpoint) {
                    collateralMintedStables[fromToken] -= copyStableAmount;
                    int256 midFees;
                    {
                        int256 currentFees;
                        uint256 slope = (uint256(uint64(yFeeBurn[lowerIndex + 1] - yFeeBurn[lowerIndex])) * BASE_36) /
                            (amountToNextBreakpoint + amountFromPrevBreakpoint);
                        currentFees = yFeeBurn[lowerIndex] + int256((slope * amountFromPrevBreakpoint) / BASE_36);
                        int256 endFees = yFeeBurn[lowerIndex] +
                            int256((slope * (amountFromPrevBreakpoint + copyStableAmount)) / BASE_36);
                        midFees = (currentFees + endFees) / 2;
                    }
                    supposedAmountOut += (copyStableAmount * (BASE_9 - uint64(uint256(midFees)))) / BASE_9;
                } else {
                    collateralMintedStables[fromToken] -= amountToNextBreakpoint;
                    {
                        int256 midFees;
                        {
                            uint256 slope = (uint256(uint64(yFeeBurn[lowerIndex + 1] - yFeeBurn[lowerIndex])) *
                                BASE_36) / (amountToNextBreakpoint + amountFromPrevBreakpoint);
                            int256 currentFees = yFeeBurn[lowerIndex] +
                                int256((slope * amountFromPrevBreakpoint) / BASE_36);
                            int256 endFees = yFeeBurn[lowerIndex + 1];
                            midFees = (currentFees + endFees) / 2;
                        }
                        supposedAmountOut += (amountToNextBreakpoint * (BASE_9 - uint64(uint256(midFees)))) / BASE_9;
                    }
                    // next part is just with end fees
                    supposedAmountOut +=
                        ((copyStableAmount - amountToNextBreakpoint) * (BASE_9 - uint64(yFeeBurn[lowerIndex + 1]))) /
                        BASE_9;
                }
            }
        }
        supposedAmountOut = _convertDecimalTo(
            _getBurnOracle(supposedAmountOut, fromToken),
            18,
            IERC20Metadata(_collaterals[fromToken]).decimals()
        );

        uint256 amountOut = transmuter.quoteIn(stableAmount, address(agToken), _collaterals[fromToken]);
        if (amountOut == 0) return;
        uint256 reflexiveAmountStable = transmuter.quoteOut(amountOut, address(agToken), _collaterals[fromToken]);
        // TODO Anyone know how we could do without this double reflexivity?
        // The problem to compare reflexiveAmountStable and amountOut is: suppose there are very high fees
        // at the end segment BASE_9-1
        // Suppose also that when burning M stablecoins, M-N are used up until xFeeBurn[2] yielding C collateral
        // Then the remaining N yield EPS<<0 collateral --> total collateral C+EPS but with precision error
        // (collateral being with 6 decimals) --> I end up with C
        // Now quote C collateral to burn --> M-N
        uint256 reflexiveAmountOut = transmuter.quoteIn(
            reflexiveAmountStable,
            address(agToken),
            _collaterals[fromToken]
        );

        if (stableAmount > _minWallet) {
            _assertApproxEqRelDecimalWithTolerance(
                supposedAmountOut,
                amountOut,
                amountOut,
                // precision of 0.01%
                _MAX_PERCENTAGE_DEVIATION * 100,
                18
            );
            _assertApproxEqRelDecimalWithTolerance(
                reflexiveAmountOut,
                amountOut,
                reflexiveAmountOut,
                _MAX_PERCENTAGE_DEVIATION * 10,
                18
            );
        }
    }

    function testFuzz_QuoteBurnReflexivityRandPiecewiseFees(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint64[10] memory xFeeBurnUnbounded,
        int64[10] memory yFeeBurnUnbounded,
        uint256 stableAmount,
        uint256 fromToken
    ) public {
        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        // let's first load the reserves of the protocol
        (, uint256[] memory collateralMintedStables) = _loadReserves(
            charlie,
            sweeper,
            initialAmounts,
            transferProportion
        );
        _randomBurnFees(
            _collaterals[fromToken],
            xFeeBurnUnbounded,
            yFeeBurnUnbounded,
            int256(BASE_9) - (2 * int256(BASE_9)) / 1000
        );

        stableAmount = bound(stableAmount, 0, collateralMintedStables[fromToken]);
        if (stableAmount == 0) return;

        // _logIssuedCollateral();
        uint256 amountOut = transmuter.quoteIn(stableAmount, address(agToken), _collaterals[fromToken]);
        // This will crash if the
        if (amountOut != 0) {
            uint256 reflexiveAmountStable = transmuter.quoteOut(amountOut, address(agToken), _collaterals[fromToken]);
            uint256 reflexiveAmountOut = transmuter.quoteIn(
                reflexiveAmountStable,
                address(agToken),
                _collaterals[fromToken]
            );

            if (amountOut > _minWallet / 10 ** (18 - IERC20Metadata(_collaterals[fromToken]).decimals())) {
                _assertApproxEqRelDecimalWithTolerance(
                    reflexiveAmountOut,
                    amountOut,
                    reflexiveAmountOut,
                    // 0.01%
                    _MAX_PERCENTAGE_DEVIATION * 100,
                    IERC20Metadata(_collaterals[fromToken]).decimals()
                );
            }
        }
    }

    // Oracle precision worsen reflexivity
    function testFuzz_QuoteBurnReflexivityRandOracleAndPiecewiseFees(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256[3] memory latestOracleValue,
        uint64[10] memory xFeeBurnUnbounded,
        int64[10] memory yFeeBurnUnbounded,
        uint256 stableAmount,
        uint256 fromToken
    ) public {
        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        // let's first load the reserves of the protocol
        (, uint256[] memory collateralMintedStables) = _loadReserves(
            charlie,
            sweeper,
            initialAmounts,
            transferProportion
        );
        _updateOracles(latestOracleValue);
        _randomBurnFees(
            _collaterals[fromToken],
            xFeeBurnUnbounded,
            yFeeBurnUnbounded,
            int256(BASE_9) - int256(BASE_9) / 1000
        );

        stableAmount = bound(stableAmount, 0, collateralMintedStables[fromToken]);
        if (stableAmount == 0) return;

        // _logIssuedCollateral();
        uint256 amountOut = transmuter.quoteIn(stableAmount, address(agToken), _collaterals[fromToken]);
        // This will crash if the
        if (amountOut != 0) {
            uint256 reflexiveAmountStable = transmuter.quoteOut(amountOut, address(agToken), _collaterals[fromToken]);
            uint256 reflexiveAmountOut = transmuter.quoteIn(
                reflexiveAmountStable,
                address(agToken),
                _collaterals[fromToken]
            );

            if (amountOut > (10 * _minWallet) / 10 ** (18 - IERC20Metadata(_collaterals[fromToken]).decimals())) {
                _assertApproxEqRelDecimalWithTolerance(
                    reflexiveAmountOut,
                    amountOut,
                    reflexiveAmountOut,
                    // 0.01%
                    _MAX_PERCENTAGE_DEVIATION * 100,
                    IERC20Metadata(_collaterals[fromToken]).decimals()
                );
            }
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                   INDEPENDENT PATH                                                 
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_QuoteBurnExactInputIndependant(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256 splitProportion,
        uint256[3] memory latestOracleValue,
        uint64[10] memory xFeeBurnUnbounded,
        int64[10] memory yFeeBurnUnbounded,
        uint256 stableAmount,
        uint256 fromToken
    ) public {
        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        // let's first load the reserves of the protocol
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
            alice,
            address(0),
            initialAmounts,
            transferProportion
        );
        if (mintedStables == 0) return;
        _updateOracles(latestOracleValue);
        _randomBurnFees(
            _collaterals[fromToken],
            xFeeBurnUnbounded,
            yFeeBurnUnbounded,
            // when fees are larger than 99.9% we don't ensure the independent path
            // It won't be independant anymore because the current fees and the mid fee
            // approximation won't be correct and could be trickable. by chosing one over the other
            int256(BASE_9) - int256(BASE_9) / 1000
        );
        stableAmount = bound(stableAmount, 0, collateralMintedStables[fromToken]);
        if (stableAmount == 0) return;

        uint256 amountOut = transmuter.quoteIn(stableAmount, address(agToken), _collaterals[fromToken]);
        splitProportion = bound(splitProportion, 0, BASE_9);
        uint256 amountStableSplit1 = (stableAmount * splitProportion) / BASE_9;
        amountStableSplit1 = amountStableSplit1 == 0 ? 1 : amountStableSplit1;
        uint256 amountOutSplit1 = transmuter.quoteIn(amountStableSplit1, address(agToken), _collaterals[fromToken]);
        // do the swap to update the system
        _burnExactInput(alice, _collaterals[fromToken], amountStableSplit1, amountOutSplit1);
        uint256 amountOutSplit2 = transmuter.quoteIn(
            stableAmount - amountStableSplit1,
            address(agToken),
            _collaterals[fromToken]
        );
        if (stableAmount > _minWallet) {
            _assertApproxEqRelDecimalWithTolerance(
                amountOutSplit1 + amountOutSplit2,
                amountOut,
                amountOut,
                // 0.01%
                _MAX_PERCENTAGE_DEVIATION * 100,
                18
            );
        }
    }

    function testFuzz_QuoteBurnExactOutputIndependant(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256 splitProportion,
        uint256[3] memory latestOracleValue,
        uint64[10] memory xFeeBurnUnbounded,
        int64[10] memory yFeeBurnUnbounded,
        uint256 amountOut,
        uint256 fromToken
    ) public {
        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        // let's first load the reserves of the protocol
        (uint256 mintedStables, ) = _loadReserves(alice, address(0), initialAmounts, transferProportion);
        if (mintedStables == 0) return;
        _updateOracles(latestOracleValue);
        _randomBurnFees(
            _collaterals[fromToken],
            xFeeBurnUnbounded,
            yFeeBurnUnbounded,
            int256(BASE_9) - int256(BASE_9) / 1000
        );
        amountOut = bound(amountOut, 0, IERC20(_collaterals[fromToken]).balanceOf(address(transmuter)));
        if (amountOut == 0) return;

        uint256 amountStable = transmuter.quoteOut(amountOut, address(agToken), _collaterals[fromToken]);
        splitProportion = bound(splitProportion, 0, BASE_9);
        uint256 amountOutSplit1 = (amountOut * splitProportion) / BASE_9;
        amountOutSplit1 = amountOutSplit1 == 0 ? 1 : amountOutSplit1;
        uint256 amountStableSplit1 = transmuter.quoteOut(amountOutSplit1, address(agToken), _collaterals[fromToken]);
        // do the swap to update the system
        bool notReverted = _burnExactOutput(alice, _collaterals[fromToken], amountOutSplit1, amountStableSplit1);
        if (notReverted) return;
        uint256 amountStableSplit2 = transmuter.quoteOut(
            amountOut - amountOutSplit1,
            address(agToken),
            _collaterals[fromToken]
        );
        if (amountStable > _minWallet) {
            _assertApproxEqRelDecimalWithTolerance(
                amountStableSplit1 + amountStableSplit2,
                amountStable,
                amountStable,
                // 0.01%
                _MAX_PERCENTAGE_DEVIATION * 100,
                18
            );
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         BURN                                                       
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_BurnExactInput(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256[3] memory latestOracleValue,
        uint64[10] memory xFeeBurnUnbounded,
        int64[10] memory yFeeBurnUnbounded,
        uint256 stableAmount,
        uint256 fromToken
    ) public {
        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        // let's first load the reserves of the protocol
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
            alice,
            address(0),
            initialAmounts,
            transferProportion
        );
        if (mintedStables == 0) return;
        _updateOracles(latestOracleValue);
        _randomBurnFees(
            _collaterals[fromToken],
            xFeeBurnUnbounded,
            yFeeBurnUnbounded,
            int256(BASE_9) - int256(BASE_9) / 1000
        );
        stableAmount = bound(stableAmount, 0, collateralMintedStables[fromToken]);
        if (stableAmount == 0) return;

        uint256 prevBalanceStable = agToken.balanceOf(alice);
        uint256 prevTransmuterCollat = IERC20(_collaterals[fromToken]).balanceOf(address(transmuter));

        uint256 amountOut = transmuter.quoteIn(stableAmount, address(agToken), _collaterals[fromToken]);
        bool burnMoreThanHad = _burnExactInput(alice, _collaterals[fromToken], stableAmount, amountOut);

        uint256 balanceStable = agToken.balanceOf(alice);
        if (amountOut == 0 || stableAmount == 0) assertEq(balanceStable, prevBalanceStable);
        else assertEq(balanceStable, prevBalanceStable - stableAmount);
        assertEq(IERC20(_collaterals[fromToken]).balanceOf(alice), amountOut);
        assertEq(
            IERC20(_collaterals[fromToken]).balanceOf(address(transmuter)),
            burnMoreThanHad ? 0 : prevTransmuterCollat - amountOut
        );

        (uint256 newStableAmountCollat, uint256 newStableAmount) = transmuter.getIssuedByCollateral(
            _collaterals[fromToken]
        );

        if (amountOut == 0 || stableAmount == 0) {
            assertApproxEqAbs(newStableAmountCollat, collateralMintedStables[fromToken], 1 wei);
            assertApproxEqAbs(newStableAmount, mintedStables, 1 wei);
        } else {
            assertApproxEqAbs(newStableAmountCollat, collateralMintedStables[fromToken] - stableAmount, 1 wei);
            assertApproxEqAbs(newStableAmount, mintedStables - stableAmount, 1 wei);
        }
    }

    function testFuzz_BurnExactOutput(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256[3] memory latestOracleValue,
        uint64[10] memory xFeeBurnUnbounded,
        int64[10] memory yFeeBurnUnbounded,
        uint256 amountOut,
        uint256 fromToken
    ) public {
        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        // let's first load the reserves of the protocol
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
            alice,
            address(0),
            initialAmounts,
            transferProportion
        );
        if (mintedStables == 0) return;
        _updateOracles(latestOracleValue);
        _randomBurnFees(
            _collaterals[fromToken],
            xFeeBurnUnbounded,
            yFeeBurnUnbounded,
            int256(BASE_9) - int256(BASE_9) / 1000
        );
        amountOut = bound(amountOut, 0, IERC20(_collaterals[fromToken]).balanceOf(address(transmuter)));
        if (amountOut == 0) return;

        uint256 prevBalanceStable = agToken.balanceOf(alice);

        uint256 stableAmount = transmuter.quoteOut(amountOut, address(agToken), _collaterals[fromToken]);
        bool notReverted = _burnExactOutput(alice, _collaterals[fromToken], amountOut, stableAmount);
        if (notReverted) return;

        uint256 balanceStable = agToken.balanceOf(alice);
        uint256 prevTransmuterCollat = IERC20(_collaterals[fromToken]).balanceOf(address(transmuter));

        assertEq(balanceStable, prevBalanceStable - stableAmount);
        assertEq(IERC20(_collaterals[fromToken]).balanceOf(alice), amountOut);
        assertEq(IERC20(_collaterals[fromToken]).balanceOf(address(transmuter)), prevTransmuterCollat - amountOut);

        (uint256 newStableAmountCollat, uint256 newStableAmount) = transmuter.getIssuedByCollateral(
            _collaterals[fromToken]
        );

        assertApproxEqAbs(newStableAmountCollat, collateralMintedStables[fromToken] - stableAmount, 1 wei);
        assertApproxEqAbs(newStableAmount, mintedStables - stableAmount, 1 wei);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                   BURN WITH MANAGER                                                
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/
    function testFuzz_BurnMaxAvailableManager(uint256[3] memory initialAmounts, uint256 stableAmount) public {
        // create a manager to be above the maxAvailable
        MockManager manager = new MockManager(_collaterals[0]);
        IERC20[] memory subCollaterals = new IERC20[](1);
        AggregatorV3Interface[] memory oracles = new AggregatorV3Interface[](1);
        subCollaterals[0] = IERC20(_collaterals[0]);
        uint8[] memory decimals = new uint8[](1);
        decimals[0] = IERC20Metadata(_collaterals[0]).decimals();
        uint32[] memory stalePeriods = new uint32[](1);
        uint8[] memory oracleIsMultiplied = new uint8[](1);
        uint8[] memory chainlinkDecimals = new uint8[](1);
        oracles[0] = oracleA;
        stalePeriods[0] = 365 days;
        oracleIsMultiplied[0] = 1;
        chainlinkDecimals[0] = 8;

        manager.setSubCollaterals(
            subCollaterals,
            abi.encode(decimals, oracles, stalePeriods, oracleIsMultiplied, chainlinkDecimals)
        );
        ManagerStorage memory managerData = ManagerStorage(
            subCollaterals,
            abi.encode(ManagerType.EXTERNAL, abi.encode(IManager(address(manager))))
        );
        vm.prank(governor);
        transmuter.setCollateralManager(_collaterals[0], managerData);
        // done

        // let's first load the reserves of the protocol
        (, uint256[] memory collateralMintedStables) = _loadReserves(alice, address(0), initialAmounts, 0);
        if (collateralMintedStables[0] < BASE_18) return;

        // artificially make the manager maxAvailable to 0
        deal(_collaterals[0], address(manager), 0);

        stableAmount = bound(stableAmount, BASE_18, collateralMintedStables[0]);
        if (stableAmount == 0) return;

        vm.expectRevert(Errors.InvalidSwap.selector);
        transmuter.quoteIn(stableAmount, address(agToken), _collaterals[0]);
        vm.startPrank(alice);
        vm.expectRevert();
        transmuter.swapExactInput(stableAmount, 0, address(agToken), _collaterals[0], alice, block.timestamp * 2);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         UTILS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _loadReserves(
        address owner,
        address receiver,
        uint256[3] memory initialAmounts,
        uint256 transferProportion
    ) internal returns (uint256 mintedStables, uint256[] memory collateralMintedStables) {
        collateralMintedStables = new uint256[](_collaterals.length);

        vm.startPrank(owner);
        for (uint256 i; i < _collaterals.length; i++) {
            initialAmounts[i] = bound(initialAmounts[i], 0, _maxTokenAmount[i]);
            deal(_collaterals[i], owner, initialAmounts[i]);
            IERC20(_collaterals[i]).approve(address(transmuter), initialAmounts[i]);

            collateralMintedStables[i] = transmuter.swapExactInput(
                initialAmounts[i],
                0,
                _collaterals[i],
                address(agToken),
                owner,
                block.timestamp * 2
            );
            mintedStables += collateralMintedStables[i];
        }

        // Send a proportion of these to another account user just to complexify the case
        transferProportion = bound(transferProportion, 0, BASE_9);
        if (receiver != address(0)) agToken.transfer(receiver, (mintedStables * transferProportion) / BASE_9);
        vm.stopPrank();

        _setMintFeesForNegativeBurnFees(-_minBurnFee);
    }

    function _emptyReserves(
        address owner,
        uint256[3] memory amounts
    ) internal returns (bool succeed, uint256 burntStables, uint256[] memory collateralBurntStables) {
        collateralBurntStables = new uint256[](_collaterals.length);
        succeed = true;

        vm.startPrank(owner);
        for (uint256 i; i < _collaterals.length; i++) {
            amounts[i] = bound(amounts[i], 0, IERC20(_collaterals[i]).balanceOf(address(transmuter)));
            (uint256 maxAmount, ) = transmuter.getIssuedByCollateral(_collaterals[i]);
            uint256 estimatedStable = transmuter.quoteOut(amounts[i], address(agToken), _collaterals[i]);
            uint256 balanceStableOwner = agToken.balanceOf(owner);
            if (estimatedStable > maxAmount && estimatedStable > balanceStableOwner)
                vm.expectRevert(stdError.arithmeticError);
            else if (estimatedStable > balanceStableOwner) vm.expectRevert("ERC20: burn amount exceeds balance");
            else if (estimatedStable > maxAmount) vm.expectRevert(stdError.arithmeticError);
            collateralBurntStables[i] = transmuter.swapExactOutput(
                amounts[i],
                estimatedStable,
                address(agToken),
                _collaterals[i],
                owner,
                block.timestamp * 2
            );
            if (estimatedStable > balanceStableOwner || estimatedStable > maxAmount)
                return (false, burntStables, collateralBurntStables);
            burntStables += collateralBurntStables[i];
        }
        vm.stopPrank();
    }

    function _setMintFeesForNegativeBurnFees(int64 smallestFee) internal {
        // set mint Fees to be consistent with the min fee on Burn
        uint64[] memory xFee = new uint64[](1);
        xFee[0] = uint64(0);
        int64[] memory yFee = new int64[](1);
        yFee[0] = smallestFee;
        vm.startPrank(governor);
        transmuter.setFees(address(eurA), xFee, yFee, true);
        transmuter.setFees(address(eurB), xFee, yFee, true);
        transmuter.setFees(address(eurY), xFee, yFee, true);
        vm.stopPrank();
    }

    function _getExposures(
        uint256 mintedStables,
        uint256[] memory collateralMintedStables
    ) internal view returns (uint256[] memory exposures) {
        exposures = new uint256[](_collaterals.length);
        for (uint256 i; i < _collaterals.length; i++) {
            exposures[i] = (collateralMintedStables[i] * BASE_9) / mintedStables;
        }
    }

    function _amountToPrevAndNextExposure(
        uint256 mintedStables,
        uint256 indexCollat,
        uint256[] memory collateralMintedStables,
        uint256 exposure,
        uint64[] memory xThres
    ) internal pure returns (uint256 amountToPrevBreakpoint, uint256 amountToNextBreakpoint, uint256 indexExposure) {
        if (exposure <= xThres[xThres.length - 1]) return (0, 0, xThres.length - 1);
        while (exposure < xThres[indexExposure]) indexExposure++;
        if (exposure > xThres[indexExposure]) indexExposure--;
        amountToNextBreakpoint =
            (BASE_9 * collateralMintedStables[indexCollat] - xThres[indexExposure + 1] * mintedStables) /
            (BASE_9 - xThres[indexExposure + 1]);
        // if we are on the first segment amountToPrevBreakpoint is infinite
        // so we need to set constant fees for this segment
        amountToPrevBreakpoint = indexExposure == 0
            ? type(uint256).max
            : (xThres[indexExposure] * mintedStables - BASE_9 * collateralMintedStables[indexCollat]) /
                (BASE_9 - xThres[indexExposure]);
    }

    function _updateOracles(uint256[3] memory latestOracleValue) internal {
        for (uint256 i; i < _collaterals.length; i++) {
            latestOracleValue[i] = bound(latestOracleValue[i], _minOracleValue * 10, BASE_18 / 100);
            MockChainlinkOracle(address(_oracles[i])).setLatestAnswer(int256(latestOracleValue[i]));
        }
    }

    function _randomBurnFees(
        address collateral,
        uint64[10] memory xFeeBurnUnbounded,
        int64[10] memory yFeeBurnUnbounded,
        int256 maxFee
    ) internal returns (uint64[] memory xFeeBurn, int64[] memory yFeeBurn) {
        (xFeeBurn, yFeeBurn) = _generateCurves(xFeeBurnUnbounded, yFeeBurnUnbounded, false, false, _minBurnFee, maxFee);
        vm.prank(governor);
        transmuter.setFees(collateral, xFeeBurn, yFeeBurn, false);
    }

    function _sweepBalances(address owner, address[] memory tokens) internal {
        vm.startPrank(owner);
        for (uint256 i; i < tokens.length; ++i) {
            IERC20(tokens[i]).transfer(sweeper, IERC20(tokens[i]).balanceOf(owner));
        }
        vm.stopPrank();
    }

    // function _logIssuedCollateral() internal view {
    //     for (uint256 i; i < _collaterals.length; i++) {
    //         (uint256 collateralIssued, uint256 total) = transmuter.getIssuedByCollateral(_collaterals[i]);
    //         console.log("collateralIssued ", i, collateralIssued);
    //     }
    // }

    function _getBurnOracle(uint256 amount, uint256 fromToken) internal view returns (uint256) {
        uint256 minDeviation = BASE_8;
        uint256 oracleValue;
        for (uint256 i; i < _oracles.length; i++) {
            (, int256 oracleValueTmp, , , ) = _oracles[i].latestRoundData();
            if (minDeviation > uint256(oracleValueTmp)) minDeviation = uint256(oracleValueTmp);
            if (i == fromToken) oracleValue = uint256(oracleValueTmp);
        }
        return (amount * minDeviation) / oracleValue;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        ACTIONS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _burnExactInput(
        address owner,
        address tokenOut,
        uint256 amountStable,
        uint256 estimatedAmountOut
    ) internal returns (bool burnMoreThanHad) {
        // we need to increase the balance because fees are negative and we need to transfer
        // more than what we received with the mint
        if (IERC20(tokenOut).balanceOf(address(transmuter)) < estimatedAmountOut) {
            deal(tokenOut, address(transmuter), estimatedAmountOut);
            burnMoreThanHad = true;
        }
        vm.startPrank(owner);
        transmuter.swapExactInput(
            amountStable,
            estimatedAmountOut,
            address(agToken),
            tokenOut,
            owner,
            block.timestamp * 2
        );
        vm.stopPrank();
    }

    function _burnExactOutput(
        address owner,
        address tokenOut,
        uint256 amountOut,
        uint256 estimatedStable
    ) internal returns (bool) {
        // _logIssuedCollateral();
        vm.startPrank(owner);
        (uint256 maxAmount, ) = transmuter.getIssuedByCollateral(tokenOut);
        uint256 balanceStableOwner = agToken.balanceOf(owner);
        if (estimatedStable > maxAmount) vm.expectRevert(stdError.arithmeticError);
        else if (estimatedStable > balanceStableOwner) vm.expectRevert("ERC20: burn amount exceeds balance");
        transmuter.swapExactOutput(amountOut, estimatedStable, address(agToken), tokenOut, owner, block.timestamp * 2);
        if (amountOut > maxAmount) return false;
        vm.stopPrank();
        return true;
    }
}
