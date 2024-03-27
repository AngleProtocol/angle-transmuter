// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";

import "contracts/transmuter/Storage.sol" as Storage;
import "contracts/utils/Errors.sol" as Errors;

import "../Fixture.sol";
import { IERC20Metadata } from "../mock/MockTokenPermit.sol";
import "../utils/FunctionUtils.sol";

contract SwapTest is Fixture, FunctionUtils {
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
                                                        REVERTS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_InvalidTokens(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256[3] memory latestOracleValue,
        uint256 amount,
        uint256 fromToken
    ) public {
        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        amount = bound(amount, 2, _maxAmountWithoutDecimals * 10 ** 18);
        // let's first load the reserves of the protocol
        (uint256 mintedStables, ) = _loadReserves(charlie, sweeper, initialAmounts, transferProportion);
        if (mintedStables == 0) return;
        _updateOracles(latestOracleValue);

        address testToken1 = address(new MockTokenPermit("TST1", "TST1", 11));
        address testToken2 = address(new MockTokenPermit("TST2", "TST2", 15));

        vm.startPrank(alice);
        vm.expectRevert(Errors.InvalidTokens.selector);
        transmuter.swapExactOutput(amount, 0, testToken1, testToken2, alice, block.timestamp * 2);
        vm.expectRevert(Errors.InvalidTokens.selector);
        transmuter.swapExactInput(amount, 0, testToken1, testToken2, alice, block.timestamp * 2);
        vm.expectRevert(Errors.InvalidTokens.selector);
        transmuter.swapExactOutput(amount, 0, testToken2, testToken1, alice, block.timestamp * 2);
        vm.expectRevert(Errors.InvalidTokens.selector);
        transmuter.swapExactInput(amount, 0, testToken2, testToken1, alice, block.timestamp * 2);

        vm.expectRevert(Errors.Paused.selector);
        transmuter.swapExactInput(amount, 0, testToken2, address(agToken), alice, block.timestamp * 2);
        vm.expectRevert(Errors.Paused.selector);
        transmuter.swapExactInput(amount, 0, address(agToken), testToken2, alice, block.timestamp * 2);
        vm.expectRevert(Errors.Paused.selector);
        transmuter.swapExactInput(amount, 0, testToken1, address(agToken), alice, block.timestamp * 2);
        vm.expectRevert(Errors.Paused.selector);
        transmuter.swapExactInput(amount, 0, address(agToken), testToken1, alice, block.timestamp * 2);
        vm.expectRevert(Errors.Paused.selector);
        transmuter.swapExactOutput(amount, 0, testToken2, address(agToken), alice, block.timestamp * 2);
        vm.expectRevert(Errors.Paused.selector);
        transmuter.swapExactOutput(amount, 0, address(agToken), testToken2, alice, block.timestamp * 2);
        vm.expectRevert(Errors.Paused.selector);
        transmuter.swapExactOutput(amount, 0, testToken1, address(agToken), alice, block.timestamp * 2);
        vm.expectRevert(Errors.Paused.selector);
        transmuter.swapExactOutput(amount, 0, address(agToken), testToken1, alice, block.timestamp * 2);

        vm.expectRevert(Errors.InvalidTokens.selector);
        transmuter.swapExactInput(amount, 0, testToken2, address(eurA), alice, block.timestamp * 2);
        vm.expectRevert(Errors.InvalidTokens.selector);
        transmuter.swapExactInput(amount, 0, address(eurA), testToken2, alice, block.timestamp * 2);
        vm.expectRevert(Errors.InvalidTokens.selector);
        transmuter.swapExactInput(amount, 0, testToken1, address(eurA), alice, block.timestamp * 2);
        vm.expectRevert(Errors.InvalidTokens.selector);
        transmuter.swapExactInput(amount, 0, address(eurA), testToken1, alice, block.timestamp * 2);
        vm.expectRevert(Errors.InvalidTokens.selector);
        transmuter.swapExactOutput(amount, 0, testToken2, address(eurA), alice, block.timestamp * 2);
        vm.expectRevert(Errors.InvalidTokens.selector);
        transmuter.swapExactOutput(amount, 0, address(eurA), testToken2, alice, block.timestamp * 2);
        vm.expectRevert(Errors.InvalidTokens.selector);
        transmuter.swapExactOutput(amount, 0, testToken1, address(eurA), alice, block.timestamp * 2);
        vm.expectRevert(Errors.InvalidTokens.selector);
        transmuter.swapExactOutput(amount, 0, address(eurA), testToken1, alice, block.timestamp * 2);
        vm.stopPrank();
    }

    function test_RevertWhen_Paused(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256[3] memory latestOracleValue,
        uint256 amount,
        uint256 fromToken
    ) public {
        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        amount = bound(amount, 2, _maxAmountWithoutDecimals * 10 ** 18);
        // let's first load the reserves of the protocol
        (uint256 mintedStables, ) = _loadReserves(charlie, sweeper, initialAmounts, transferProportion);
        if (mintedStables == 0) return;
        _updateOracles(latestOracleValue);

        vm.startPrank(governor);
        transmuter.togglePause(_collaterals[fromToken], Storage.ActionType.Mint);
        transmuter.togglePause(_collaterals[fromToken], Storage.ActionType.Burn);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(Errors.Paused.selector);
        transmuter.swapExactOutput(amount, 0, _collaterals[fromToken], address(agToken), alice, block.timestamp * 2);
        vm.expectRevert(Errors.Paused.selector);
        transmuter.swapExactInput(amount, 0, _collaterals[fromToken], address(agToken), alice, block.timestamp * 2);
        vm.stopPrank();
    }

    function test_RevertWhen_Paused2(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256[3] memory latestOracleValue,
        uint256 amount,
        uint256 fromToken
    ) public {
        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        amount = bound(amount, 2, _maxAmountWithoutDecimals * 10 ** 18);
        // let's first load the reserves of the protocol
        (uint256 mintedStables, ) = _loadReserves(charlie, sweeper, initialAmounts, transferProportion);
        if (mintedStables == 0) return;
        _updateOracles(latestOracleValue);

        vm.startPrank(governor);
        transmuter.togglePause(_collaterals[fromToken], Storage.ActionType.Mint);
        transmuter.togglePause(_collaterals[fromToken], Storage.ActionType.Burn);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(Errors.Paused.selector);
        transmuter.swapExactOutput(amount, 0, address(agToken), _collaterals[fromToken], alice, block.timestamp * 2);
        vm.expectRevert(Errors.Paused.selector);
        transmuter.swapExactInput(amount, 0, address(agToken), _collaterals[fromToken], alice, block.timestamp * 2);
        vm.stopPrank();
    }

    function test_RevertWhen_Slippage(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256[3] memory latestOracleValue,
        uint256 stableAmount,
        uint256 burnAmount,
        uint256 fromTokenMint,
        uint256 fromTokenBurn
    ) public {
        fromTokenMint = bound(fromTokenMint, 0, _collaterals.length - 1);
        fromTokenBurn = bound(fromTokenBurn, 0, _collaterals.length - 1);
        stableAmount = bound(stableAmount, 2, _maxAmountWithoutDecimals * BASE_18);
        // let's first load the reserves of the protocol
        (, uint256[] memory collateralMintedStables) = _loadReserves(
            charlie,
            sweeper,
            initialAmounts,
            transferProportion
        );
        burnAmount = bound(
            burnAmount,
            0,
            agToken.balanceOf(charlie) > collateralMintedStables[fromTokenBurn]
                ? collateralMintedStables[fromTokenBurn]
                : agToken.balanceOf(charlie)
        );
        if (burnAmount == 0) return;
        _updateOracles(latestOracleValue);

        uint256 amountIn = transmuter.quoteOut(stableAmount, _collaterals[fromTokenMint], address(agToken));
        uint256 amountOut = transmuter.quoteIn(burnAmount, address(agToken), _collaterals[fromTokenBurn]);
        uint256 reflexiveBurnAmount = transmuter.quoteOut(amountOut, address(agToken), _collaterals[fromTokenBurn]);

        vm.startPrank(alice);
        if (amountIn > 0) {
            vm.expectRevert(Errors.TooBigAmountIn.selector);
            transmuter.swapExactOutput(
                stableAmount,
                amountIn - 1,
                _collaterals[fromTokenMint],
                address(agToken),
                alice,
                block.timestamp * 2
            );
        }
        if (stableAmount > 0) {
            vm.expectRevert(Errors.TooSmallAmountOut.selector);
            transmuter.swapExactInput(
                amountIn,
                stableAmount + 1,
                _collaterals[fromTokenMint],
                address(agToken),
                alice,
                block.timestamp * 2
            );
        }
        vm.stopPrank();

        vm.startPrank(charlie);
        if (amountOut > 0 && burnAmount > 0) {
            vm.expectRevert(Errors.TooBigAmountIn.selector);
            transmuter.swapExactOutput(
                amountOut,
                reflexiveBurnAmount - 1,
                address(agToken),
                _collaterals[fromTokenBurn],
                alice,
                block.timestamp * 2
            );
        }
        if (burnAmount > 0) {
            vm.expectRevert(Errors.TooSmallAmountOut.selector);
            transmuter.swapExactInput(
                burnAmount,
                amountOut + 1,
                address(agToken),
                _collaterals[fromTokenBurn],
                alice,
                block.timestamp * 2
            );
        }
        vm.stopPrank();
    }

    function test_RevertWhen_Deadline(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256[3] memory latestOracleValue,
        uint256 elapseTimestamp,
        uint256 stableAmount,
        uint256 burnAmount,
        uint256 fromTokenMint,
        uint256 fromTokenBurn
    ) public {
        // fr the stale periods in Chainlink
        elapseTimestamp = bound(elapseTimestamp, 1, 1 hours - 1);
        fromTokenMint = bound(fromTokenMint, 0, _collaterals.length - 1);
        fromTokenBurn = bound(fromTokenBurn, 0, _collaterals.length - 1);
        stableAmount = bound(stableAmount, 2, _maxAmountWithoutDecimals * BASE_18);
        // let's first load the reserves of the protocol
        (, uint256[] memory collateralMintedStables) = _loadReserves(
            charlie,
            sweeper,
            initialAmounts,
            transferProportion
        );
        burnAmount = bound(
            burnAmount,
            0,
            agToken.balanceOf(charlie) > collateralMintedStables[fromTokenBurn]
                ? collateralMintedStables[fromTokenBurn]
                : agToken.balanceOf(charlie)
        );
        if (burnAmount == 0) return;
        _updateOracles(latestOracleValue);

        uint256 amountIn = transmuter.quoteOut(stableAmount, _collaterals[fromTokenMint], address(agToken));
        uint256 amountOut = transmuter.quoteIn(burnAmount, address(agToken), _collaterals[fromTokenBurn]);
        uint256 curTimestamp = block.timestamp;
        skip(elapseTimestamp);

        vm.startPrank(alice);
        if (amountIn > 0) {
            vm.expectRevert(Errors.TooLate.selector);
            transmuter.swapExactOutput(
                stableAmount,
                amountIn,
                _collaterals[fromTokenMint],
                address(agToken),
                alice,
                curTimestamp
            );
        }
        vm.expectRevert(Errors.TooLate.selector);
        transmuter.swapExactInput(amountIn, 0, _collaterals[fromTokenMint], address(agToken), alice, curTimestamp);
        vm.stopPrank();

        vm.startPrank(charlie);
        vm.expectRevert(Errors.TooLate.selector);
        transmuter.swapExactOutput(
            amountOut,
            burnAmount,
            address(agToken),
            _collaterals[fromTokenBurn],
            alice,
            curTimestamp
        );
        if (burnAmount > 0) {
            vm.expectRevert(Errors.TooLate.selector);
            transmuter.swapExactInput(
                burnAmount,
                amountOut,
                address(agToken),
                _collaterals[fromTokenBurn],
                alice,
                curTimestamp
            );
        }
        vm.stopPrank();
    }

    // TODO Tests to check that you can't arb directly the system mint with one asset and burn with another and make a profit
    function testFuzz_ArbitrageSwap(
        uint256[3] memory initialAmounts,
        uint256[3] memory latestOracleValue,
        uint128[6] memory userAndBurnFirewall,
        uint256 stableAmount,
        uint256 fromToken,
        uint256 toToken
    ) public {
        _updateOracleFirewalls(userAndBurnFirewall);
        // let's first load the reserves of the protocol
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
            charlie,
            sweeper,
            initialAmounts,
            0
        );
        if (mintedStables == 0) return;
        _updateOracles(latestOracleValue);

        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        toToken = bound(toToken, 0, _collaterals.length - 1);
        stableAmount = bound(stableAmount, 0, collateralMintedStables[fromToken]);
        if (stableAmount == 0) return;

        (uint256 prevCollatRatio, ) = transmuter.getCollateralRatio();
        vm.startPrank(alice);
        {
            uint256 estimatedAmount = transmuter.quoteOut(stableAmount, _collaterals[fromToken], address(agToken));
            deal(address(_collaterals[fromToken]), alice, estimatedAmount);
            IERC20(_collaterals[fromToken]).approve(address(transmuter), estimatedAmount);
        }
        uint256 amountInSpent = transmuter.swapExactOutput(
            stableAmount,
            type(uint256).max,
            _collaterals[fromToken],
            address(agToken),
            alice,
            block.timestamp + 1000
        );
        if (amountInSpent == 0) return;
        {
            try transmuter.quoteIn(stableAmount, address(agToken), _collaterals[toToken]) returns (
                uint256 amountOutSupposed
            ) {
                if (amountOutSupposed == 0) return;
                if (
                    amountOutSupposed > IERC20(_collaterals[toToken]).balanceOf(address(transmuter)) ||
                    stableAmount > collateralMintedStables[toToken]
                ) vm.expectRevert();
            } catch {
                return; // Tryong to swap for a collateral that isn't deep enough
            }
        }
        uint256 amountOutReceived = transmuter.swapExactInput(
            stableAmount,
            0,
            address(agToken),
            _collaterals[toToken],
            alice,
            block.timestamp + 1000
        );

        {
            (, , , , uint256 oracleTo) = transmuter.getOracleValues(_collaterals[toToken]);
            oracleTo = _userOracleProtection(BASE_18, oracleTo, userAndBurnFirewall[toToken]);
            (, , , , uint256 oracleFrom) = transmuter.getOracleValues(_collaterals[fromToken]);
            oracleFrom = _userOracleProtection(BASE_18, oracleFrom, userAndBurnFirewall[fromToken]);
            assertLe(
                amountOutReceived * oracleTo * 10 ** (18 - IERC20Metadata(_collaterals[toToken]).decimals()),
                amountInSpent * oracleFrom * 10 ** (18 - IERC20Metadata(_collaterals[fromToken]).decimals()),
                "Direct arbitrage"
            );
        }
        // {
        //     (uint256 collatRatio, ) = transmuter.getCollateralRatio();
        //     assertLe(prevCollatRatio, collatRatio, "Collateral ratio should not decrease");
        // }
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
        agToken.transfer(receiver, (mintedStables * transferProportion) / BASE_9);
        vm.stopPrank();
    }

    function _updateOracles(uint256[3] memory latestOracleValue) internal {
        for (uint256 i; i < _collaterals.length; i++) {
            latestOracleValue[i] = bound(latestOracleValue[i], _minOracleValue, BASE_18);
            MockChainlinkOracle(address(_oracles[i])).setLatestAnswer(int256(latestOracleValue[i]));
        }
    }

    function _updateOracleFirewalls(uint128[6] memory userAndBurnFirewall) internal returns (uint128[6] memory) {
        uint128[] memory userFirewall = new uint128[](3);
        uint128[] memory burnFirewall = new uint128[](3);
        for (uint256 i; i < _collaterals.length; i++) {
            userFirewall[i] = uint128(bound(userAndBurnFirewall[i], 0, BASE_18));
            burnFirewall[i] = uint128(bound(userAndBurnFirewall[i + 3], 0, BASE_18));
            userAndBurnFirewall[i] = userFirewall[i];
            userAndBurnFirewall[i + 3] = burnFirewall[i];
        }

        vm.startPrank(governor);
        for (uint256 i; i < _collaterals.length; i++) {
            (
                Storage.OracleReadType readType,
                Storage.OracleReadType targetType,
                bytes memory data,
                bytes memory targetData,

            ) = transmuter.getOracle(address(_collaterals[i]));
            transmuter.setOracle(
                _collaterals[i],
                abi.encode(
                    readType,
                    targetType,
                    data,
                    targetData,
                    abi.encode(uint128(userFirewall[i]), uint128(burnFirewall[i]))
                )
            );
        }
        vm.stopPrank();
        return userAndBurnFirewall;
    }

    function _userOracleProtection(
        uint256 targetPrice,
        uint256 oracleValue,
        uint256 deviation
    ) private pure returns (uint256) {
        if (
            targetPrice * (BASE_18 - deviation) < oracleValue * BASE_18 &&
            oracleValue * BASE_18 < targetPrice * (BASE_18 + deviation)
        ) oracleValue = targetPrice;
        return oracleValue;
    }
}
