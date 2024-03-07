// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";
import { ITransmuterOracle, MockExternalOracle } from "../mock/MockExternalOracle.sol";
import { MockMorphoOracle } from "../mock/MockMorphoOracle.sol";
import { MockPyth } from "../mock/MockPyth.sol";
import { IERC20Metadata } from "../mock/MockTokenPermit.sol";
import "../Fixture.sol";
import "../utils/FunctionUtils.sol";
import "../utils/FunctionUtils.sol";
import "contracts/transmuter/Storage.sol" as Storage;
import "contracts/utils/Errors.sol" as Errors;
import { IStETH } from "contracts/interfaces/external/lido/IStETH.sol";
import { ISfrxETH } from "contracts/interfaces/external/frax/ISfrxETH.sol";
import { ICbETH } from "contracts/interfaces/external/coinbase/ICbETH.sol";
import { IRETH } from "contracts/interfaces/external/rocketPool/IRETH.sol";
import { stdError } from "forge-std/Test.sol";

contract OracleTest is Fixture, FunctionUtils {
    using SafeERC20 for IERC20;

    uint256 internal _maxAmountWithoutDecimals = 10 ** 15;
    uint256 internal _minOracleValue = 10 ** 3; // 10**(-5)
    uint256 internal _maxOracleValue = BASE_18 / 100;
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
                                                         TESTS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_OracleReadMintStale(
        uint256[3] memory latestOracleValue,
        uint32[3] memory newStalePeriods,
        uint256 elapseTimestamp,
        uint256 stableAmount,
        uint256 fromToken
    ) public {
        // fr the stale periods in Chainlink
        elapseTimestamp = bound(elapseTimestamp, 1, 365 days);
        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        stableAmount = bound(stableAmount, 2, _maxAmountWithoutDecimals * BASE_18);

        _updateOracleValues(latestOracleValue);
        _updateOracleStalePeriods(newStalePeriods);
        skip(elapseTimestamp);

        if (newStalePeriods[fromToken] < elapseTimestamp) vm.expectRevert(Errors.InvalidChainlinkRate.selector);
        transmuter.quoteOut(stableAmount, _collaterals[fromToken], address(agToken));
    }

    function test_RevertWhen_OracleReadBurnStale(
        uint256[3] memory initialAmounts,
        uint256[3] memory latestOracleValue,
        uint32[3] memory newStalePeriods,
        uint256 elapseTimestamp,
        uint256 stableAmount,
        uint256 fromToken
    ) public {
        // fr the stale periods in Chainlink
        elapseTimestamp = bound(elapseTimestamp, 1, 365 days);
        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        stableAmount = bound(stableAmount, 2, _maxAmountWithoutDecimals * BASE_18);

        _loadReserves(alice, alice, initialAmounts, 0);
        _updateOracleValues(latestOracleValue);
        uint256 minStalePeriod = _updateOracleStalePeriods(newStalePeriods);
        skip(elapseTimestamp);
        deal(_collaterals[fromToken], address(transmuter), _maxTokenAmount[fromToken]);

        if (minStalePeriod < elapseTimestamp) vm.expectRevert(Errors.InvalidChainlinkRate.selector);
        transmuter.quoteIn(stableAmount, address(agToken), _collaterals[fromToken]);
    }

    function test_RevertWhen_OracleReadRedemptionStale(
        uint256[3] memory initialAmounts,
        uint256[3] memory latestOracleValue,
        uint32[3] memory newStalePeriods,
        uint256 elapseTimestamp,
        uint256 stableAmount,
        uint256 fromToken
    ) public {
        // fr the stale periods in Chainlink
        elapseTimestamp = bound(elapseTimestamp, 1, 365 days);
        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        stableAmount = bound(stableAmount, 2, _maxAmountWithoutDecimals * BASE_18);

        _loadReserves(alice, alice, initialAmounts, 0);
        _updateOracleValues(latestOracleValue);
        uint256 minStalePeriod = _updateOracleStalePeriods(newStalePeriods);
        skip(elapseTimestamp);

        if (minStalePeriod < elapseTimestamp) vm.expectRevert(Errors.InvalidChainlinkRate.selector);
        transmuter.getCollateralRatio();
    }

    function test_RevertWhen_OracleTargetStale(
        uint256[3] memory initialAmounts,
        uint256[3] memory latestOracleValue,
        uint32[3] memory newStalePeriods,
        uint256 elapseTimestamp,
        uint256 stableAmount,
        uint256 fromToken
    ) public {
        // fr the stale periods in Chainlink
        elapseTimestamp = bound(elapseTimestamp, 1, 365 days);
        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        stableAmount = bound(stableAmount, 2, _maxAmountWithoutDecimals * BASE_18);

        _loadReserves(alice, alice, initialAmounts, 0);
        _updateOracleValues(latestOracleValue);
        uint256 minStalePeriod = _updateTargetOracleStalePeriods(newStalePeriods);
        skip(elapseTimestamp);

        if (minStalePeriod < elapseTimestamp) vm.expectRevert(Errors.InvalidChainlinkRate.selector);
        transmuter.getCollateralRatio();

        deal(_collaterals[fromToken], address(transmuter), _maxTokenAmount[fromToken]);

        if (minStalePeriod < elapseTimestamp) vm.expectRevert(Errors.InvalidChainlinkRate.selector);
        transmuter.quoteIn(stableAmount, address(agToken), _collaterals[fromToken]);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       GETORACLE                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_GetOracle(
        uint8[3] memory newChainlinkDecimals,
        uint8[3] memory newCircuitChainIsMultiplied,
        uint8[3] memory newQuoteType,
        uint8[3] memory newReadType,
        uint8[3] memory newTargetType,
        uint256[4] memory latestExchangeRateStakeETH
    ) public {
        for (uint256 i; i < _collaterals.length; i++) {
            bytes memory oracleData;
            bytes memory targetData;
            {
                Storage.OracleReadType readType;
                Storage.OracleReadType targetType;
                uint256 userFirewall;
                uint256 burnFirewall;
                {
                    bytes memory hyperparameters;
                    (readType, targetType, oracleData, targetData, hyperparameters) = transmuter.getOracle(
                        address(_collaterals[i])
                    );
                    (userFirewall, burnFirewall) = abi.decode(hyperparameters, (uint128, uint128));
                }

                assertEq(uint256(readType), uint256(Storage.OracleReadType.CHAINLINK_FEEDS));
                assertEq(uint256(targetType), uint256(Storage.OracleReadType.STABLE));
                assertEq(userFirewall, 0);
                assertEq(burnFirewall, 0);
            }

            (
                AggregatorV3Interface[] memory circuitChainlink,
                uint32[] memory stalePeriods,
                uint8[] memory circuitChainIsMultiplied,
                uint8[] memory chainlinkDecimals,
                Storage.OracleQuoteType quoteType
            ) = abi.decode(oracleData, (AggregatorV3Interface[], uint32[], uint8[], uint8[], Storage.OracleQuoteType));
            assertEq(circuitChainlink.length, 1);
            assertEq(circuitChainIsMultiplied.length, 1);
            assertEq(chainlinkDecimals.length, 1);
            assertEq(stalePeriods.length, 1);
            assertEq(address(circuitChainlink[0]), address(_oracles[i]));
            assertEq(circuitChainIsMultiplied[0], 1);
            assertEq(chainlinkDecimals[0], 8);
            assertEq(uint256(quoteType), uint256(Storage.OracleQuoteType.UNIT));
        }

        _updateStakeETHExchangeRates(latestExchangeRateStakeETH);
        address[] memory externalOracles = _updateOracles(
            newChainlinkDecimals,
            newCircuitChainIsMultiplied,
            newQuoteType,
            newReadType,
            newTargetType
        );

        for (uint256 i; i < _collaterals.length; i++) {
            {
                bytes memory data;
                {
                    bytes memory targetData;
                    Storage.OracleReadType readType;
                    Storage.OracleReadType targetType;
                    (readType, targetType, data, targetData, ) = transmuter.getOracle(address(_collaterals[i]));

                    assertEq(uint8(readType), newReadType[i]);
                    assertEq(uint8(targetType), newTargetType[i]);
                }
                if (newReadType[i] == 1) {
                    ITransmuterOracle externalOracle = abi.decode(data, (ITransmuterOracle));
                    assertEq(address(externalOracle), externalOracles[i]);
                } else {
                    (
                        AggregatorV3Interface[] memory circuitChainlink,
                        uint32[] memory stalePeriods,
                        uint8[] memory circuitChainIsMultiplied,
                        uint8[] memory chainlinkDecimals,
                        Storage.OracleQuoteType quoteType
                    ) = abi.decode(
                            data,
                            (AggregatorV3Interface[], uint32[], uint8[], uint8[], Storage.OracleQuoteType)
                        );
                    assertEq(circuitChainlink.length, 1);
                    assertEq(circuitChainIsMultiplied.length, 1);
                    assertEq(chainlinkDecimals.length, 1);
                    assertEq(stalePeriods.length, 1);
                    assertEq(address(circuitChainlink[0]), address(_oracles[i]));
                    assertEq(circuitChainIsMultiplied[0], newCircuitChainIsMultiplied[i]);
                    assertEq(chainlinkDecimals[0], newChainlinkDecimals[i]);
                    assertEq(uint8(quoteType), newQuoteType[i]);
                }
            }

            if (newTargetType[i] == 0) {
                bytes memory targetData;
                (, , , targetData, ) = transmuter.getOracle(address(_collaterals[i]));
                (
                    AggregatorV3Interface[] memory circuitChainlink,
                    uint32[] memory stalePeriods,
                    uint8[] memory circuitChainIsMultiplied,
                    uint8[] memory chainlinkDecimals,
                    Storage.OracleQuoteType quoteType
                ) = abi.decode(
                        targetData,
                        (AggregatorV3Interface[], uint32[], uint8[], uint8[], Storage.OracleQuoteType)
                    );
                assertEq(circuitChainlink.length, 1);
                assertEq(circuitChainIsMultiplied.length, 1);
                assertEq(chainlinkDecimals.length, 1);
                assertEq(stalePeriods.length, 1);
                assertEq(address(circuitChainlink[0]), address(_oracles[i]));
                assertEq(circuitChainIsMultiplied[0], newCircuitChainIsMultiplied[i]);
                assertEq(chainlinkDecimals[0], newChainlinkDecimals[i]);
                assertEq(uint8(quoteType), newQuoteType[i]);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    READREDEMPTION                                                  
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_OracleReadRedemption_Success(
        uint8[3] memory newChainlinkDecimals,
        uint8[3] memory newCircuitChainIsMultiplied,
        uint8[3] memory newQuoteType,
        uint8[3] memory newReadType,
        uint8[3] memory newTargetType,
        uint256[3] memory latestOracleValue,
        uint256[4] memory latestExchangeRateStakeETH
    ) public {
        _updateStakeETHExchangeRates(latestExchangeRateStakeETH);
        _updateOracleValues(latestOracleValue);
        _updateOracles(newChainlinkDecimals, newCircuitChainIsMultiplied, newQuoteType, newReadType, newTargetType);

        for (uint256 i; i < _collaterals.length; i++) {
            (, , , , uint256 redemption) = transmuter.getOracleValues(address(_collaterals[i]));
            uint256 oracleRedemption;
            uint256 targetPrice;
            if (newTargetType[i] == 0) {
                (, int256 value, , , ) = _oracles[i].latestRoundData();
                targetPrice = newCircuitChainIsMultiplied[i] == 1
                    ? (BASE_18 * uint256(value)) / 10 ** (newChainlinkDecimals[i])
                    : (BASE_18 * 10 ** (newChainlinkDecimals[i])) / uint256(value);
            } else if (newTargetType[i] == 1 || newTargetType[i] == 2 || newTargetType[i] == 3) targetPrice = BASE_18;
            else targetPrice = latestExchangeRateStakeETH[newTargetType[i] - 4];

            uint256 quoteAmount = newQuoteType[i] == 0 ? BASE_18 : targetPrice;

            if (newReadType[i] == 0) {
                (, int256 value, , , ) = _oracles[i].latestRoundData();
                oracleRedemption = newCircuitChainIsMultiplied[i] == 1
                    ? (quoteAmount * uint256(value)) / 10 ** (newChainlinkDecimals[i])
                    : (quoteAmount * 10 ** (newChainlinkDecimals[i])) / uint256(value);
            } else if (newReadType[i] == 1) {
                (, int256 value, , , ) = _oracles[i].latestRoundData();
                oracleRedemption = uint256(value) * 1e12;
            } else if (newReadType[i] == 2) oracleRedemption = targetPrice;
            else if (newReadType[i] == 3) oracleRedemption = BASE_18;
            else oracleRedemption = latestExchangeRateStakeETH[newReadType[i] - 4];
            assertEq(redemption, oracleRedemption);
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       READMINT                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_OracleReadMint_Success(
        uint8[3] memory newChainlinkDecimals,
        uint8[3] memory newCircuitChainIsMultiplied,
        uint8[3] memory newQuoteType,
        uint8[3] memory newReadType,
        uint8[3] memory newTargetType,
        uint256[3] memory latestOracleValue,
        uint256[4] memory latestExchangeRateStakeETH
    ) public {
        _updateStakeETHExchangeRates(latestExchangeRateStakeETH);
        _updateOracleValues(latestOracleValue);
        _updateOracles(newChainlinkDecimals, newCircuitChainIsMultiplied, newQuoteType, newReadType, newTargetType);

        for (uint256 i; i < _collaterals.length; i++) {
            (uint256 mint, , , , ) = transmuter.getOracleValues(address(_collaterals[i]));
            uint256 oracleMint;
            uint256 targetPrice;
            if (newTargetType[i] == 0) {
                (, int256 value, , , ) = _oracles[i].latestRoundData();
                targetPrice = newCircuitChainIsMultiplied[i] == 1
                    ? (BASE_18 * uint256(value)) / 10 ** (newChainlinkDecimals[i])
                    : (BASE_18 * 10 ** (newChainlinkDecimals[i])) / uint256(value);
            } else if (newTargetType[i] == 1 || newTargetType[i] == 2 || newTargetType[i] == 3) targetPrice = BASE_18;
            else targetPrice = latestExchangeRateStakeETH[newTargetType[i] - 4];

            uint256 quoteAmount = newQuoteType[i] == 0 ? BASE_18 : targetPrice;

            if (newReadType[i] == 0) {
                (, int256 value, , , ) = _oracles[i].latestRoundData();
                oracleMint = newCircuitChainIsMultiplied[i] == 1
                    ? (quoteAmount * uint256(value)) / 10 ** (newChainlinkDecimals[i])
                    : (quoteAmount * 10 ** (newChainlinkDecimals[i])) / uint256(value);
            } else if (newReadType[i] == 1) {
                (, int256 value, , , ) = _oracles[i].latestRoundData();
                oracleMint = uint256(value) * 1e12;
            } else if (newReadType[i] == 2) oracleMint = targetPrice;
            else if (newReadType[i] == 3) oracleMint = BASE_18;
            else oracleMint = latestExchangeRateStakeETH[newReadType[i] - 4];

            if (newReadType[i] != 1 && targetPrice < oracleMint) oracleMint = targetPrice;
            assertEq(mint, oracleMint);
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       READBURN                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_OracleReadBurn_Success(
        uint8[3] memory newChainlinkDecimals,
        uint8[3] memory newCircuitChainIsMultiplied,
        uint8[3] memory newQuoteType,
        uint8[3] memory newReadType,
        uint8[3] memory newTargetType,
        uint256[3] memory latestOracleValue,
        uint256[4] memory latestExchangeRateStakeETH
    ) public {
        _updateStakeETHExchangeRates(latestExchangeRateStakeETH);
        _updateOracleValues(latestOracleValue);
        _updateOracles(newChainlinkDecimals, newCircuitChainIsMultiplied, newQuoteType, newReadType, newTargetType);

        uint256 minDeviation;
        uint256 minRatio;
        for (uint256 i; i < _collaterals.length; i++) {
            uint256 burn;
            uint256 deviation;
            (, burn, deviation, minRatio, ) = transmuter.getOracleValues(address(_collaterals[i]));
            if (i == 0) minDeviation = deviation;
            if (deviation < minDeviation) minDeviation = deviation;

            uint256 targetPrice;
            if (newTargetType[i] == 0) {
                (, int256 value, , , ) = _oracles[i].latestRoundData();
                targetPrice = newCircuitChainIsMultiplied[i] == 1
                    ? (BASE_18 * uint256(value)) / 10 ** (newChainlinkDecimals[i])
                    : (BASE_18 * 10 ** (newChainlinkDecimals[i])) / uint256(value);
            } else if (newTargetType[i] == 1 || newTargetType[i] == 2 || newTargetType[i] == 3) targetPrice = BASE_18;
            else targetPrice = latestExchangeRateStakeETH[newTargetType[i] - 4];

            uint256 oracleBurn;
            if (newReadType[i] == 0) {
                (, int256 value, , , ) = _oracles[i].latestRoundData();
                if (newQuoteType[i] == 0) {
                    if (newCircuitChainIsMultiplied[i] == 1) {
                        oracleBurn = (BASE_18 * uint256(value)) / 10 ** (newChainlinkDecimals[i]);
                    } else {
                        oracleBurn = (BASE_18 * 10 ** (newChainlinkDecimals[i])) / uint256(value);
                    }
                } else {
                    if (newCircuitChainIsMultiplied[i] == 1) {
                        oracleBurn = (targetPrice * uint256(value)) / 10 ** (newChainlinkDecimals[i]);
                    } else {
                        oracleBurn = (targetPrice * 10 ** (newChainlinkDecimals[i])) / uint256(value);
                    }
                }
            } else if (newReadType[i] == 1) {
                (, int256 value, , , ) = _oracles[i].latestRoundData();
                oracleBurn = uint256(value) * 1e12;
            } else if (newReadType[i] == 2) oracleBurn = targetPrice;
            else if (newReadType[i] == 3) oracleBurn = BASE_18;
            else oracleBurn = latestExchangeRateStakeETH[newReadType[i] - 4];

            {
                uint256 oracleDeviation = BASE_18;
                if (newReadType[i] != 1 && targetPrice > oracleBurn)
                    oracleDeviation = (oracleBurn * BASE_18) / targetPrice;
                assertEq(deviation, oracleDeviation);
            }
            assertEq(burn, oracleBurn);
        }
        assertEq(minDeviation, minRatio);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         PYTH                                                       
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_ReadPythFeed(
        uint256[3] memory prices,
        uint256[3] memory expos,
        uint8[3] memory circuitIsMultiplied
    ) public {
        MockPyth pyth = new MockPyth();
        vm.startPrank(governor);
        for (uint256 i; i < _collaterals.length; i++) {
            int64 price;
            int32 expo;
            circuitIsMultiplied[i] = uint8(bound(circuitIsMultiplied[i], 0, 1));
            prices[i] = uint256(bound(prices[i], 0, BASE_9));
            expos[i] = uint256(bound(prices[i], 0, 20));
            if (prices[i] > BASE_9 / 2) price = int64(int256(prices[i]) - int256(BASE_9));
            else price = int64(int256(prices[i]));
            if (expos[i] > 10) expo = -int32(int256(expos[i]) - int256(20));
            else expo = int32(int256(expos[i]));

            {
                Storage.OracleReadType readType = Storage.OracleReadType.PYTH;
                Storage.OracleReadType targetType = Storage.OracleReadType.STABLE;
                Storage.OracleQuoteType quoteType = Storage.OracleQuoteType.UNIT;
                bytes memory readData;
                bytes memory targetData;
                {
                    bytes32[] memory feedIds = new bytes32[](1);
                    uint32[] memory stalePeriods = new uint32[](1);
                    uint8[] memory isMultiplied = new uint8[](1);
                    feedIds[0] = 0xd052e6f54fe29355d6a3c06592fdefe49fae7840df6d8655bf6d6bfb789b56e4;
                    stalePeriods[0] = 1 hours;
                    isMultiplied[0] = circuitIsMultiplied[i];
                    readData = abi.encode(address(pyth), feedIds, stalePeriods, isMultiplied, quoteType);
                }
                vm.expectRevert(Errors.InvalidRate.selector);
                transmuter.setOracle(
                    _collaterals[i],
                    abi.encode(readType, targetType, readData, targetData, abi.encode(uint128(0), uint128(0)))
                );

                pyth.setParams(110000000, -8);
                transmuter.setOracle(
                    _collaterals[i],
                    abi.encode(readType, targetType, readData, targetData, abi.encode(uint128(0), uint128(0)))
                );
            }
            if (i == 0) {
                (uint256 mint, uint256 burn, uint256 ratio, uint256 minRatio, uint256 redemption) = transmuter
                    .getOracleValues(address(_collaterals[i]));
                if (circuitIsMultiplied[i] == 0) {
                    assertEq(mint, (BASE_18 * 10) / 11);
                    assertEq(burn, (BASE_18 * 10) / 11);
                    assertEq(ratio, (BASE_18 * 10) / 11);
                    assertEq(minRatio, (BASE_18 * 10) / 11);
                    assertEq(redemption, (BASE_18 * 10) / 11);
                } else {
                    assertEq(mint, BASE_18);
                    assertEq(burn, (BASE_18 * 11) / 10);
                    assertEq(ratio, BASE_18);
                    assertEq(minRatio, BASE_18);
                    assertEq(redemption, (BASE_18 * 11) / 10);
                }
            }
            pyth.setParams(price, expo);
            if (price <= 0) vm.expectRevert(Errors.InvalidRate.selector);
            (, , , , uint256 redemption2) = transmuter.getOracleValues(address(_collaterals[i]));
            if (price <= 0) return;
            uint256 normalizer = expos[i] < 0 ? 10 ** uint32(-expo) : 10 ** uint32(expo);
            prices[i] = uint64(price);
            if (circuitIsMultiplied[i] == 1 && expos[i] < 0) assertEq(redemption2, (BASE_18 * prices[i]) / normalizer);
            else if (circuitIsMultiplied[i] == 1 && expos[i] >= 0)
                assertEq(redemption2, BASE_18 * prices[i] * normalizer);
            else if (circuitIsMultiplied[i] == 0 && expos[i] < 0)
                assertEq(redemption2, (BASE_18 * normalizer) / prices[i]);
            else if (circuitIsMultiplied[i] == 0 && expos[i] >= 0)
                assertEq(redemption2, BASE_18 / (normalizer * prices[i]));
            pyth.setParams(0, 0);
        }
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        MORPHO                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_ReadMorphoFeed(uint256[3] memory baseValues, uint256[3] memory normalizers) public {
        vm.startPrank(governor);
        for (uint256 i; i < _collaterals.length; i++) {
            baseValues[i] = uint256(bound(baseValues[i], 100, 1e5));
            normalizers[i] = uint256(bound(normalizers[i], 1, 18));
            MockMorphoOracle morphoOracle = new MockMorphoOracle(baseValues[i] * 1e36);
            {
                Storage.OracleReadType readType = Storage.OracleReadType.MORPHO_ORACLE;
                Storage.OracleReadType targetType = Storage.OracleReadType.MAX;
                bytes memory readData = abi.encode(address(morphoOracle), 10 ** normalizers[i]);
                bytes memory targetData = abi.encode(
                    (baseValues[i] * 1e36) / 10 ** normalizers[i],
                    uint96(block.timestamp),
                    0,
                    1 days
                );
                transmuter.setOracle(
                    _collaterals[i],
                    abi.encode(readType, targetType, readData, targetData, abi.encode(uint128(0), uint128(0)))
                );
            }
            (uint256 mint, uint256 burn, uint256 ratio, uint256 minRatio, uint256 redemption) = transmuter
                .getOracleValues(address(_collaterals[i]));
            assertEq(mint, (baseValues[i] * 1e36) / 10 ** normalizers[i]);
            assertEq(burn, (baseValues[i] * 1e36) / 10 ** normalizers[i]);
            assertEq(ratio, BASE_18);
            assertEq(minRatio, BASE_18);
            assertEq(redemption, (baseValues[i] * 1e36) / 10 ** normalizers[i]);
            if (i == 2) {
                morphoOracle.setValue((baseValues[i] * 1e36 * 9) / 10);
                (mint, burn, ratio, minRatio, redemption) = transmuter.getOracleValues(address(_collaterals[i]));
                assertEq(mint, ((baseValues[i] * 1e36) * 9) / 10 ** normalizers[i] / 10);
                assertEq(burn, ((baseValues[i] * 1e36) * 9) / 10 ** normalizers[i] / 10);
                assertEq(ratio, (BASE_18 * 9) / 10);
                assertEq(minRatio, (BASE_18 * 9) / 10);
                assertEq(redemption, ((baseValues[i] * 1e36) * 9) / 10 ** normalizers[i] / 10);
            }
        }
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       FIREWALL                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_OracleReadMint_WithFirewall_Success(
        uint8[3] memory newChainlinkDecimals,
        uint8[3] memory newCircuitChainIsMultiplied,
        uint8[3] memory newQuoteType,
        uint8[3] memory newReadType,
        uint8[3] memory newTargetType,
        uint128[6] memory userAndBurnFirewall,
        uint256[3] memory latestOracleValue,
        uint256[4] memory latestExchangeRateStakeETH
    ) public {
        _updateStakeETHExchangeRates(latestExchangeRateStakeETH);
        _updateOracleValues(latestOracleValue);
        _updateOracles(newChainlinkDecimals, newCircuitChainIsMultiplied, newQuoteType, newReadType, newTargetType);
        userAndBurnFirewall = _updateOracleFirewalls(userAndBurnFirewall);

        for (uint256 i; i < _collaterals.length; i++) {
            (uint256 mint, , , , ) = transmuter.getOracleValues(address(_collaterals[i]));
            uint256 oracleMint;
            uint256 targetPrice;
            if (newTargetType[i] == 0) {
                (, int256 value, , , ) = _oracles[i].latestRoundData();
                targetPrice = newCircuitChainIsMultiplied[i] == 1
                    ? (BASE_18 * uint256(value)) / 10 ** (newChainlinkDecimals[i])
                    : (BASE_18 * 10 ** (newChainlinkDecimals[i])) / uint256(value);
            } else if (newTargetType[i] == 1 || newTargetType[i] == 2 || newTargetType[i] == 3) targetPrice = BASE_18;
            else targetPrice = latestExchangeRateStakeETH[newTargetType[i] - 4];

            uint256 quoteAmount = newQuoteType[i] == 0 ? BASE_18 : targetPrice;

            if (newReadType[i] == 0) {
                (, int256 value, , , ) = _oracles[i].latestRoundData();
                oracleMint = newCircuitChainIsMultiplied[i] == 1
                    ? (quoteAmount * uint256(value)) / 10 ** (newChainlinkDecimals[i])
                    : (quoteAmount * 10 ** (newChainlinkDecimals[i])) / uint256(value);
            } else if (newReadType[i] == 1) {
                (, int256 value, , , ) = _oracles[i].latestRoundData();
                oracleMint = uint256(value) * 1e12;
            } else if (newReadType[i] == 2) oracleMint = targetPrice;
            else if (newReadType[i] == 3) oracleMint = BASE_18;
            else oracleMint = latestExchangeRateStakeETH[newReadType[i] - 4];

            if (newReadType[i] != 1) {
                if (
                    targetPrice * (BASE_18 - userAndBurnFirewall[i]) < oracleMint * BASE_18 &&
                    targetPrice * (BASE_18 + userAndBurnFirewall[i]) > oracleMint * BASE_18
                ) oracleMint = targetPrice;
                if (targetPrice < oracleMint) oracleMint = targetPrice;
            }
            assertEq(mint, oracleMint);
        }
    }

    function testFuzz_OracleReadBurn_WithFirewall_Success(
        uint8[3] memory newCircuitChainIsMultiplied,
        uint8[3] memory newQuoteType,
        uint8[3] memory newReadType,
        uint8[3] memory newTargetType,
        uint128[6] memory userAndBurnFirewall,
        uint256[3] memory latestOracleValue,
        uint256[4] memory latestExchangeRateStakeETH
    ) public {
        _updateStakeETHExchangeRates(latestExchangeRateStakeETH);
        _updateOracleValues(latestOracleValue);
        {
            uint8[3] memory newChainlinkDecimals = [8, 8, 8];
            _updateOracles(newChainlinkDecimals, newCircuitChainIsMultiplied, newQuoteType, newReadType, newTargetType);
        }
        userAndBurnFirewall = _updateOracleFirewalls(userAndBurnFirewall);

        uint256 minDeviation;
        uint256 minRatio;
        for (uint256 i; i < _collaterals.length; i++) {
            uint256 burn;
            uint256 deviation;
            (, burn, deviation, minRatio, ) = transmuter.getOracleValues(address(_collaterals[i]));
            if (i == 0) minDeviation = deviation;
            if (deviation < minDeviation) minDeviation = deviation;

            uint256 targetPrice;
            if (newTargetType[i] == 0) {
                (, int256 value, , , ) = _oracles[i].latestRoundData();
                targetPrice = newCircuitChainIsMultiplied[i] == 1
                    ? (BASE_18 * uint256(value)) / 10 ** 8
                    : (BASE_18 * 10 ** 8) / uint256(value);
            } else if (newTargetType[i] == 1 || newTargetType[i] == 2 || newTargetType[i] == 3) targetPrice = BASE_18;
            else targetPrice = latestExchangeRateStakeETH[newTargetType[i] - 4];

            uint256 oracleBurn;
            if (newReadType[i] == 0) {
                (, int256 value, , , ) = _oracles[i].latestRoundData();
                if (newQuoteType[i] == 0) {
                    if (newCircuitChainIsMultiplied[i] == 1) {
                        oracleBurn = (BASE_18 * uint256(value)) / 10 ** 8;
                    } else {
                        oracleBurn = (BASE_18 * 10 ** 8) / uint256(value);
                    }
                } else {
                    if (newCircuitChainIsMultiplied[i] == 1) {
                        oracleBurn = (targetPrice * uint256(value)) / 10 ** 8;
                    } else {
                        oracleBurn = (targetPrice * 10 ** 8) / uint256(value);
                    }
                }
            } else if (newReadType[i] == 1) {
                (, int256 value, , , ) = _oracles[i].latestRoundData();
                oracleBurn = uint256(value) * 1e12;
            } else if (newReadType[i] == 2) oracleBurn = targetPrice;
            else if (newReadType[i] == 3) oracleBurn = BASE_18;
            else oracleBurn = latestExchangeRateStakeETH[newReadType[i] - 4];

            {
                uint256 oracleDeviation = BASE_18;
                if (newReadType[i] != 1) {
                    if (
                        targetPrice * (BASE_18 - userAndBurnFirewall[i]) < oracleBurn * BASE_18 &&
                        targetPrice * (BASE_18 + userAndBurnFirewall[i]) > oracleBurn * BASE_18
                    ) oracleBurn = targetPrice;
                    if (oracleBurn * BASE_18 < targetPrice * (BASE_18 - userAndBurnFirewall[i + 3]))
                        oracleDeviation = (oracleBurn * BASE_18) / targetPrice;
                    else if (oracleBurn < targetPrice) oracleBurn = targetPrice;
                    assertEq(deviation, oracleDeviation);
                }
            }
            assertEq(burn, oracleBurn);
        }
        assertEq(minDeviation, minRatio);
    }

    function testFuzz_Simple_ReadPythFeed_WithFirewalls(uint8[3] memory circuitIsMultiplied) public {
        vm.startPrank(governor);
        for (uint256 i; i < _collaterals.length; i++) {
            MockPyth pyth = new MockPyth();
            int64 price;
            int32 expo;
            circuitIsMultiplied[i] = uint8(bound(circuitIsMultiplied[i], 0, 1));
            {
                Storage.OracleReadType readType = Storage.OracleReadType.PYTH;
                Storage.OracleReadType targetType = Storage.OracleReadType.STABLE;
                Storage.OracleQuoteType quoteType = Storage.OracleQuoteType.UNIT;
                bytes memory readData;
                bytes memory targetData;
                {
                    bytes32[] memory feedIds = new bytes32[](1);
                    uint32[] memory stalePeriods = new uint32[](1);
                    uint8[] memory isMultiplied = new uint8[](1);
                    feedIds[0] = bytes32(0);
                    stalePeriods[0] = 1 hours;
                    isMultiplied[0] = circuitIsMultiplied[i];
                    readData = abi.encode(address(pyth), feedIds, stalePeriods, isMultiplied, quoteType);
                }

                if (i == 0) pyth.setParams(110000000, -8);
                else if (i == 1) pyth.setParams(9000000000, -10);
                else if (i == 2) pyth.setParams(96000, -5);
                {
                    bytes memory hyperParameters = abi.encode(uint128(0), uint128(0));
                    if (i == 0) hyperParameters = abi.encode(uint128(0.05 ether), uint128(0.07 ether));
                    else if (i == 1) hyperParameters = abi.encode(uint128(0.03 ether), uint128(0.099 ether));
                    else if (i == 2) hyperParameters = abi.encode(uint128(0.5 ether), uint128(0.1 ether));
                    transmuter.setOracle(
                        _collaterals[i],
                        abi.encode(readType, targetType, readData, targetData, hyperParameters)
                    );
                }
            }
        }
        for (uint256 i; i < _collaterals.length; i++) {
            (uint256 mint, uint256 burn, uint256 ratio, uint256 minRatio, uint256 redemption) = transmuter
                .getOracleValues(address(_collaterals[i]));
            if (i == 0) {
                if (circuitIsMultiplied[i] == 0) {
                    assertEq(mint, (BASE_18 * 10) / 11);
                    assertEq(burn, (BASE_18 * 10) / 11);
                    assertEq(ratio, (BASE_18 * 10) / 11);
                    assertEq(redemption, (BASE_18 * 10) / 11);
                } else {
                    assertEq(mint, BASE_18);
                    assertEq(burn, (BASE_18 * 11) / 10);
                    assertEq(ratio, BASE_18);
                    assertEq(redemption, (BASE_18 * 11) / 10);
                }
            }
            if (i == 1) {
                if (circuitIsMultiplied[i] == 0) {
                    assertEq(mint, BASE_18);
                    assertEq(burn, (BASE_18 * 10) / 9);
                    assertEq(ratio, BASE_18);
                    assertEq(redemption, (BASE_18 * 10) / 9);
                } else {
                    assertEq(mint, (BASE_18 * 9) / 10);
                    assertEq(burn, (BASE_18 * 9) / 10);
                    assertEq(ratio, (BASE_18 * 9) / 10);
                    assertEq(redemption, (BASE_18 * 9) / 10);
                }
            }
            if (i == 2) {
                if (circuitIsMultiplied[i] == 0) {
                    assertEq(mint, BASE_18);
                    assertEq(burn, BASE_18);
                    assertEq(ratio, BASE_18);
                    assertEq(redemption, (BASE_18 * 100) / 96);
                } else {
                    assertEq(mint, BASE_18);
                    assertEq(burn, BASE_18);
                    assertEq(ratio, BASE_18);
                    assertEq(redemption, (BASE_18 * 96) / 100);
                }
            }
        }
        vm.stopPrank();
    }

    function test_Simple_ReadPythFeed_WithFirewalls() public {
        vm.startPrank(governor);
        for (uint256 i; i < _collaterals.length; i++) {
            MockPyth pyth = new MockPyth();
            int64 price;
            int32 expo;
            {
                Storage.OracleReadType readType = Storage.OracleReadType.PYTH;
                Storage.OracleReadType targetType = Storage.OracleReadType.STABLE;
                Storage.OracleQuoteType quoteType = Storage.OracleQuoteType.UNIT;
                bytes memory readData;
                bytes memory targetData;
                {
                    bytes32[] memory feedIds = new bytes32[](1);
                    uint32[] memory stalePeriods = new uint32[](1);
                    uint8[] memory isMultiplied = new uint8[](1);
                    feedIds[0] = bytes32(0);
                    stalePeriods[0] = 1 hours;
                    isMultiplied[0] = 1;
                    readData = abi.encode(address(pyth), feedIds, stalePeriods, isMultiplied, quoteType);
                }

                if (i == 0) pyth.setParams(110000000, -8);
                else if (i == 1) pyth.setParams(9000000000, -10);
                else if (i == 2) pyth.setParams(96000, -5);
                {
                    bytes memory hyperParameters = abi.encode(uint128(0), uint128(0));
                    if (i == 0) hyperParameters = abi.encode(uint128(0.05 ether), uint128(0.07 ether));
                    else if (i == 1) hyperParameters = abi.encode(uint128(0.03 ether), uint128(0.1 ether));
                    else if (i == 2) hyperParameters = abi.encode(uint128(0.5 ether), uint128(0.1 ether));
                    transmuter.setOracle(
                        _collaterals[i],
                        abi.encode(readType, targetType, readData, targetData, hyperParameters)
                    );
                }
                if (i == 1) {
                    (uint256 mint, uint256 burn, uint256 ratio, uint256 minRatio, uint256 redemption) = transmuter
                        .getOracleValues(address(_collaterals[1]));
                    assertEq(mint, (BASE_18 * 9) / 10);
                    assertEq(burn, BASE_18);
                    assertEq(redemption, (BASE_18 * 9) / 10);
                }
            }
        }

        (, , , uint256 minRatio, ) = transmuter.getOracleValues(address(_collaterals[0]));
        assertEq(minRatio, BASE_18);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                 UPDATE ORACLE STORAGE                                              
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_revertWhen_updateOracle_NotAuthorized() public {
        vm.startPrank(alice);
        vm.expectRevert(Errors.NotTrusted.selector);
        transmuter.updateOracle(_collaterals[0]);
    }

    function testFuzz_revertWhen_updateOracle_NotACollateral(address fakeCollat) public {
        for (uint256 i; i < _collaterals.length; i++) {
            vm.assume(fakeCollat != _collaterals[i]);
        }
        vm.prank(governor);
        transmuter.toggleTrusted(alice, Storage.TrustedType.Seller);

        vm.prank(alice);
        vm.expectRevert(Errors.NotCollateral.selector);
        transmuter.updateOracle(fakeCollat);
    }

    function testFuzz_revertWhen_updateOracle_NotMax() public {
        vm.prank(governor);
        transmuter.toggleTrusted(alice, Storage.TrustedType.Seller);

        (, , , bytes memory targetData, ) = transmuter.getOracle(_collaterals[0]);
        assertEq(targetData.length, 0);

        vm.prank(alice);
        vm.expectRevert(Errors.OracleUpdateFailed.selector);
        transmuter.updateOracle(_collaterals[0]);
    }

    function testFuzz_revertWhen_updateOracle_NoUpdate() public {
        vm.prank(governor);
        transmuter.toggleTrusted(alice, Storage.TrustedType.Seller);

        address collateral = _collaterals[0];

        (
            Storage.OracleReadType readType,
            Storage.OracleReadType targetType,
            bytes memory data,
            bytes memory targetData,
            bytes memory hyperparameters
        ) = transmuter.getOracle(address(collateral));
        (uint256 oracleValue, , , , ) = transmuter.getOracleValues(collateral);

        vm.prank(governor);
        transmuter.setOracle(
            collateral,
            abi.encode(readType, Storage.OracleReadType.MAX, data, abi.encode(oracleValue), hyperparameters)
        );

        vm.prank(alice);
        vm.expectRevert(Errors.OracleUpdateFailed.selector);
        transmuter.updateOracle(collateral);
    }

    function testFuzz_updateOracle_Success(uint256 updateOracleValue, uint32 heartbeat) public {
        vm.prank(governor);
        transmuter.toggleTrusted(alice, Storage.TrustedType.Seller);

        uint256 indexCollat = 0;
        address collateral = _collaterals[indexCollat];

        {
            (Storage.OracleReadType readType, , bytes memory data, , ) = transmuter.getOracle(address(collateral));
            (uint256 oracleValue, , , , ) = transmuter.getOracleValues(collateral);

            vm.prank(governor);
            transmuter.setOracle(
                collateral,
                abi.encode(
                    readType,
                    Storage.OracleReadType.MAX,
                    data,
                    abi.encode(oracleValue),
                    abi.encode(uint128(0), uint128(0))
                )
            );
        }

        vm.warp(block.timestamp + heartbeat);

        // Update the oracles
        uint256 newOracleValue;
        {
            (, int256 oracleValueTmp, , , ) = _oracles[indexCollat].latestRoundData();
            updateOracleValue = bound(updateOracleValue, uint256(oracleValueTmp) + 1, _maxOracleValue);
            if (updateOracleValue > _maxOracleValue) return;

            uint256[3] memory latestOracleValue = [updateOracleValue, BASE_8, BASE_8];
            latestOracleValue = _updateOracleValues(latestOracleValue);
            newOracleValue = latestOracleValue[indexCollat];
        }

        vm.prank(alice);
        transmuter.updateOracle(collateral);

        (, , , bytes memory targetData, ) = transmuter.getOracle(address(collateral));
        uint256 maxValue = abi.decode(targetData, (uint256));

        assertEq(maxValue, (newOracleValue * BASE_18) / BASE_8);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                 UPDATE ORACLE STORAGE                                              
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_revertWhen_updateOracle_NotAuthorized() public {
        vm.startPrank(alice);
        vm.expectRevert(Errors.NotTrusted.selector);
        transmuter.updateOracle(_collaterals[0]);
    }

    function testFuzz_revertWhen_updateOracle_NotACollateral(address fakeCollat) public {
        for (uint256 i; i < _collaterals.length; i++) {
            vm.assume(fakeCollat != _collaterals[i]);
        }
        vm.prank(governor);
        transmuter.toggleTrusted(alice, Storage.TrustedType.Updater);

        vm.prank(alice);
        vm.expectRevert(Errors.NotCollateral.selector);
        transmuter.updateOracle(fakeCollat);
    }

    function testFuzz_revertWhen_updateOracle_NotMax() public {
        vm.prank(governor);
        transmuter.toggleTrusted(alice, Storage.TrustedType.Updater);

        (, , , bytes memory targetData, ) = transmuter.getOracle(_collaterals[0]);
        assertEq(targetData.length, 0);

        vm.prank(alice);
        vm.expectRevert(Errors.OracleUpdateFailed.selector);
        transmuter.updateOracle(_collaterals[0]);
    }

    function testFuzz_revertWhen_updateOracle_NoUpdate() public {
        vm.prank(governor);
        transmuter.toggleTrusted(alice, Storage.TrustedType.Updater);

        address collateral = _collaterals[0];
        uint96 deviationThreshold = 0;
        // This should be enough to avoid automatically minted blocks by foundry
        uint32 heartbeat = 1000;

        (
            Storage.OracleReadType readType,
            Storage.OracleReadType targetType,
            bytes memory data,
            bytes memory targetData,
            bytes memory hyperparameters
        ) = transmuter.getOracle(address(collateral));
        (uint256 oracleValue, , , , ) = transmuter.getOracleValues(collateral);

        vm.prank(governor);
        transmuter.setOracle(
            collateral,
            abi.encode(
                readType,
                Storage.OracleReadType.MAX,
                data,
                abi.encode(oracleValue, uint96(block.timestamp), deviationThreshold, heartbeat),
                hyperparameters
            )
        );

        vm.prank(alice);
        vm.expectRevert(Errors.OracleUpdateFailed.selector);
        transmuter.updateOracle(collateral);
    }

    function testFuzz_updateOracle_Heartbeat_Success(uint32 heartbeat) public {
        vm.prank(governor);
        transmuter.toggleTrusted(alice, Storage.TrustedType.Updater);

        address collateral = _collaterals[0];
        uint96 deviationThreshold = 0;

        (Storage.OracleReadType readType, , bytes memory data, , bytes memory hyperparameters) = transmuter.getOracle(
            address(collateral)
        );
        (uint256 oracleValue, , , , ) = transmuter.getOracleValues(collateral);

        vm.prank(governor);
        transmuter.setOracle(
            collateral,
            abi.encode(
                readType,
                Storage.OracleReadType.MAX,
                data,
                abi.encode(oracleValue, deviationThreshold, uint96(block.timestamp), heartbeat),
                hyperparameters
            )
        );

        vm.warp(block.timestamp + heartbeat + 1);

        // Update the oracles
        {
            uint256[3] memory latestOracleValue = [BASE_8, BASE_8, BASE_8];
            _updateOracleValues(latestOracleValue);
        }

        vm.prank(alice);
        transmuter.updateOracle(collateral);

        (, , , bytes memory targetData, ) = transmuter.getOracle(address(collateral));
        (
            uint256 maxValue,
            uint96 deviationThresholdContract,
            uint96 lastUpdateTimestamp,
            uint32 heartbeatContract
        ) = abi.decode(targetData, (uint256, uint96, uint96, uint32));
        assertEq(maxValue, oracleValue);
        assertEq(deviationThresholdContract, deviationThreshold);
        assertEq(lastUpdateTimestamp, block.timestamp);
        assertEq(heartbeatContract, heartbeat);
    }

    function testFuzz_updateOracle_Deviation_Success(uint96 deviationThreshold, uint256 newOracleValue) public {
        vm.prank(governor);
        transmuter.toggleTrusted(alice, Storage.TrustedType.Updater);

        uint256 indexCollat = 0;
        address collateral = _collaterals[indexCollat];

        {
            (Storage.OracleReadType readType, , bytes memory data, , bytes memory hyperparameters) = transmuter
                .getOracle(address(collateral));
            (uint256 oracleValue, , , , ) = transmuter.getOracleValues(collateral);

            vm.prank(governor);
            transmuter.setOracle(
                collateral,
                abi.encode(
                    readType,
                    Storage.OracleReadType.MAX,
                    data,
                    abi.encode(oracleValue, deviationThreshold, uint96(block.timestamp), 1000),
                    hyperparameters
                )
            );
        }

        // Update the oracles
        {
            (, int256 oracleValueTmp, , , ) = _oracles[indexCollat].latestRoundData();
            uint256 updateOracleValue = (uint256(oracleValueTmp) * (BASE_18 + uint256(deviationThreshold))) /
                BASE_18 +
                1;
            if (updateOracleValue > _maxOracleValue) return;

            newOracleValue = bound(newOracleValue, updateOracleValue, _maxOracleValue);
            uint256[3] memory latestOracleValue = [newOracleValue, BASE_8, BASE_8];
            latestOracleValue = _updateOracleValues(latestOracleValue);
            newOracleValue = latestOracleValue[indexCollat];
        }

        vm.prank(alice);
        transmuter.updateOracle(collateral);

        (, , , bytes memory targetData, ) = transmuter.getOracle(address(collateral));
        (uint256 maxValue, uint96 deviationThresholdContract, uint96 lastUpdateTimestamp, ) = abi.decode(
            targetData,
            (uint256, uint96, uint96, uint32)
        );

        assertEq(maxValue, (newOracleValue * BASE_18) / BASE_8);
        assertEq(deviationThresholdContract, deviationThreshold);
        assertEq(lastUpdateTimestamp, block.timestamp);
    }

    function testFuzz_updateOracle_BothConditions_Success(uint96 deviationThreshold, uint32 heartbeat) public {
        vm.prank(governor);
        transmuter.toggleTrusted(alice, Storage.TrustedType.Updater);

        uint256 indexCollat = 0;
        address collateral = _collaterals[indexCollat];

        {
            (Storage.OracleReadType readType, , bytes memory data, , ) = transmuter.getOracle(address(collateral));
            (uint256 oracleValue, , , , ) = transmuter.getOracleValues(collateral);

            vm.prank(governor);
            transmuter.setOracle(
                collateral,
                abi.encode(
                    readType,
                    Storage.OracleReadType.MAX,
                    data,
                    abi.encode(oracleValue, deviationThreshold, uint96(block.timestamp), heartbeat),
                    abi.encode(uint128(0), uint128(0))
                )
            );
        }

        vm.warp(block.timestamp + heartbeat + 1);

        // Update the oracles
        uint256 newOracleValue;
        {
            (, int256 oracleValueTmp, , , ) = _oracles[indexCollat].latestRoundData();
            uint256 updateOracleValue = (uint256(oracleValueTmp) * (BASE_18 + uint256(deviationThreshold))) /
                BASE_18 +
                1;
            if (updateOracleValue > _maxOracleValue) return;

            uint256[3] memory latestOracleValue = [updateOracleValue, BASE_8, BASE_8];
            latestOracleValue = _updateOracleValues(latestOracleValue);
            newOracleValue = latestOracleValue[indexCollat];
        }

        vm.prank(alice);
        transmuter.updateOracle(collateral);

        (, , , bytes memory targetData, ) = transmuter.getOracle(address(collateral));
        (uint256 maxValue, uint96 deviationThresholdContract, uint96 lastUpdateTimestamp, ) = abi.decode(
            targetData,
            (uint256, uint96, uint96, uint32)
        );

        assertEq(maxValue, (newOracleValue * BASE_18) / BASE_8);
        assertEq(lastUpdateTimestamp, block.timestamp);
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
    }

    function _getReadType(uint8 newReadType) internal pure returns (Storage.OracleReadType readType) {
        readType = newReadType == 0 ? Storage.OracleReadType.CHAINLINK_FEEDS : newReadType == 1
            ? Storage.OracleReadType.EXTERNAL
            : newReadType == 2
            ? Storage.OracleReadType.NO_ORACLE
            : newReadType == 3
            ? Storage.OracleReadType.STABLE
            : newReadType == 4
            ? Storage.OracleReadType.WSTETH
            : newReadType == 5
            ? Storage.OracleReadType.CBETH
            : newReadType == 6
            ? Storage.OracleReadType.RETH
            : Storage.OracleReadType.SFRXETH;
    }

    function _updateOracles(
        uint8[3] memory newChainlinkDecimals,
        uint8[3] memory newCircuitChainIsMultiplied,
        uint8[3] memory newQuoteType,
        uint8[3] memory newReadType,
        uint8[3] memory newTargetType
    ) internal returns (address[] memory externalOracles) {
        externalOracles = new address[](3);
        vm.startPrank(governor);
        for (uint256 i; i < _collaterals.length; i++) {
            newChainlinkDecimals[i] = uint8(bound(newChainlinkDecimals[i], 2, 18));
            newCircuitChainIsMultiplied[i] = uint8(bound(newCircuitChainIsMultiplied[i], 0, 1));
            newQuoteType[i] = uint8(bound(newQuoteType[i], 0, 1));
            newReadType[i] = uint8(bound(newReadType[i], 0, 7));
            newTargetType[i] = uint8(bound(newTargetType[i], 0, 7));

            Storage.OracleReadType readType = _getReadType(newReadType[i]);
            Storage.OracleReadType targetType = _getReadType(newTargetType[i]);

            Storage.OracleQuoteType quoteType = newQuoteType[i] == 0
                ? Storage.OracleQuoteType.UNIT
                : Storage.OracleQuoteType.TARGET;

            bytes memory readData;
            bytes memory targetData;
            if (readType == Storage.OracleReadType.EXTERNAL) {
                MockExternalOracle newOracle = new MockExternalOracle(_oracles[i]);
                externalOracles[i] = address(newOracle);
                readData = abi.encode(ITransmuterOracle(address(externalOracles[i])));
            }
            {
                AggregatorV3Interface[] memory circuitChainlink = new AggregatorV3Interface[](1);
                uint32[] memory stalePeriods = new uint32[](1);
                uint8[] memory circuitChainIsMultiplied = new uint8[](1);
                uint8[] memory chainlinkDecimals = new uint8[](1);
                circuitChainlink[0] = AggregatorV3Interface(_oracles[i]);
                stalePeriods[0] = 1 hours;
                circuitChainIsMultiplied[0] = newCircuitChainIsMultiplied[i];
                chainlinkDecimals[0] = newChainlinkDecimals[i];
                bytes memory data = abi.encode(
                    circuitChainlink,
                    stalePeriods,
                    circuitChainIsMultiplied,
                    chainlinkDecimals,
                    quoteType
                );
                if (readType != Storage.OracleReadType.EXTERNAL) readData = data;
                if (targetType == Storage.OracleReadType.CHAINLINK_FEEDS) targetData = data;
            }
            transmuter.setOracle(
                _collaterals[i],
                abi.encode(readType, targetType, readData, targetData, abi.encode(uint128(0), uint128(0)))
            );
        }
        vm.stopPrank();
    }

    function _updateOracleValues(uint256[3] memory latestOracleValue) internal returns (uint256[3] memory) {
        for (uint256 i; i < _collaterals.length; i++) {
            latestOracleValue[i] = bound(latestOracleValue[i], _minOracleValue * 10, _maxOracleValue);
            MockChainlinkOracle(address(_oracles[i])).setLatestAnswer(int256(latestOracleValue[i]));
        }
        return latestOracleValue;
    }

    function _updateStakeETHExchangeRates(uint256[4] memory latestExchangeRateStakeETH) internal {
        for (uint256 i; i < latestExchangeRateStakeETH.length; i++) {
            latestExchangeRateStakeETH[i] = bound(latestExchangeRateStakeETH[i], _minOracleValue * BASE_12, BASE_27);
        }
        vm.mockCall(
            address(STETH),
            abi.encodeWithSelector(IStETH.getPooledEthByShares.selector),
            abi.encode(latestExchangeRateStakeETH[0])
        );
        vm.mockCall(
            address(CBETH),
            abi.encodeWithSelector(ICbETH.exchangeRate.selector),
            abi.encode(latestExchangeRateStakeETH[1])
        );
        vm.mockCall(
            address(RETH),
            abi.encodeWithSelector(IRETH.getExchangeRate.selector),
            abi.encode(latestExchangeRateStakeETH[2])
        );
        vm.mockCall(
            address(SFRXETH),
            abi.encodeWithSelector(ISfrxETH.pricePerShare.selector),
            abi.encode(latestExchangeRateStakeETH[3])
        );
    }

    function _updateOracleStalePeriods(uint32[3] memory newStalePeriods) internal returns (uint256 minStalePeriod) {
        minStalePeriod = type(uint256).max;
        vm.startPrank(governor);
        for (uint256 i; i < _collaterals.length; i++) {
            newStalePeriods[i] = uint32(bound(newStalePeriods[i], 0, 365 days));

            if (minStalePeriod > newStalePeriods[i]) minStalePeriod = newStalePeriods[i];
            AggregatorV3Interface[] memory circuitChainlink = new AggregatorV3Interface[](1);
            uint32[] memory stalePeriods = new uint32[](1);
            uint8[] memory circuitChainIsMultiplied = new uint8[](1);
            uint8[] memory chainlinkDecimals = new uint8[](1);
            circuitChainlink[0] = AggregatorV3Interface(_oracles[i]);
            stalePeriods[0] = newStalePeriods[i];
            circuitChainIsMultiplied[0] = 1;
            chainlinkDecimals[0] = 8;
            Storage.OracleQuoteType quoteType = Storage.OracleQuoteType.UNIT;
            bytes memory readData = abi.encode(
                circuitChainlink,
                stalePeriods,
                circuitChainIsMultiplied,
                chainlinkDecimals,
                quoteType
            );
            bytes memory targetData;
            (, , , , bytes memory hyperparameters) = transmuter.getOracle(address(_collaterals[i]));
            transmuter.setOracle(
                _collaterals[i],
                abi.encode(
                    Storage.OracleReadType.CHAINLINK_FEEDS,
                    Storage.OracleReadType.STABLE,
                    readData,
                    targetData,
                    hyperparameters
                )
            );
        }
        vm.stopPrank();
    }

    function _updateTargetOracleStalePeriods(
        uint32[3] memory newStalePeriods
    ) internal returns (uint256 minStalePeriod) {
        minStalePeriod = type(uint256).max;
        vm.startPrank(governor);
        for (uint256 i; i < _collaterals.length; i++) {
            newStalePeriods[i] = uint32(bound(newStalePeriods[i], 0, 365 days));
            if (minStalePeriod > newStalePeriods[i]) minStalePeriod = newStalePeriods[i];
            AggregatorV3Interface[] memory circuitChainlink = new AggregatorV3Interface[](1);
            uint32[] memory stalePeriods = new uint32[](1);
            uint8[] memory circuitChainIsMultiplied = new uint8[](1);
            uint8[] memory chainlinkDecimals = new uint8[](1);
            circuitChainlink[0] = AggregatorV3Interface(_oracles[i]);
            stalePeriods[0] = newStalePeriods[i];
            circuitChainIsMultiplied[0] = 1;
            chainlinkDecimals[0] = 8;
            Storage.OracleQuoteType quoteType = Storage.OracleQuoteType.UNIT;
            bytes memory readData;
            bytes memory targetData = abi.encode(
                circuitChainlink,
                stalePeriods,
                circuitChainIsMultiplied,
                chainlinkDecimals,
                quoteType
            );
            (, , , , bytes memory hyperparameters) = transmuter.getOracle(address(_collaterals[i]));
            transmuter.setOracle(
                _collaterals[i],
                abi.encode(
                    Storage.OracleReadType.STABLE,
                    Storage.OracleReadType.CHAINLINK_FEEDS,
                    readData,
                    targetData,
                    hyperparameters
                )
            );
        }
        vm.stopPrank();
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

    function _updateOracleFirewalls(uint128[6] memory mintBurnFirewall) internal returns (uint128[6] memory) {
        uint128[] memory mintFirewall = new uint128[](3);
        uint128[] memory burnFirewall = new uint128[](3);
        for (uint256 i; i < _collaterals.length; i++) {
            mintFirewall[i] = mintBurnFirewall[i];
            burnFirewall[i] = uint128(bound(mintBurnFirewall[i + 3], 0, BASE_18));
            mintBurnFirewall[i + 3] = burnFirewall[i];
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
                    abi.encode(uint128(mintFirewall[i]), uint128(burnFirewall[i]))
                )
            );
        }
        vm.stopPrank();
        return mintBurnFirewall;
    }
}
