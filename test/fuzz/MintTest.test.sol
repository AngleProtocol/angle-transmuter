// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { stdError } from "forge-std/Test.sol";

import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "../mock/MockTokenPermit.sol";
import "../Fixture.sol";
import "../utils/FunctionUtils.sol";
import "contracts/utils/Errors.sol" as Errors;

contract MintTest is Fixture, FunctionUtils {
    using SafeERC20 for IERC20;

    uint256 internal _maxAmountWithoutDecimals = 10 ** 15;
    // making this value smaller worsen rounding and make test harder to pass.
    // Trade off between bullet proof against all oracles and all interactions
    uint256 internal _minOracleValue = 10 ** 3; // 10**(-6)
    uint256 internal _minWallet = 10 ** 18; // in base 18
    uint256 internal _maxWallet = 10 ** (18 + 12); // in base 18

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

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         TESTS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testQuoteMintExactInputSimple(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256 mintAmount,
        uint256 fromToken
    ) public {
        // let's first load the reserves of the protocol
        _loadReserves(charlie, sweeper, initialAmounts, transferProportion);

        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        mintAmount = bound(mintAmount, 0, _maxTokenAmount[fromToken]);
        uint256 amountOut = kheops.quoteIn(mintAmount, _collaterals[fromToken], address(agToken));

        assertEq(_convertDecimalTo(mintAmount, IERC20Metadata(_collaterals[fromToken]).decimals(), 18), amountOut);
    }

    function testQuoteMintExactInputNonNullFees(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        int64 mintFee,
        uint256 mintAmount,
        uint256 fromToken
    ) public {
        // let's first load the reserves of the protocol
        _loadReserves(charlie, sweeper, initialAmounts, transferProportion);
        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        mintAmount = bound(mintAmount, 0, _maxTokenAmount[fromToken]);
        mintFee = int64(bound(int256(mintFee), 0, int256(BASE_12)));
        uint64[] memory xFeeMint = new uint64[](1);
        xFeeMint[0] = uint64(0);
        int64[] memory yFeeMint = new int64[](1);
        yFeeMint[0] = mintFee;
        vm.prank(governor);
        kheops.setFees(_collaterals[fromToken], xFeeMint, yFeeMint, true);

        if (mintFee == int256(BASE_12)) vm.expectRevert(Errors.InvalidSwap.selector);
        uint256 amountOut = kheops.quoteIn(mintAmount, _collaterals[fromToken], address(agToken));
        if (mintFee == int256(BASE_12)) return;

        uint256 supposedAmountOut = ((_convertDecimalTo(
            mintAmount,
            IERC20Metadata(_collaterals[fromToken]).decimals(),
            18
        ) * BASE_9) / (BASE_9 + uint64(mintFee)));

        assertEq(supposedAmountOut, amountOut);
    }

    function testQuoteMintReflexivitySimple(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256 amountIn,
        uint256 fromToken
    ) public {
        // let's first load the reserves of the protocol
        _loadReserves(charlie, sweeper, initialAmounts, transferProportion);

        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        amountIn = bound(amountIn, 0, _maxTokenAmount[fromToken]);
        uint256 amountOut = kheops.quoteIn(amountIn, _collaterals[fromToken], address(agToken));
        uint256 reflexiveAmountIn = kheops.quoteOut(amountOut, _collaterals[fromToken], address(agToken));
        assertEq(_convertDecimalTo(amountIn, IERC20Metadata(_collaterals[fromToken]).decimals(), 18), amountOut);
        assertEq(amountIn, reflexiveAmountIn);
    }

    function testQuoteMintReflexivityRandomOracle(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256[3] memory latestOracleValue,
        uint256 amountIn,
        uint256 fromToken
    ) public {
        // let's first load the reserves of the protocol
        _loadReserves(charlie, sweeper, initialAmounts, transferProportion);
        _updateOracles(latestOracleValue);

        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        amountIn = bound(amountIn, 0, _maxTokenAmount[fromToken]);
        (, int256 oracleValue, , , ) = _oracles[fromToken].latestRoundData();
        uint256 supposedAmountOut = (_convertDecimalTo(
            amountIn,
            IERC20Metadata(_collaterals[fromToken]).decimals(),
            18
        ) * (uint256(oracleValue) > BASE_8 ? BASE_8 : uint256(oracleValue))) / BASE_8;
        uint256 amountOut = kheops.quoteIn(amountIn, _collaterals[fromToken], address(agToken));
        uint256 reflexiveAmountIn = kheops.quoteOut(amountOut, _collaterals[fromToken], address(agToken));
        assertEq(supposedAmountOut, amountOut);
        if (amountOut > _minWallet) {
            _assertApproxEqRelDecimalWithTolerance(
                amountIn,
                reflexiveAmountIn,
                amountIn,
                _MAX_PERCENTAGE_DEVIATION,
                IERC20Metadata(_collaterals[fromToken]).decimals()
            );
        }
    }

    function testQuoteMintExactInputReflexivityFees(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        int64 mintFee,
        uint256 amountIn,
        uint256 fromToken
    ) public {
        // let's first load the reserves of the protocol
        _loadReserves(charlie, sweeper, initialAmounts, transferProportion);
        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        amountIn = bound(amountIn, 0, _maxTokenAmount[fromToken]);
        mintFee = int64(bound(int256(mintFee), 0, int256(BASE_12)));
        uint64[] memory xFeeMint = new uint64[](1);
        xFeeMint[0] = uint64(0);
        int64[] memory yFeeMint = new int64[](1);
        yFeeMint[0] = mintFee;
        vm.prank(governor);
        kheops.setFees(_collaterals[fromToken], xFeeMint, yFeeMint, true);

        uint256 supposedAmountOut = (_convertDecimalTo(
            amountIn,
            IERC20Metadata(_collaterals[fromToken]).decimals(),
            18
        ) * BASE_9) / (BASE_9 + uint64(mintFee));

        if (uint64(mintFee) == BASE_12) vm.expectRevert(Errors.InvalidSwap.selector);
        uint256 amountOut = kheops.quoteIn(amountIn, _collaterals[fromToken], address(agToken));
        if (uint64(mintFee) == BASE_12) vm.expectRevert(Errors.InvalidSwap.selector);
        uint256 reflexiveAmountIn = kheops.quoteOut(amountOut, _collaterals[fromToken], address(agToken));
        if (uint64(mintFee) == BASE_12) return;

        assertEq(supposedAmountOut, amountOut);
        if (amountOut > _minWallet) {
            _assertApproxEqRelDecimalWithTolerance(
                amountIn,
                reflexiveAmountIn,
                amountIn,
                _MAX_PERCENTAGE_DEVIATION,
                IERC20Metadata(_collaterals[fromToken]).decimals()
            );
        }
    }

    function testQuoteMintExactInputReflexivityOracleFees(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256[3] memory latestOracleValue,
        int64 mintFee,
        uint256 amountIn,
        uint256 fromToken
    ) public {
        // let's first load the reserves of the protocol
        _loadReserves(charlie, sweeper, initialAmounts, transferProportion);
        _updateOracles(latestOracleValue);

        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        amountIn = bound(amountIn, 0, _maxTokenAmount[fromToken]);
        mintFee = int64(bound(int256(mintFee), 0, int256(BASE_12)));
        uint64[] memory xFeeMint = new uint64[](1);
        xFeeMint[0] = uint64(0);
        int64[] memory yFeeMint = new int64[](1);
        yFeeMint[0] = mintFee;
        vm.prank(governor);
        kheops.setFees(_collaterals[fromToken], xFeeMint, yFeeMint, true);

        (, int256 oracleValue, , , ) = _oracles[fromToken].latestRoundData();
        uint256 supposedAmountOut = (((_convertDecimalTo(
            amountIn,
            IERC20Metadata(_collaterals[fromToken]).decimals(),
            18
        ) * BASE_9) / (BASE_9 + uint64(mintFee))) * (uint256(oracleValue) > BASE_8 ? BASE_8 : uint256(oracleValue))) /
            BASE_8;

        if (uint64(mintFee) == BASE_12) vm.expectRevert(Errors.InvalidSwap.selector);
        uint256 amountOut = kheops.quoteIn(amountIn, _collaterals[fromToken], address(agToken));
        if (uint64(mintFee) == BASE_12) vm.expectRevert(Errors.InvalidSwap.selector);
        uint256 reflexiveAmountIn = kheops.quoteOut(amountOut, _collaterals[fromToken], address(agToken));
        if (uint64(mintFee) == BASE_12) return;

        assertApproxEqAbs(supposedAmountOut, amountOut, 1 wei);
        if (amountOut > _minWallet) {
            _assertApproxEqRelDecimalWithTolerance(
                amountIn,
                reflexiveAmountIn,
                amountIn,
                _MAX_PERCENTAGE_DEVIATION,
                IERC20Metadata(_collaterals[fromToken]).decimals()
            );
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                 PIECEWISE LINEAR FEES                                              
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testQuoteMintExactOutputReflexivityFixPiecewiseFees(
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
        stableAmount = bound(stableAmount, 1, _maxAmountWithoutDecimals * BASE_18);
        upperFees = int64(bound(int256(upperFees), 0, int256(BASE_12) - 1));
        uint64[] memory xFeeMint = new uint64[](2);
        xFeeMint[0] = uint64(0);
        xFeeMint[1] = uint64(BASE_9 / 2);
        int64[] memory yFeeMint = new int64[](2);
        yFeeMint[0] = int64(0);
        yFeeMint[1] = upperFees;
        vm.prank(governor);
        kheops.setFees(_collaterals[fromToken], xFeeMint, yFeeMint, true);

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
                xFeeMint
            );
        // this is to handle in easy tests
        if (lowerIndex == type(uint256).max) return;

        uint256 supposedAmountIn;
        if (stableAmount <= amountToNextBreakpoint) {
            collateralMintedStables[fromToken] += stableAmount;

            int256 midFees;
            {
                int256 currentFees;
                uint256 slope = (uint256(uint64(yFeeMint[lowerIndex + 1] - yFeeMint[lowerIndex])) * BASE_36) /
                    (amountToNextBreakpoint + amountFromPrevBreakpoint);
                currentFees = yFeeMint[lowerIndex] + int256((slope * amountFromPrevBreakpoint) / BASE_36);
                int256 endFees = yFeeMint[lowerIndex] +
                    int256((slope * (amountFromPrevBreakpoint + stableAmount)) / BASE_36);
                midFees = (currentFees + endFees) / 2;
            }
            supposedAmountIn = (stableAmount * (BASE_9 + uint256(midFees)));
            uint256 mintOracleValue;
            {
                (, int256 oracleValue, , , ) = _oracles[fromToken].latestRoundData();
                mintOracleValue = uint256(oracleValue) > BASE_8 ? BASE_8 : uint256(oracleValue);
            }
            supposedAmountIn = _convertDecimalTo(
                supposedAmountIn / (10 * mintOracleValue),
                18,
                IERC20Metadata(_collaterals[fromToken]).decimals()
            );
        } else {
            collateralMintedStables[fromToken] += amountToNextBreakpoint;
            int256 midFees;
            {
                uint256 slope = ((uint256(uint64(yFeeMint[lowerIndex + 1] - yFeeMint[lowerIndex])) * BASE_36) /
                    (amountToNextBreakpoint + amountFromPrevBreakpoint));
                int256 currentFees = yFeeMint[lowerIndex] + int256((slope * amountFromPrevBreakpoint) / BASE_36);
                int256 endFees = yFeeMint[lowerIndex + 1];
                midFees = (currentFees + endFees) / 2;
            }
            supposedAmountIn = (amountToNextBreakpoint * (BASE_9 + uint256(midFees)));

            // next part is just with end fees
            supposedAmountIn += (stableAmount - amountToNextBreakpoint) * (BASE_9 + uint64(yFeeMint[lowerIndex + 1]));
            uint256 mintOracleValue;
            {
                (, int256 oracleValue, , , ) = _oracles[fromToken].latestRoundData();
                mintOracleValue = uint256(oracleValue) > BASE_8 ? BASE_8 : uint256(oracleValue);
            }
            supposedAmountIn = _convertDecimalTo(
                supposedAmountIn / (10 * mintOracleValue),
                18,
                IERC20Metadata(_collaterals[fromToken]).decimals()
            );
        }

        uint256 amountIn = kheops.quoteOut(stableAmount, _collaterals[fromToken], address(agToken));
        uint256 reflexiveAmountStable = kheops.quoteIn(amountIn, _collaterals[fromToken], address(agToken));

        if (stableAmount > _minWallet) {
            _assertApproxEqRelDecimalWithTolerance(
                supposedAmountIn,
                amountIn,
                amountIn,
                // precision of 0.1%
                _MAX_PERCENTAGE_DEVIATION * 100,
                18
            );
            _assertApproxEqRelDecimalWithTolerance(
                reflexiveAmountStable,
                stableAmount,
                reflexiveAmountStable,
                _MAX_PERCENTAGE_DEVIATION,
                18
            );
        }
    }

    function testQuoteMintReflexivityRandPiecewiseFees(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256[3] memory latestOracleValue,
        uint64[10] memory xFeeMintUnbounded,
        int64[10] memory yFeeMintUnbounded,
        uint256 stableAmount,
        uint256 fromToken
    ) public {
        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        stableAmount = bound(stableAmount, 2, _maxAmountWithoutDecimals * BASE_18);
        // let's first load the reserves of the protocol
        (uint256 mintedStables, ) = _loadReserves(charlie, sweeper, initialAmounts, transferProportion);
        if (mintedStables == 0) return;
        _updateOracles(latestOracleValue);
        _randomMintFees(_collaterals[fromToken], xFeeMintUnbounded, yFeeMintUnbounded);

        uint256 amountIn = kheops.quoteOut(stableAmount, _collaterals[fromToken], address(agToken));
        uint256 reflexiveAmountStable;
        // Sometimes this can crash by a division by 0
        if (amountIn == 0) reflexiveAmountStable = 0;
        else reflexiveAmountStable = kheops.quoteIn(amountIn, _collaterals[fromToken], address(agToken));

        if (stableAmount > _minWallet) {
            _assertApproxEqRelDecimalWithTolerance(
                reflexiveAmountStable,
                stableAmount,
                reflexiveAmountStable,
                _MAX_PERCENTAGE_DEVIATION,
                18
            );
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                   INDEPENDANT PATH                                                 
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testQuoteMintExactOutputIndependant(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256 splitProportion,
        uint256[3] memory latestOracleValue,
        uint64[10] memory xFeeMintUnbounded,
        int64[10] memory yFeeMintUnbounded,
        uint256 stableAmount,
        uint256 fromToken
    ) public {
        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        stableAmount = bound(stableAmount, 2, _maxAmountWithoutDecimals * BASE_18);
        // let's first load the reserves of the protocol
        (uint256 mintedStables, ) = _loadReserves(charlie, sweeper, initialAmounts, transferProportion);
        if (mintedStables == 0) return;
        _updateOracles(latestOracleValue);
        _randomMintFees(_collaterals[fromToken], xFeeMintUnbounded, yFeeMintUnbounded);

        uint256 amountIn = kheops.quoteOut(stableAmount, _collaterals[fromToken], address(agToken));
        // uint256 reflexiveAmountStable = kheops.quoteIn(amountIn, _collaterals[fromToken], address(agToken));
        splitProportion = bound(splitProportion, 0, BASE_9);
        uint256 amountStableSplit1 = (stableAmount * splitProportion) / BASE_9;
        amountStableSplit1 = amountStableSplit1 == 0 ? 1 : amountStableSplit1;
        uint256 amountInSplit1 = kheops.quoteOut(amountStableSplit1, _collaterals[fromToken], address(agToken));
        // do the swap to update the system
        _mintExactOutput(alice, _collaterals[fromToken], amountStableSplit1, amountInSplit1);
        uint256 amountInSplit2 = kheops.quoteOut(
            stableAmount - amountStableSplit1,
            _collaterals[fromToken],
            address(agToken)
        );
        if (stableAmount > _minWallet) {
            _assertApproxEqRelDecimalWithTolerance(
                amountInSplit1 + amountInSplit2,
                amountIn,
                amountIn,
                // 0.01%
                _MAX_PERCENTAGE_DEVIATION * 100,
                18
            );
        }
    }

    function testQuoteMintExactInputIndependant(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256 splitProportion,
        uint256[3] memory latestOracleValue,
        uint64[10] memory xFeeMintUnbounded,
        int64[10] memory yFeeMintUnbounded,
        uint256 amountIn,
        uint256 fromToken
    ) public {
        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        amountIn = bound(amountIn, 2, _maxTokenAmount[fromToken]);
        // let's first load the reserves of the protocol
        (uint256 mintedStables, ) = _loadReserves(charlie, sweeper, initialAmounts, transferProportion);
        if (mintedStables == 0) return;
        _updateOracles(latestOracleValue);
        _randomMintFees(_collaterals[fromToken], xFeeMintUnbounded, yFeeMintUnbounded);

        uint256 amountStable = kheops.quoteIn(amountIn, _collaterals[fromToken], address(agToken));
        // uint256 reflexiveAmountStable = kheops.quoteIn(amountIn, _collaterals[fromToken], address(agToken));
        splitProportion = bound(splitProportion, 0, BASE_9);
        uint256 amountInSplit1 = (amountIn * splitProportion) / BASE_9;
        amountInSplit1 = amountInSplit1 == 0 ? 1 : amountInSplit1;
        uint256 amountStableSplit1 = kheops.quoteIn(amountInSplit1, _collaterals[fromToken], address(agToken));
        // do the swap to update the system
        _mintExactInput(alice, _collaterals[fromToken], amountInSplit1, amountStableSplit1);
        uint256 amountStableSplit2 = kheops.quoteIn(
            amountIn - amountInSplit1,
            _collaterals[fromToken],
            address(agToken)
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
                                                         MINT                                                       
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testMintExactOutput(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256[3] memory latestOracleValue,
        uint64[10] memory xFeeMintUnbounded,
        int64[10] memory yFeeMintUnbounded,
        uint256 stableAmount,
        uint256 fromToken
    ) public {
        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        stableAmount = bound(stableAmount, 2, _maxAmountWithoutDecimals * BASE_18);
        // let's first load the reserves of the protocol
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
            charlie,
            sweeper,
            initialAmounts,
            transferProportion
        );
        if (mintedStables == 0) return;
        _updateOracles(latestOracleValue);
        _randomMintFees(_collaterals[fromToken], xFeeMintUnbounded, yFeeMintUnbounded);

        uint256 prevBalanceStable = agToken.balanceOf(alice);
        uint256 prevKheopsCollat = IERC20(_collaterals[fromToken]).balanceOf(address(kheops));

        uint256 amountIn = kheops.quoteOut(stableAmount, _collaterals[fromToken], address(agToken));
        _mintExactOutput(alice, _collaterals[fromToken], stableAmount, amountIn);

        uint256 balanceStable = agToken.balanceOf(alice);

        assertEq(balanceStable, prevBalanceStable + stableAmount);
        assertEq(IERC20(_collaterals[fromToken]).balanceOf(alice), 0);
        assertEq(IERC20(_collaterals[fromToken]).balanceOf(address(kheops)), prevKheopsCollat + amountIn);

        (uint256 newStableAmountCollat, uint256 newStableAmount) = kheops.getIssuedByCollateral(
            _collaterals[fromToken]
        );

        assertApproxEqAbs(newStableAmountCollat, collateralMintedStables[fromToken] + stableAmount, 1 wei);
        assertApproxEqAbs(newStableAmount, mintedStables + stableAmount, 1 wei);
    }

    function testMintExactInput(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256[3] memory latestOracleValue,
        uint64[10] memory xFeeMintUnbounded,
        int64[10] memory yFeeMintUnbounded,
        uint256 amountIn,
        uint256 fromToken
    ) public {
        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        amountIn = bound(amountIn, 2, _maxTokenAmount[fromToken]);
        // let's first load the reserves of the protocol
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
            charlie,
            sweeper,
            initialAmounts,
            transferProportion
        );
        if (mintedStables == 0) return;
        _updateOracles(latestOracleValue);
        _randomMintFees(_collaterals[fromToken], xFeeMintUnbounded, yFeeMintUnbounded);

        uint256 prevBalanceStable = agToken.balanceOf(alice);
        uint256 prevKheopsCollat = IERC20(_collaterals[fromToken]).balanceOf(address(kheops));

        // we could end up with fees = 100% making the quote revert
        try kheops.quoteIn(amountIn, _collaterals[fromToken], address(agToken)) returns (uint256 stableAmount) {
            _mintExactInput(alice, _collaterals[fromToken], amountIn, stableAmount);

            uint256 balanceStable = agToken.balanceOf(alice);

            assertEq(balanceStable, prevBalanceStable + stableAmount);
            assertEq(IERC20(_collaterals[fromToken]).balanceOf(alice), 0);
            assertEq(IERC20(_collaterals[fromToken]).balanceOf(address(kheops)), prevKheopsCollat + amountIn);

            (uint256 newStableAmountCollat, uint256 newStableAmount) = kheops.getIssuedByCollateral(
                _collaterals[fromToken]
            );

            assertApproxEqAbs(newStableAmountCollat, collateralMintedStables[fromToken] + stableAmount, 1 wei);
            assertApproxEqAbs(newStableAmount, mintedStables + stableAmount, 1 wei);
        } catch {}
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
            IERC20(_collaterals[i]).approve(address(kheops), initialAmounts[i]);

            collateralMintedStables[i] = kheops.swapExactInput(
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
        agToken.transfer(receiver, (mintedStables * transferProportion) / BASE_9);
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
        if (exposure >= xThres[xThres.length - 1]) return (0, 0, type(uint256).max);
        while (exposure > xThres[indexExposure]) {
            indexExposure++;
        }
        if (exposure < xThres[indexExposure]) indexExposure--;
        amountToNextBreakpoint =
            (xThres[indexExposure + 1] * mintedStables - BASE_9 * collateralMintedStables[indexCollat]) /
            (BASE_9 - xThres[indexExposure + 1]);
        amountToPrevBreakpoint =
            (BASE_9 * collateralMintedStables[indexCollat] - xThres[indexExposure] * mintedStables) /
            (BASE_9 - xThres[indexExposure]);
    }

    function _updateOracles(uint256[3] memory latestOracleValue) internal {
        for (uint256 i; i < _collaterals.length; i++) {
            latestOracleValue[i] = bound(latestOracleValue[i], _minOracleValue, BASE_18);
            MockChainlinkOracle(address(_oracles[i])).setLatestAnswer(int256(latestOracleValue[i]));
        }
    }

    function _randomMintFees(
        address collateral,
        uint64[10] memory xFeeMintUnbounded,
        int64[10] memory yFeeMintUnbounded
    ) internal returns (uint64[] memory xFeeMint, int64[] memory yFeeMint) {
        (xFeeMint, yFeeMint) = _generateCurves(xFeeMintUnbounded, yFeeMintUnbounded, true, true, 0);
        vm.prank(governor);
        kheops.setFees(collateral, xFeeMint, yFeeMint, true);
    }

    function _sweepBalances(address owner, address[] memory tokens) internal {
        vm.startPrank(owner);
        for (uint256 i; i < tokens.length; ++i) {
            IERC20(tokens[i]).transfer(sweeper, IERC20(tokens[i]).balanceOf(owner));
        }
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        ACTIONS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _mintExactOutput(
        address owner,
        address tokenIn,
        uint256 amountStable,
        uint256 estimatedAmountIn
    ) internal {
        vm.startPrank(owner);
        deal(tokenIn, owner, estimatedAmountIn);
        IERC20(tokenIn).approve(address(kheops), type(uint256).max);
        kheops.swapExactOutput(amountStable, estimatedAmountIn, tokenIn, address(agToken), owner, block.timestamp * 2);
        vm.stopPrank();
    }

    function _mintExactInput(address owner, address tokenIn, uint256 amountIn, uint256 estimatedStable) internal {
        vm.startPrank(owner);
        deal(tokenIn, owner, amountIn);
        IERC20(tokenIn).approve(address(kheops), type(uint256).max);
        kheops.swapExactInput(amountIn, estimatedStable, tokenIn, address(agToken), owner, block.timestamp * 2);
        vm.stopPrank();
    }
}
