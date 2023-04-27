// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.12;

import "../../utils/Constants.sol";
import { Storage as s } from "./Storage.sol";
import "../Storage.sol";
import "../../utils/Errors.sol";

import "../../interfaces/IExternalOracle.sol";
import "../../interfaces/external/chainlink/AggregatorV3Interface.sol";
import { IDiamondCut } from "../interfaces/IDiamondCut.sol";

library Oracle {
    function parseOracle(
        bytes memory oracleData
    ) internal pure returns (OracleReadType, OracleQuoteType, OracleTargetType, bytes memory) {
        return abi.decode(oracleData, (OracleReadType, OracleQuoteType, OracleTargetType, bytes));
    }

    function getOracle(
        address collateral
    ) internal view returns (OracleReadType, OracleQuoteType, OracleTargetType, bytes memory) {
        return parseOracle(s.kheopsStorage().collaterals[collateral].oracle);
    }

    function targetPrice(OracleTargetType targetType, bytes memory oracleStorage) internal view returns (uint256) {
        if (targetType == OracleTargetType.STABLE) return BASE_18;
        if (targetType == OracleTargetType.BONDS) {
            (uint256 cumulativeVolume, uint256 cumulativePriceWeightedVolume, uint256 decimalNormalizer) = abi.decode(
                oracleStorage,
                (uint256, uint256, uint256)
            );
            return ((cumulativePriceWeightedVolume * BASE_18) * decimalNormalizer) / cumulativeVolume;
        }
        if (targetType == OracleTargetType.WSTETH) return STETH.getPooledEthByShares(1 ether);
        revert InvalidOracleType();
    }

    // There aren't Chainlink oracles for wstETH to stETH, we need to tweak a bit the system
    // For any other asset that is not referenced by Chainlink but have a reliable feed on chain
    // you can change this function and it will modify the value passed through Chainlink system
    function quoteAmount(OracleQuoteType quoteType) internal view returns (uint256) {
        if (quoteType == OracleQuoteType.UNIT) return BASE_18;
        if (quoteType == OracleQuoteType.WSTETH) return STETH.getPooledEthByShares(1 ether);
        revert InvalidOracleType();
    }

    function read(
        OracleReadType readType,
        OracleQuoteType quoteType,
        bytes memory data
    ) internal view returns (uint256) {
        if (readType == OracleReadType.CHAINLINK_FEEDS) {
            (
                AggregatorV3Interface[] memory circuitChainlink,
                uint32[] memory stalePeriods,
                uint8[] memory circuitChainIsMultiplied,
                uint8[] memory chainlinkDecimals
            ) = abi.decode(data, (AggregatorV3Interface[], uint32[], uint8[], uint8[]));

            uint256 listLength = circuitChainlink.length;
            uint256 _quoteAmount = quoteAmount(quoteType);
            for (uint256 i; i < listLength; ++i) {
                _quoteAmount = readChainlinkFeed(
                    _quoteAmount,
                    circuitChainlink[i],
                    circuitChainIsMultiplied[i],
                    chainlinkDecimals[i],
                    stalePeriods[i]
                );
            }
            return _quoteAmount;
        }
        revert InvalidOracleType();
    }

    // Do we want to add a small buffer at the protocol advantage or are the fees enough?
    // It shouldn't take into account the deviation nor target price as it would break the
    // anti bank run process
    // Also using readMint to underestimate the current collateral ratio is not possible either
    // take the exemple of 2 assets one above its target price and the other below,
    // such that real collateral ratio is above 1 but we would return a collateral ratio<1
    // Then it is profitable to redeem as you would receive substantially more of the asset 1
    // that you should have
    function readRedemption(bytes memory oracleData) internal view returns (uint256) {
        (OracleReadType readType, OracleQuoteType quoteType, , bytes memory data) = parseOracle(oracleData);
        if (readType == OracleReadType.EXTERNAL) {
            IExternalOracle externalOracle = abi.decode(data, (IExternalOracle));
            return externalOracle.readRedemption();
        } else return read(readType, quoteType, data);
    }

    function readMint(bytes memory oracleData, bytes memory oracleStorage) internal view returns (uint256 oracleValue) {
        (
            OracleReadType readType,
            OracleQuoteType quoteType,
            OracleTargetType targetType,
            bytes memory data
        ) = parseOracle(oracleData);
        if (readType == OracleReadType.EXTERNAL) {
            IExternalOracle externalOracle = abi.decode(data, (IExternalOracle));
            return externalOracle.readMint();
        }
        oracleValue = read(readType, quoteType, data);
        uint256 _targetPrice = targetPrice(targetType, oracleStorage);
        if (_targetPrice < oracleValue) oracleValue = _targetPrice;
    }

    function readBurn(
        bytes memory oracleData,
        bytes memory oracleStorage
    ) internal view returns (uint256 oracleValue, uint256 deviation) {
        (
            OracleReadType readType,
            OracleQuoteType quoteType,
            OracleTargetType targetType,
            bytes memory data
        ) = parseOracle(oracleData);
        if (readType == OracleReadType.EXTERNAL) {
            IExternalOracle externalOracle = abi.decode(data, (IExternalOracle));
            return externalOracle.readBurn();
        }
        oracleValue = read(readType, quoteType, data);
        uint256 _targetPrice = targetPrice(targetType, oracleStorage);
        deviation = BASE_18;
        if (oracleValue < _targetPrice) {
            deviation = (oracleValue * BASE_18) / _targetPrice;
            // Overestimating the oracle value
            oracleValue = _targetPrice;
        }
    }

    // TODO: can we do better -> might in fact be problematic to use this as a target value as using this might fix the oracle since
    // you'd always be acquiring at the lowest value -> which is potentially the initial value
    function updateInternalData(
        address collateral,
        bytes memory oracleData,
        bytes memory oracleStorage,
        uint256 amountIn,
        uint256 amountOut,
        bool mint
    ) internal {
        (OracleReadType readType, , OracleTargetType targetType, bytes memory data) = parseOracle(oracleData);
        if (targetType == OracleTargetType.BONDS) {
            (uint256 cumulativeVolume, uint256 cumulativePriceWeightedVolume, uint256 decimalNormalizer) = abi.decode(
                oracleStorage,
                (uint256, uint256, uint256)
            );
            if (mint) {
                // Price is amountIn/amountOut -> if you adjust by volume it makes amountIn
                cumulativePriceWeightedVolume += amountIn;
                cumulativeVolume += amountOut;
            } else {
                cumulativePriceWeightedVolume += amountOut;
                cumulativeVolume += amountIn;
            }
            s.kheopsStorage().collaterals[collateral].oracleStorage = abi.encode(
                cumulativeVolume,
                cumulativePriceWeightedVolume,
                decimalNormalizer
            );
        } else if (readType == OracleReadType.EXTERNAL) {
            IExternalOracle externalOracle = abi.decode(data, (IExternalOracle));
            externalOracle.updateInternalData(amountIn, amountOut, mint);
        } else revert InvalidOracleType();
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

    // TODO Add getters for data
}
