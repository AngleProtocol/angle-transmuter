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

    function setOracle(address collateral, OracleType oracleType, bytes memory data) internal {
        data = abi.encode(oracleType, data);

        KheopsStorage storage ks = s.kheopsStorage();
        Collateral storage collatInfo = ks.collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();

        // TODO Eventually add more validation
        Oracle.readMint(data); // Checks oracle validity
        ks.collaterals[collateral].oracle = data;
    }

    function targetPrice(OracleType oracleType, bytes memory data) internal view returns (uint256) {
        if (oracleType == OracleType.CHAINLINK_SIMPLE) {
            return BASE_18;
        }
        if (oracleType == OracleType.CHAINLINK_TWO_FEEDS) {
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
        if (oracleType == OracleType.CHAINLINK_SIMPLE) {
            (uint32 stalePeriod, AggregatorV3Interface oracle) = abi.decode(data, (uint32, AggregatorV3Interface));
            return readChainlinkFeed(BASE_18, oracle, 1, 8, stalePeriod);
        }
        if (oracleType == OracleType.CHAINLINK_TWO_FEEDS) {
            (uint32 stalePeriod, AggregatorV3Interface[2] memory circuitChainlink) = abi.decode(
                data,
                (uint32, AggregatorV3Interface[2])
            );

            uint256 quoteAmount = BASE_18;
            uint8[2] memory circuitChainIsMultiplied = [1, 0];
            uint8[2] memory chainlinkDecimals = [8, 8];
            for (uint256 i; i < 2; ++i) {
                quoteAmount = readChainlinkFeed(
                    quoteAmount,
                    circuitChainlink[i],
                    circuitChainIsMultiplied[i],
                    chainlinkDecimals[i],
                    stalePeriod
                );
            }
            return quoteAmount;
        } else {
            IOracle externalOracle = abi.decode(data, (IOracle));
            return externalOracle.targetPrice();
        }
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
