// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.12;

import "../../utils/Constants.sol";
import { Storage as s } from "./Storage.sol";
import "../Storage.sol";
import "../../utils/Errors.sol";

import "../../interfaces/external/chainlink/AggregatorV3Interface.sol";
import { IDiamondCut } from "../interfaces/IDiamondCut.sol";

interface IOracle {
    function targetPrice() external view returns (uint256);

    function read() external view returns (uint256);
}

library Oracle {
    function parseOracle(bytes memory oracleData) internal pure returns (OracleType, bytes memory) {
        return abi.decode(oracleData, (OracleType, bytes));
    }

    function getOracle(address collateral) internal view returns (OracleType, bytes memory) {
        return parseOracle(s.kheopsStorage().collaterals[collateral].oracle);
    }

    function targetPrice(OracleType oracleType, bytes memory data) internal view returns (uint256) {
        if (oracleType == OracleType.CHAINLINK_FEEDS) {
            return BASE_18;
        }
        if (oracleType == OracleType.WSTETH) {
            return STETH.getPooledEthByShares(1 ether);
        } else {
            IOracle externalOracle = abi.decode(data, (IOracle));
            return externalOracle.targetPrice();
        }
    }

    function read(OracleType oracleType, bytes memory data) internal view returns (uint256) {
        if (oracleType == OracleType.CHAINLINK_FEEDS) {
            (
                AggregatorV3Interface[] memory circuitChainlink,
                uint32[] memory stalePeriods,
                uint8[] memory circuitChainIsMultiplied,
                uint8[] memory chainlinkDecimals
            ) = abi.decode(data, (AggregatorV3Interface[], uint32[], uint8[], uint8[]));

            uint256 listLength = circuitChainlink.length;
            uint256 quoteAmount = BASE_18;
            for (uint256 i; i < listLength; ++i) {
                quoteAmount = readChainlinkFeed(
                    quoteAmount,
                    circuitChainlink[i],
                    circuitChainIsMultiplied[i],
                    chainlinkDecimals[i],
                    stalePeriods[i]
                );
            }
            return quoteAmount;
        } else {
            IOracle externalOracle = abi.decode(data, (IOracle));
            return externalOracle.read();
        }
    }

    // Do we want to add a small buffer at the protocol advantage or are the fees enough?
    // It shouldn't take into account the deviation nor target price as it would break the
    // anti bank run process
    function readRedemption(bytes memory oracleData) internal view returns (uint256) {
        (OracleType oracleType, bytes memory data) = parseOracle(oracleData);
        return read(oracleType, data);
    }

    function readMint(bytes memory oracleData) internal view returns (uint256 oracleValue) {
        (OracleType oracleType, bytes memory data) = parseOracle(oracleData);
        oracleValue = read(oracleType, data);
        uint256 _targetPrice = targetPrice(oracleType, data);
        if (_targetPrice < oracleValue) oracleValue = _targetPrice;
    }

    function readBurn(bytes memory oracleData) internal view returns (uint256 oracleValue, uint256 deviation) {
        (OracleType oracleType, bytes memory data) = parseOracle(oracleData);
        oracleValue = read(oracleType, data);
        uint256 _targetPrice = targetPrice(oracleType, data);
        deviation = BASE_18;
        if (oracleValue < _targetPrice) {
            // TODO: does it work well in terms of non manipulability of the redemptions to give the prices like that
            deviation = (oracleValue * BASE_18) / _targetPrice;
            // Overestimating the oracle value
            oracleValue = _targetPrice;
        }
    }

    // ============================== SPECIFIC HELPERS =============================

    /// @notice Reads a Chainlink feed using a quote amount and converts the quote amount to
    /// the out-currency
    /// @param quoteAmount The amount for which to compute the price expressed with base decimal
    /// @param feed Chainlink feed to query
    /// @param multiplied Whether the ratio outputted by Chainlink should be multiplied or divided
    /// to the `quoteAmount`
    /// @param decimals Number of decimals of the corresponding Chainlink pair
    /// @return The `quoteAmount` converted in out-currency
    function readChainlinkFeed(
        uint256 quoteAmount,
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
        if (multiplied == 1) return (quoteAmount * castedRatio) / (10 ** decimals);
        else return (quoteAmount * (10 ** decimals)) / castedRatio;
    }

    // TODO Add getters for data
}
