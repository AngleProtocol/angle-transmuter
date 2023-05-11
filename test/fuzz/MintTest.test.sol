// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { stdError } from "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "contracts/mock/MockTokenPermit.sol";
import "../Fixture.sol";
import "../utils/FunctionUtils.sol";
import "contracts/kheops/utils/Utils.sol";
import "contracts/utils/Errors.sol";

contract MintTest is Fixture, FunctionUtils {
    using SafeERC20 for IERC20;

    uint256 internal _maxAmountWithoutDecimals = 10 ** 15;
    // making this value smaller worsen rounding and make test harder to pass.
    // Trade off between bullet proof against all oracles and all interactions
    uint256 internal _minOracleValue = 10 ** 3; // 10**(-6)

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

    function testQuoteMintExactInputSimple(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256 mintAmount,
        uint256 fromToken
    ) public {
        // let's first load the reserves of the protocol
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
            charlie,
            sweeper,
            initialAmounts,
            transferProportion
        );

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
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
            charlie,
            sweeper,
            initialAmounts,
            transferProportion
        );
        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        mintAmount = bound(mintAmount, 0, _maxTokenAmount[fromToken]);
        mintFee = int64(bound(int256(mintFee), 0, int256(BASE_9)));
        uint64[] memory xFeeMint = new uint64[](1);
        xFeeMint[0] = uint64(0);
        int64[] memory yFeeMint = new int64[](1);
        yFeeMint[0] = mintFee;
        vm.prank(governor);
        kheops.setFees(_collaterals[fromToken], xFeeMint, yFeeMint, true);

        uint256 amountOut = kheops.quoteIn(mintAmount, _collaterals[fromToken], address(agToken));

        uint256 supposedAmountOut = (_convertDecimalTo(
            mintAmount,
            IERC20Metadata(_collaterals[fromToken]).decimals(),
            18
        ) * (BASE_9 - uint64(mintFee))) / BASE_9;

        assertEq(supposedAmountOut, amountOut);
    }

    function testQuoteMintReflexivitySimple(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256[3] memory latestOracleValue,
        uint256 amountIn,
        uint256 fromToken
    ) public {
        // let's first load the reserves of the protocol
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
            charlie,
            sweeper,
            initialAmounts,
            transferProportion
        );

        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        amountIn = bound(amountIn, 0, _maxTokenAmount[fromToken]);
        uint256 amountOut = kheops.quoteIn(amountIn, _collaterals[fromToken], address(agToken));
        uint256 reflexiveAmountIn = kheops.quoteIn(amountOut, address(agToken), _collaterals[fromToken]);
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
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
            charlie,
            sweeper,
            initialAmounts,
            transferProportion
        );
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
        uint256 reflexiveAmountIn = kheops.quoteIn(amountOut, address(agToken), _collaterals[fromToken]);
        assertEq(supposedAmountOut, amountOut);
        assertEq(amountIn, reflexiveAmountIn);
    }

    function testQuoteMintExactInputReflexivityNonNullFees(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        int64 mintFee,
        uint256 amountIn,
        uint256 fromToken
    ) public {
        // let's first load the reserves of the protocol
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
            charlie,
            sweeper,
            initialAmounts,
            transferProportion
        );
        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        amountIn = bound(amountIn, 0, _maxTokenAmount[fromToken]);
        mintFee = int64(bound(int256(mintFee), 0, int256(BASE_9)));
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
        ) * (BASE_9 - uint64(mintFee))) / BASE_9;

        uint256 amountOut = kheops.quoteIn(amountIn, _collaterals[fromToken], address(agToken));
        if (uint64(mintFee) == BASE_9) vm.expectRevert();
        uint256 reflexiveAmountIn = kheops.quoteIn(amountOut, address(agToken), _collaterals[fromToken]);

        assertEq(supposedAmountOut, amountOut);
        if (uint64(mintFee) != BASE_9) assertEq(amountIn, reflexiveAmountIn);
    }

    // function testQuoteMintExactInputRandomFees(
    //     uint256[3] memory initialAmounts,
    //     uint256 transferProportion,
    //     uint256[3] memory latestOracleValue,
    //     uint64[10] memory xFeeMintUnbounded,
    //     int64[10] memory yFeeMintUnbounded
    // ) public {
    //     // let's first load the reserves of the protocol
    //     (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
    //         charlie,
    //         sweeper,
    //         initialAmounts,
    //         transferProportion
    //     );
    //     _updateOracles(latestOracleValue, mintedStables, collateralMintedStables);
    //     (uint64[] memory xFeeMint, int64[] memory yFeeMint) = _randomMintFees(xFeeMintunbounded, yFeeMintUnbounded);

    //     vm.startPrank(alice);
    //     uint256 amountBurnt = agToken.balanceOf(alice);
    //     if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
    //     (address[] memory tokens, uint256[] memory amounts) = kheops.quoteRedemptionCurve(amountBurnt);
    //     vm.stopPrank();

    //     if (mintedStables == 0) return;

    //     // compute fee at current collatRatio
    //     _assertsSizes(tokens, amounts);
    //     uint64 fee;
    //     if (collatRatio >= BASE_9) fee = uint64(yFeeRedeem[yFeeRedeem.length - 1]);
    //     else fee = uint64(Utils.piecewiseLinear(collatRatio, true, xFeeRedeem, yFeeRedeem));
    //     _assertsQuoteAmounts(collatRatio, mintedStables, amountBurnt, fee, amounts);
    // }

    // ================================== ASSERTS ==================================

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

    function _currentExposures(
        uint256 mintedStables,
        uint256[] memory collateralMintedStables
    ) internal returns (uint256[] memory exposures) {
        for (uint256 i; i < _collaterals.length; i++) {
            exposures[i] = (collateralMintedStables[i] * BASE_9) / mintedStables;
        }
    }

    function _updateOracles(uint256[3] memory latestOracleValue) internal returns (uint64 collatRatio) {
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
        (xFeeMint, yFeeMint) = _generateCurves(xFeeMintUnbounded, yFeeMintUnbounded, true);
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
}
