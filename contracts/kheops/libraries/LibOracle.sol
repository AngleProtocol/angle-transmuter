// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { AggregatorV3Interface } from "../../interfaces/external/chainlink/AggregatorV3Interface.sol";
import { IKheopsOracle } from "../../interfaces/IKheopsOracle.sol";
import { IDiamondCut } from "../interfaces/IDiamondCut.sol";

import { LibStorage as s } from "./LibStorage.sol";

import "../../utils/Errors.sol";
import "../../utils/Constants.sol";
import "../Storage.sol";

/// @title LibOracle
/// @author Angle Labs, Inc.
library LibOracle {
    function parseOracle(
        bytes memory oracleConfig
    ) internal pure returns (OracleReadType, OracleTargetType, bytes memory) {
        return abi.decode(oracleConfig, (OracleReadType, OracleTargetType, bytes));
    }

    function getOracle(address collateral) internal view returns (OracleReadType, OracleTargetType, bytes memory) {
        return parseOracle(s.kheopsStorage().collaterals[collateral].oracleConfig);
    }

    function targetPrice(OracleTargetType targetType) internal view returns (uint256) {
        if (targetType == OracleTargetType.STABLE) return BASE_18;
        else if (targetType == OracleTargetType.WSTETH) return STETH.getPooledEthByShares(1 ether);
        else if (targetType == OracleTargetType.CBETH) return CBETH.exchangeRate();
        else if (targetType == OracleTargetType.RETH) return RETH.getExchangeRate();
        else if (targetType == OracleTargetType.SFRXETH) return SFRXETH.pricePerShare();
        revert InvalidOracleType();
    }

    function quoteAmount(OracleQuoteType quoteType, uint256 _targetPrice) internal pure returns (uint256) {
        if (quoteType == OracleQuoteType.UNIT) return BASE_18;
        else if (quoteType == OracleQuoteType.TARGET) return _targetPrice;
        revert InvalidOracleType();
    }

    function read(OracleReadType readType, uint256 _targetPrice, bytes memory data) internal view returns (uint256) {
        if (readType == OracleReadType.CHAINLINK_FEEDS) {
            (
                AggregatorV3Interface[] memory circuitChainlink,
                uint32[] memory stalePeriods,
                uint8[] memory circuitChainIsMultiplied,
                uint8[] memory chainlinkDecimals,
                OracleQuoteType quoteType
            ) = abi.decode(data, (AggregatorV3Interface[], uint32[], uint8[], uint8[], OracleQuoteType));
            uint256 quotePrice = quoteAmount(quoteType, _targetPrice);
            uint256 listLength = circuitChainlink.length;
            for (uint256 i; i < listLength; ++i) {
                quotePrice = readChainlinkFeed(
                    quotePrice,
                    circuitChainlink[i],
                    circuitChainIsMultiplied[i],
                    chainlinkDecimals[i],
                    stalePeriods[i]
                );
            }
            return quotePrice;
        } else if (readType == OracleReadType.NO_ORACLE) {
            return _targetPrice;
        }
        revert InvalidOracleType();
    }

    function readRedemption(bytes memory oracleConfig) internal view returns (uint256) {
        (OracleReadType readType, OracleTargetType targetType, bytes memory data) = parseOracle(oracleConfig);
        if (readType == OracleReadType.EXTERNAL) {
            IKheopsOracle externalOracle = abi.decode(data, (IKheopsOracle));
            return externalOracle.readRedemption();
        } else return read(readType, targetPrice(targetType), data);
    }

    function readMint(bytes memory oracleConfig) internal view returns (uint256 oracleValue) {
        (OracleReadType readType, OracleTargetType targetType, bytes memory data) = parseOracle(oracleConfig);
        if (readType == OracleReadType.EXTERNAL) {
            IKheopsOracle externalOracle = abi.decode(data, (IKheopsOracle));
            return externalOracle.readMint();
        }
        uint256 _targetPrice = targetPrice(targetType);
        oracleValue = read(readType, _targetPrice, data);
        if (_targetPrice < oracleValue) oracleValue = _targetPrice;
    }

    function readBurn(bytes memory oracleConfig) internal view returns (uint256 oracleValue, uint256 deviation) {
        (OracleReadType readType, OracleTargetType targetType, bytes memory data) = parseOracle(oracleConfig);
        if (readType == OracleReadType.EXTERNAL) {
            IKheopsOracle externalOracle = abi.decode(data, (IKheopsOracle));
            return externalOracle.readBurn();
        }
        uint256 _targetPrice = targetPrice(targetType);
        oracleValue = read(readType, _targetPrice, data);
        deviation = BASE_18;
        if (oracleValue < _targetPrice) deviation = (oracleValue * BASE_18) / _targetPrice;
    }

    // ============================== SPECIFIC HELPERS =============================

    /// @notice Reads a Chainlink feed using a quote amount and converts the quote amount to
    /// the out-currency
    /// @param _quoteAmount The amount for which to compute the price expressed with base decimal
    /// @param feed Chainlink feed to query
    /// @param multiplied Whether the ratio outputted by Chainlink should be multiplied or divided
    /// to the `quoteAmount`
    /// @param decimals Number of decimals of the corresponding Chainlink pair
    /// @return The `quoteAmount` converted in out-currency
    function readChainlinkFeed(
        uint256 _quoteAmount,
        AggregatorV3Interface feed,
        uint8 multiplied,
        uint256 decimals,
        uint32 stalePeriod
    ) internal view returns (uint256) {
        (uint80 roundId, int256 ratio, , uint256 updatedAt, uint80 answeredInRound) = feed.latestRoundData();
        if (ratio <= 0 || roundId > answeredInRound || block.timestamp - updatedAt > stalePeriod)
            revert InvalidChainlinkRate();
        uint256 castedRatio = uint256(ratio);
        // Checking whether we should multiply or divide by the ratio computed
        if (multiplied == 1) return (_quoteAmount * castedRatio) / (10 ** decimals);
        else return (_quoteAmount * (10 ** decimals)) / castedRatio;
    }
}
