// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";
import { ITransmuterOracle, MockExternalOracle } from "../mock/MockExternalOracle.sol";
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
        for (uint i; i < _collaterals.length; i++) {
            bytes memory data;
            {
                Storage.OracleReadType readType;
                Storage.OracleTargetType targetType;
                (readType, targetType, data) = transmuter.getOracle(address(_collaterals[i]));

                assertEq(uint(readType), uint(Storage.OracleReadType.CHAINLINK_FEEDS));
                assertEq(uint(targetType), uint(Storage.OracleTargetType.STABLE));
            }
            (
                AggregatorV3Interface[] memory circuitChainlink,
                uint32[] memory stalePeriods,
                uint8[] memory circuitChainIsMultiplied,
                uint8[] memory chainlinkDecimals,
                Storage.OracleQuoteType quoteType
            ) = abi.decode(data, (AggregatorV3Interface[], uint32[], uint8[], uint8[], Storage.OracleQuoteType));
            assertEq(circuitChainlink.length, 1);
            assertEq(circuitChainIsMultiplied.length, 1);
            assertEq(chainlinkDecimals.length, 1);
            assertEq(stalePeriods.length, 1);
            assertEq(address(circuitChainlink[0]), address(_oracles[i]));
            assertEq(circuitChainIsMultiplied[0], 1);
            assertEq(chainlinkDecimals[0], 8);
            assertEq(uint(quoteType), uint(Storage.OracleQuoteType.UNIT));
        }

        _updateStakeETHExchangeRates(latestExchangeRateStakeETH);
        address[] memory externalOracles = _updateOracles(
            newChainlinkDecimals,
            newCircuitChainIsMultiplied,
            newQuoteType,
            newReadType,
            newTargetType
        );

        for (uint i; i < _collaterals.length; i++) {
            bytes memory data;
            {
                Storage.OracleReadType readType;
                Storage.OracleTargetType targetType;
                (readType, targetType, data) = transmuter.getOracle(address(_collaterals[i]));

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
                ) = abi.decode(data, (AggregatorV3Interface[], uint32[], uint8[], uint8[], Storage.OracleQuoteType));
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

    function testFuzz_OracleReadRedemptionSuccess(
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

        for (uint i; i < _collaterals.length; i++) {
            (, , , , uint256 redemption) = transmuter.getOracleValues(address(_collaterals[i]));
            uint256 oracleRedemption;
            uint256 targetPrice = newTargetType[i] == 0 ? BASE_18 : latestExchangeRateStakeETH[newTargetType[i] - 1];
            uint256 quoteAmount = newQuoteType[i] == 0 ? BASE_18 : targetPrice;
            if (newReadType[i] == 2) oracleRedemption = targetPrice;
            else if (newReadType[i] == 0) {
                (, int256 value, , , ) = _oracles[i].latestRoundData();
                oracleRedemption = newCircuitChainIsMultiplied[i] == 1
                    ? (quoteAmount * uint256(value)) / 10 ** (newChainlinkDecimals[i])
                    : (quoteAmount * 10 ** (newChainlinkDecimals[i])) / uint256(value);
            } else {
                (, int256 value, , , ) = _oracles[i].latestRoundData();
                oracleRedemption = uint256(value) * 1e12;
            }
            assertEq(redemption, oracleRedemption);
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       READMINT                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_OracleReadMintSuccess(
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

        for (uint i; i < _collaterals.length; i++) {
            (uint256 mint, , , , ) = transmuter.getOracleValues(address(_collaterals[i]));
            uint256 oracleMint;
            uint256 targetPrice = newTargetType[i] == 0 ? BASE_18 : latestExchangeRateStakeETH[newTargetType[i] - 1];
            uint256 quoteAmount = newQuoteType[i] == 0 ? BASE_18 : targetPrice;
            if (newReadType[i] == 2) oracleMint = targetPrice;
            else if (newReadType[i] == 0) {
                (, int256 value, , , ) = _oracles[i].latestRoundData();
                oracleMint = newCircuitChainIsMultiplied[i] == 1
                    ? (quoteAmount * uint256(value)) / 10 ** (newChainlinkDecimals[i])
                    : (quoteAmount * 10 ** (newChainlinkDecimals[i])) / uint256(value);
            } else {
                (, int256 value, , , ) = _oracles[i].latestRoundData();
                oracleMint = uint256(value) * 1e12;
            }
            if (newReadType[i] != 1 && targetPrice < oracleMint) oracleMint = targetPrice;
            assertEq(mint, oracleMint);
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       READBURN                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_OracleReadBurnSuccess(
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
        for (uint i; i < _collaterals.length; i++) {
            uint256 burn;
            uint256 deviation;
            (, burn, deviation, minRatio, ) = transmuter.getOracleValues(address(_collaterals[i]));
            if (i == 0) minDeviation = deviation;
            if (deviation < minDeviation) minDeviation = deviation;
            uint256 oracleBurn;
            uint256 targetPrice = newTargetType[i] == 0 ? BASE_18 : latestExchangeRateStakeETH[newTargetType[i] - 1];
            if (newReadType[i] == 2) oracleBurn = targetPrice;
            else if (newReadType[i] == 0) {
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
            } else {
                (, int256 value, , , ) = _oracles[i].latestRoundData();
                oracleBurn = uint256(value) * 1e12;
            }
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
            newReadType[i] = uint8(bound(newReadType[i], 0, 2));
            newTargetType[i] = uint8(bound(newTargetType[i], 0, 4));

            Storage.OracleReadType readType = newReadType[i] == 0
                ? Storage.OracleReadType.CHAINLINK_FEEDS
                : newReadType[i] == 1
                ? Storage.OracleReadType.EXTERNAL
                : Storage.OracleReadType.NO_ORACLE;
            Storage.OracleTargetType targetType = newTargetType[i] == 0
                ? Storage.OracleTargetType.STABLE
                : newTargetType[i] == 1
                ? Storage.OracleTargetType.WSTETH
                : newTargetType[i] == 2
                ? Storage.OracleTargetType.CBETH
                : newTargetType[i] == 3
                ? Storage.OracleTargetType.RETH
                : Storage.OracleTargetType.SFRXETH;
            Storage.OracleQuoteType quoteType = newQuoteType[i] == 0
                ? Storage.OracleQuoteType.UNIT
                : Storage.OracleQuoteType.TARGET;

            bytes memory readData;
            if (readType == Storage.OracleReadType.EXTERNAL) {
                MockExternalOracle newOracle = new MockExternalOracle(_oracles[i]);
                externalOracles[i] = address(newOracle);
                readData = abi.encode(ITransmuterOracle(address(externalOracles[i])));
            } else {
                AggregatorV3Interface[] memory circuitChainlink = new AggregatorV3Interface[](1);
                uint32[] memory stalePeriods = new uint32[](1);
                uint8[] memory circuitChainIsMultiplied = new uint8[](1);
                uint8[] memory chainlinkDecimals = new uint8[](1);
                circuitChainlink[0] = AggregatorV3Interface(_oracles[i]);
                stalePeriods[0] = 1 hours;
                circuitChainIsMultiplied[0] = newCircuitChainIsMultiplied[i];
                chainlinkDecimals[0] = newChainlinkDecimals[i];
                readData = abi.encode(
                    circuitChainlink,
                    stalePeriods,
                    circuitChainIsMultiplied,
                    chainlinkDecimals,
                    quoteType
                );
            }
            transmuter.setOracle(_collaterals[i], abi.encode(readType, targetType, readData));
        }
        vm.stopPrank();
    }

    function _updateOracleValues(uint256[3] memory latestOracleValue) internal {
        for (uint256 i; i < _collaterals.length; i++) {
            latestOracleValue[i] = bound(latestOracleValue[i], _minOracleValue * 10, BASE_18 / 100);
            MockChainlinkOracle(address(_oracles[i])).setLatestAnswer(int256(latestOracleValue[i]));
        }
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
            transmuter.setOracle(
                _collaterals[i],
                abi.encode(Storage.OracleReadType.CHAINLINK_FEEDS, Storage.OracleTargetType.STABLE, readData)
            );
        }
        vm.stopPrank();
    }

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
}
