// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "contracts/mock/MockTokenPermit.sol";
import "../Fixture.sol";
import "../utils/FunctionUtils.sol";
import "contracts/kheops/utils/Utils.sol";
import "contracts/utils/Errors.sol";

contract BurnTest is Fixture, FunctionUtils {
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

    function testQuoteBurnExactInputSimple(
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
        uint256 amountOut = kheops.quoteIn(burnAmount, address(agToken), _collaterals[fromToken]);

        assertEq(_convertDecimalTo(burnAmount, 18, IERC20Metadata(_collaterals[fromToken]).decimals()), amountOut);
    }

    function testQuoteBurnExactInputNonNullFees(
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
        kheops.setFees(_collaterals[fromToken], xFeeBurn, yFeeBurn, false);

        uint256 amountOut = kheops.quoteIn(burnAmount, address(agToken), _collaterals[fromToken]);

        uint256 supposedAmountOut = (
            _convertDecimalTo(
                (burnAmount * (BASE_9 - uint64(burnFee))) / BASE_9,
                18,
                IERC20Metadata(_collaterals[fromToken]).decimals()
            )
        );

        assertEq(supposedAmountOut, amountOut);
    }

    function testQuoteBurnReflexivitySimple(
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

        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        burnAmount = bound(burnAmount, 0, collateralMintedStables[fromToken]);
        uint256 amountOut = kheops.quoteIn(burnAmount, address(agToken), _collaterals[fromToken]);
        uint256 reflexiveBurnAmount = kheops.quoteOut(amountOut, address(agToken), _collaterals[fromToken]);
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

    function testQuoteBurnReflexivityRandomOracle(
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
            _getBurnOracle(burnAmount, 0, fromToken),
            18,
            IERC20Metadata(_collaterals[fromToken]).decimals()
        );
        uint256 amountOut = kheops.quoteIn(burnAmount, address(agToken), _collaterals[fromToken]);
        uint256 reflexiveBurnAmount = kheops.quoteOut(amountOut, address(agToken), _collaterals[fromToken]);
        uint256 reflexiveAmountOut = kheops.quoteIn(reflexiveBurnAmount, address(agToken), _collaterals[fromToken]);
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

    function testQuoteBurnExactInputReflexivityFees(
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
        kheops.setFees(_collaterals[fromToken], xFeeBurn, yFeeBurn, false);

        uint256 supposedAmountOut = _convertDecimalTo(
            (burnAmount * (BASE_9 - uint64(burnFee))) / BASE_9,
            18,
            IERC20Metadata(_collaterals[fromToken]).decimals()
        );

        uint256 amountOut = kheops.quoteIn(burnAmount, address(agToken), _collaterals[fromToken]);
        uint256 reflexiveBurnAmount = kheops.quoteOut(amountOut, address(agToken), _collaterals[fromToken]);
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

    function testQuoteBurnExactInputReflexivityOracleFees(
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
        kheops.setFees(_collaterals[fromToken], xFeeBurn, yFeeBurn, false);

        uint256 supposedAmountOut = _convertDecimalTo(
            _getBurnOracle(burnAmount, uint64(burnFee), fromToken),
            18,
            IERC20Metadata(_collaterals[fromToken]).decimals()
        );
        uint256 amountOut = kheops.quoteIn(burnAmount, address(agToken), _collaterals[fromToken]);
        uint256 reflexiveBurnAmount = kheops.quoteOut(amountOut, address(agToken), _collaterals[fromToken]);
        if (amountOut == 0) return;

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

    function testQuoteBurnExactInputReflexivityFixPiecewiseFees(
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
        upperFees = int64(bound(int256(upperFees), 0, int256(BASE_9) - 1));
        uint64[] memory xFeeBurn = new uint64[](3);
        xFeeBurn[0] = uint64(BASE_9);
        xFeeBurn[1] = uint64((BASE_9 * 99) / 100);
        xFeeBurn[2] = uint64(BASE_9 / 2);
        int64[] memory yFeeBurn = new int64[](3);
        yFeeBurn[0] = int64(0);
        yFeeBurn[1] = int64(0);
        yFeeBurn[2] = upperFees;
        vm.prank(governor);
        kheops.setFees(_collaterals[fromToken], xFeeBurn, yFeeBurn, false);

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
            if (lowerIndex == type(uint256).max) return;

            if (lowerIndex == 0) {
                if (copyStableAmount <= amountToNextBreakpoint) {
                    collateralMintedStables[fromToken] -= copyStableAmount;
                    // first burn segment are always constant fees
                    supposedAmountOut += _convertDecimalTo(
                        _getBurnOracle(copyStableAmount, uint64(yFeeBurn[lowerIndex + 1]), fromToken),
                        18,
                        IERC20Metadata(_collaterals[fromToken]).decimals()
                    );
                    copyStableAmount = 0;
                } else {
                    collateralMintedStables[fromToken] -= amountToNextBreakpoint;
                    mintedStables -= amountToNextBreakpoint;
                    // first burn segment are always constant fees
                    supposedAmountOut += _convertDecimalTo(
                        _getBurnOracle(amountToNextBreakpoint, uint64(yFeeBurn[lowerIndex + 1]), fromToken),
                        18,
                        IERC20Metadata(_collaterals[fromToken]).decimals()
                    );
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
                    collateralMintedStables[fromToken] += copyStableAmount;

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
                    supposedAmountOut += _convertDecimalTo(
                        _getBurnOracle(copyStableAmount, uint64(uint256(midFees)), fromToken),
                        18,
                        IERC20Metadata(_collaterals[fromToken]).decimals()
                    );
                } else {
                    collateralMintedStables[fromToken] += amountToNextBreakpoint;
                    int256 midFees;
                    {
                        uint256 slope = ((uint256(uint64(yFeeBurn[lowerIndex + 1] - yFeeBurn[lowerIndex])) * BASE_36) /
                            (amountToNextBreakpoint + amountFromPrevBreakpoint));
                        int256 currentFees = yFeeBurn[lowerIndex] +
                            int256((slope * amountFromPrevBreakpoint) / BASE_36);
                        int256 endFees = yFeeBurn[lowerIndex + 1];
                        midFees = (currentFees + endFees) / 2;
                    }
                    supposedAmountOut += (amountToNextBreakpoint * (BASE_9 - uint256(midFees)));

                    // next part is just with end fees
                    supposedAmountOut +=
                        (copyStableAmount - amountToNextBreakpoint) *
                        (BASE_9 - uint64(yFeeBurn[lowerIndex + 1]));
                    supposedAmountOut += _convertDecimalTo(
                        _getBurnOracle(supposedAmountOut, uint64(BASE_9), fromToken),
                        18,
                        IERC20Metadata(_collaterals[fromToken]).decimals()
                    );
                }
            }
        }

        console.log("from token ", fromToken);
        uint256 amountOut = kheops.quoteIn(stableAmount, address(agToken), _collaterals[fromToken]);
        if (amountOut == 0) return;
        uint256 reflexiveAmountStable = kheops.quoteOut(amountOut, address(agToken), _collaterals[fromToken]);

        if (stableAmount > _minWallet) {
            // _assertApproxEqRelDecimalWithTolerance(
            //     supposedAmountOut,
            //     amountOut,
            //     amountOut,
            //     // precision of 0.1%
            //     _MAX_PERCENTAGE_DEVIATION * 100,
            //     18
            // );
            _assertApproxEqRelDecimalWithTolerance(
                reflexiveAmountStable,
                stableAmount,
                reflexiveAmountStable,
                _MAX_PERCENTAGE_DEVIATION * 100000,
                18
            );
        }
    }

    // function testQuoteMintReflexivityRandPiecewiseFees(
    //     uint256[3] memory initialAmounts,
    //     uint256 transferProportion,
    //     uint256[3] memory latestOracleValue,
    //     uint64[10] memory xFeeMintUnbounded,
    //     int64[10] memory yFeeMintUnbounded,
    //     uint256 stableAmount,
    //     uint256 fromToken
    // ) public {
    //     fromToken = bound(fromToken, 0, _collaterals.length - 1);
    //     stableAmount = bound(stableAmount, 2, _maxAmountWithoutDecimals * BASE_18);
    //     // let's first load the reserves of the protocol
    //     (uint256 mintedStables, ) = _loadReserves(charlie, sweeper, initialAmounts, transferProportion);
    //     if (mintedStables == 0) return;
    //     _updateOracles(latestOracleValue);
    //     _randomMintFees(_collaterals[fromToken], xFeeMintUnbounded, yFeeMintUnbounded);

    //     uint256 amountIn = kheops.quoteOut(stableAmount, _collaterals[fromToken], address(agToken));
    //     uint256 reflexiveAmountStable;
    //     // Sometimes this can crash by a division by 0
    //     if (amountIn == 0) reflexiveAmountStable = 0;
    //     else reflexiveAmountStable = kheops.quoteIn(amountIn, _collaterals[fromToken], address(agToken));

    //     if (stableAmount > _minWallet) {
    //         _assertApproxEqRelDecimalWithTolerance(
    //             reflexiveAmountStable,
    //             stableAmount,
    //             reflexiveAmountStable,
    //             _MAX_PERCENTAGE_DEVIATION,
    //             18
    //         );
    //     }
    // }

    // /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //                                                INDEPENDANT PATH
    // //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    // function testQuoteMintExactOutputIndependant(
    //     uint256[3] memory initialAmounts,
    //     uint256 transferProportion,
    //     uint256 splitProportion,
    //     uint256[3] memory latestOracleValue,
    //     uint64[10] memory xFeeMintUnbounded,
    //     int64[10] memory yFeeMintUnbounded,
    //     uint256 stableAmount,
    //     uint256 fromToken
    // ) public {
    //     fromToken = bound(fromToken, 0, _collaterals.length - 1);
    //     stableAmount = bound(stableAmount, 2, _maxAmountWithoutDecimals * BASE_18);
    //     // let's first load the reserves of the protocol
    //     (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
    //         charlie,
    //         sweeper,
    //         initialAmounts,
    //         transferProportion
    //     );
    //     if (mintedStables == 0) return;
    //     _updateOracles(latestOracleValue);
    //     _randomMintFees(_collaterals[fromToken], xFeeMintUnbounded, yFeeMintUnbounded);

    //     uint256 amountIn = kheops.quoteOut(stableAmount, _collaterals[fromToken], address(agToken));
    //     // uint256 reflexiveAmountStable = kheops.quoteIn(amountIn, _collaterals[fromToken], address(agToken));
    //     splitProportion = bound(splitProportion, 0, BASE_9);
    //     uint256 amountStableSplit1 = (stableAmount * splitProportion) / BASE_9;
    //     amountStableSplit1 = amountStableSplit1 == 0 ? 1 : amountStableSplit1;
    //     uint256 amountInSplit1 = kheops.quoteOut(amountStableSplit1, _collaterals[fromToken], address(agToken));
    //     // do the swap to update the system
    //     _mintExactOutput(alice, _collaterals[fromToken], amountStableSplit1, amountInSplit1);
    //     uint256 amountInSplit2 = kheops.quoteOut(
    //         stableAmount - amountStableSplit1,
    //         _collaterals[fromToken],
    //         address(agToken)
    //     );
    //     if (stableAmount > _minWallet) {
    //         _assertApproxEqRelDecimalWithTolerance(
    //             amountInSplit1 + amountInSplit2,
    //             amountIn,
    //             amountIn,
    //             // 0.01%
    //             _MAX_PERCENTAGE_DEVIATION * 100,
    //             18
    //         );
    //     }
    // }

    // function testQuoteMintExactInputIndependant(
    //     uint256[3] memory initialAmounts,
    //     uint256 transferProportion,
    //     uint256 splitProportion,
    //     uint256[3] memory latestOracleValue,
    //     uint64[10] memory xFeeMintUnbounded,
    //     int64[10] memory yFeeMintUnbounded,
    //     uint256 amountIn,
    //     uint256 fromToken
    // ) public {
    //     fromToken = bound(fromToken, 0, _collaterals.length - 1);
    //     amountIn = bound(amountIn, 2, _maxTokenAmount[fromToken]);
    //     // let's first load the reserves of the protocol
    //     (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
    //         charlie,
    //         sweeper,
    //         initialAmounts,
    //         transferProportion
    //     );
    //     if (mintedStables == 0) return;
    //     _updateOracles(latestOracleValue);
    //     _randomMintFees(_collaterals[fromToken], xFeeMintUnbounded, yFeeMintUnbounded);

    //     uint256 amountStable = kheops.quoteIn(amountIn, _collaterals[fromToken], address(agToken));
    //     // uint256 reflexiveAmountStable = kheops.quoteIn(amountIn, _collaterals[fromToken], address(agToken));
    //     splitProportion = bound(splitProportion, 0, BASE_9);
    //     uint256 amountInSplit1 = (amountIn * splitProportion) / BASE_9;
    //     amountInSplit1 = amountInSplit1 == 0 ? 1 : amountInSplit1;
    //     uint256 amountStableSplit1 = kheops.quoteIn(amountInSplit1, _collaterals[fromToken], address(agToken));
    //     // do the swap to update the system
    //     _mintExactInput(alice, _collaterals[fromToken], amountInSplit1, amountStableSplit1);
    //     uint256 amountStableSplit2 = kheops.quoteIn(
    //         amountIn - amountInSplit1,
    //         _collaterals[fromToken],
    //         address(agToken)
    //     );
    //     if (amountStable > _minWallet) {
    //         _assertApproxEqRelDecimalWithTolerance(
    //             amountStableSplit1 + amountStableSplit2,
    //             amountStable,
    //             amountStable,
    //             // 0.01%
    //             _MAX_PERCENTAGE_DEVIATION * 100,
    //             18
    //         );
    //     }
    // }

    // =================================== UTILS ===================================

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
            console.log(collateralMintedStables[i], mintedStables);
            exposures[i] = (collateralMintedStables[i] * BASE_9) / mintedStables;
        }
    }

    function _amountToPrevAndNextExposure(
        uint256 mintedStables,
        uint256 indexCollat,
        uint256[] memory collateralMintedStables,
        uint256 exposure,
        uint64[] memory xThres
    ) internal view returns (uint256 amountToPrevBreakpoint, uint256 amountToNextBreakpoint, uint256 indexExposure) {
        if (exposure <= xThres[xThres.length - 1]) return (0, 0, type(uint256).max);
        while (exposure < xThres[indexExposure]) indexExposure++;
        if (exposure > xThres[indexExposure]) indexExposure--;
        console.log("exposure ", exposure);
        console.log(indexExposure);
        amountToNextBreakpoint =
            (BASE_9 * collateralMintedStables[indexCollat] - xThres[indexExposure + 1] * mintedStables) /
            (BASE_9 - xThres[indexExposure + 1]);
        // if we are on the first degment amountToPrevBreakpoint is infinite
        // so we need to set constant fees for this segment
        amountToPrevBreakpoint = indexExposure == 0
            ? type(uint256).max
            : (xThres[indexExposure] * mintedStables - BASE_9 * collateralMintedStables[indexCollat]) /
                (BASE_9 - xThres[indexExposure]);

        console.log("amount next breakPoint", amountToNextBreakpoint);
        console.log("amount prev breakPoint", amountToPrevBreakpoint);
    }

    function _updateOracles(uint256[3] memory latestOracleValue) internal returns (uint64 collatRatio) {
        for (uint256 i; i < _collaterals.length; i++) {
            latestOracleValue[i] = bound(latestOracleValue[i], _minOracleValue, BASE_18);
            MockChainlinkOracle(address(_oracles[i])).setLatestAnswer(int256(latestOracleValue[i]));
        }
    }

    function _randomBurnFees(
        address collateral,
        uint64[10] memory xFeeBurnUnbounded,
        int64[10] memory yFeeBurnUnbounded
    ) internal returns (uint64[] memory xFeeBurn, int64[] memory yFeeBurn) {
        (xFeeBurn, yFeeBurn) = _generateCurves(xFeeBurnUnbounded, yFeeBurnUnbounded, false, false);
        vm.prank(governor);
        kheops.setFees(collateral, xFeeBurn, yFeeBurn, false);
    }

    function _sweepBalances(address owner, address[] memory tokens) internal {
        vm.startPrank(owner);
        for (uint256 i; i < tokens.length; ++i) {
            IERC20(tokens[i]).transfer(sweeper, IERC20(tokens[i]).balanceOf(owner));
        }
        vm.stopPrank();
    }

    function _logIssuedCollateral() internal view {
        for (uint256 i; i < _collaterals.length; i++) {
            (uint256 collateralIssued, uint256 total) = kheops.getIssuedByCollateral(_collaterals[i]);
            if (i == 0) console.log("Total stablecoins issued ", total);
            console.log("Stablecoins issued by ", i, collateralIssued);
        }
    }

    function _getBurnOracle(uint256 amount, uint64 fee, uint256 fromToken) internal view returns (uint256) {
        uint256 minDeviation = BASE_8;
        uint256 oracleValue;
        for (uint256 i; i < _oracles.length; i++) {
            (, int256 oracleValueTmp, , , ) = _oracles[i].latestRoundData();
            if (minDeviation > uint256(oracleValueTmp)) minDeviation = uint256(oracleValueTmp);
            if (i == fromToken) oracleValue = uint256(oracleValueTmp);
        }
        console.log("deviation ", minDeviation);
        console.log("oracleValue ", oracleValue);
        return (amount * (BASE_9 - fee) * minDeviation) / (oracleValue * BASE_9);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        ACTIONS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _burnExactInput(
        address owner,
        address tokenIn,
        uint256 amountStable,
        uint256 estimatedAmountOut
    ) internal {
        vm.startPrank(owner);
        kheops.swapExactInput(amountStable, estimatedAmountOut, address(agToken), tokenIn, owner, block.timestamp * 2);
        vm.stopPrank();
    }

    function _burnExactOutput(address owner, address tokenIn, uint256 amountOut, uint256 estimatedStable) internal {
        vm.startPrank(owner);
        kheops.swapExactInput(amountOut, estimatedStable, address(agToken), tokenIn, owner, block.timestamp * 2);
        vm.stopPrank();
    }
}
