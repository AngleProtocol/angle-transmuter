// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import { ITransmuterOracle } from "interfaces/ITransmuterOracle.sol";
import { AggregatorV3Interface } from "interfaces/external/chainlink/AggregatorV3Interface.sol";
import { IMorphoOracle } from "interfaces/external/morpho/IMorphoOracle.sol";
import { IPyth, PythStructs } from "interfaces/external/pyth/IPyth.sol";

import { LibStorage as s } from "./LibStorage.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import "../Storage.sol";

/// @title LibOracle
/// @author Angle Labs, Inc.
library LibOracle {
    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                               ACTIONS SPECIFIC ORACLES                                             
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Reads the oracle value used during a redemption to compute collateral ratio for `oracleConfig`
    /// @dev This value is only sensitive to compute the collateral ratio and deduce a penalty factor
    function readRedemption(bytes memory oracleConfig) internal view returns (uint256 oracleValue) {
        (
            OracleReadType oracleType,
            OracleReadType targetType,
            bytes memory oracleData,
            bytes memory targetData,

        ) = _parseOracleConfig(oracleConfig);
        if (oracleType == OracleReadType.EXTERNAL) {
            ITransmuterOracle externalOracle = abi.decode(oracleData, (ITransmuterOracle));
            return externalOracle.readRedemption();
        } else {
            (oracleValue, ) = readSpotAndTarget(oracleType, targetType, oracleData, targetData, 0);
            return oracleValue;
        }
    }

    /// @notice Reads the oracle value used during mint operations for an asset with `oracleConfig`
    /// @dev For assets which do not rely on external oracles, this value is the minimum between the processed oracle
    /// value for the asset and its target price
    function readMint(bytes memory oracleConfig) internal view returns (uint256 oracleValue) {
        (
            OracleReadType oracleType,
            OracleReadType targetType,
            bytes memory oracleData,
            bytes memory targetData,
            bytes memory hyperparameters
        ) = _parseOracleConfig(oracleConfig);
        if (oracleType == OracleReadType.EXTERNAL) {
            ITransmuterOracle externalOracle = abi.decode(oracleData, (ITransmuterOracle));
            return externalOracle.readMint();
        }
        (uint126 userDeviation, ) = abi.decode(hyperparameters, (uint126, uint126));
        uint256 targetPrice;
        (oracleValue, targetPrice) = readSpotAndTarget(oracleType, targetType, oracleData, targetData, userDeviation);
        if (targetPrice < oracleValue) oracleValue = targetPrice;
    }

    /// @notice Reads the oracle value used for a burn operation for an asset with `oracleConfig`
    /// @return oracleValue The actual oracle value obtained
    /// @return ratio If `oracle value < target price`, the ratio between the oracle value and the target
    /// price, otherwise `BASE_18`
    function readBurn(bytes memory oracleConfig) internal view returns (uint256 oracleValue, uint256 ratio) {
        (
            OracleReadType oracleType,
            OracleReadType targetType,
            bytes memory oracleData,
            bytes memory targetData,
            bytes memory hyperparameters
        ) = _parseOracleConfig(oracleConfig);
        if (oracleType == OracleReadType.EXTERNAL) {
            ITransmuterOracle externalOracle = abi.decode(oracleData, (ITransmuterOracle));
            return externalOracle.readBurn();
        }
        (uint126 userDeviation, uint126 burnRatioDeviation) = abi.decode(hyperparameters, (uint126, uint126));
        uint256 targetPrice;
        (oracleValue, targetPrice) = readSpotAndTarget(oracleType, targetType, oracleData, targetData, userDeviation);
        (ratio, oracleValue) = _burnRatio(targetPrice, oracleValue, burnRatioDeviation);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    VIEW FUNCTIONS                                                  
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Internal version of the `getOracle` function
    function getOracle(
        address collateral
    ) internal view returns (OracleReadType, OracleReadType, bytes memory, bytes memory, bytes memory) {
        return _parseOracleConfig(s.transmuterStorage().collaterals[collateral].oracleConfig);
    }

    /// @notice Gets the oracle value and the ratio with respect to the target price when it comes to
    /// burning for `collateral`
    function getBurnOracle(
        address collateral,
        bytes memory oracleConfig
    ) internal view returns (uint256 minRatio, uint256 oracleValue) {
        TransmuterStorage storage ts = s.transmuterStorage();
        minRatio = BASE_18;
        address[] memory collateralList = ts.collateralList;
        uint256 length = collateralList.length;
        for (uint256 i; i < length; ++i) {
            uint256 ratioObserved = BASE_18;
            if (collateralList[i] != collateral) {
                (, ratioObserved) = readBurn(ts.collaterals[collateralList[i]].oracleConfig);
            } else {
                (oracleValue, ratioObserved) = readBurn(oracleConfig);
            }
            if (ratioObserved < minRatio) minRatio = ratioObserved;
        }
    }

    /// @notice Computes the `quoteAmount` (for Chainlink oracles) depending on a `quoteType` and a base value
    /// (e.g the target price of the asset)
    /// @dev For cases where the Chainlink feed directly looks into the value of the asset, `quoteAmount` is `BASE_18`.
    /// For others, like wstETH for which Chainlink only has an oracle for stETH, `quoteAmount` is the target price
    function quoteAmount(OracleQuoteType quoteType, uint256 baseValue) internal pure returns (uint256) {
        if (quoteType == OracleQuoteType.UNIT) return BASE_18;
        else return baseValue;
    }

    function readSpotAndTarget(
        OracleReadType oracleType,
        OracleReadType targetType,
        bytes memory oracleData,
        bytes memory targetData,
        uint256 deviation
    ) internal view returns (uint256 oracleValue, uint256 targetPrice) {
        targetPrice = read(targetType, BASE_18, targetData);
        oracleValue = read(oracleType, targetPrice, oracleData);
        // Post process of the oracle value: system may tolerate small deviations from target
        oracleValue = _userOracleProtection(targetPrice, oracleValue, deviation);
    }

    /// @notice Reads an oracle value (or a target oracle value) for an asset based on its data parsed `oracleConfig`
    function read(OracleReadType readType, uint256 baseValue, bytes memory data) internal view returns (uint256) {
        if (readType == OracleReadType.CHAINLINK_FEEDS) {
            (
                AggregatorV3Interface[] memory circuitChainlink,
                uint32[] memory stalePeriods,
                uint8[] memory circuitChainIsMultiplied,
                uint8[] memory chainlinkDecimals,
                OracleQuoteType quoteType
            ) = abi.decode(data, (AggregatorV3Interface[], uint32[], uint8[], uint8[], OracleQuoteType));
            uint256 quotePrice = quoteAmount(quoteType, baseValue);
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
        } else if (readType == OracleReadType.STABLE) {
            return BASE_18;
        } else if (readType == OracleReadType.NO_ORACLE) {
            return baseValue;
        } else if (readType == OracleReadType.WSTETH) {
            return STETH.getPooledEthByShares(1 ether);
        } else if (readType == OracleReadType.CBETH) {
            return CBETH.exchangeRate();
        } else if (readType == OracleReadType.RETH) {
            return RETH.getExchangeRate();
        } else if (readType == OracleReadType.SFRXETH) {
            return SFRXETH.pricePerShare();
        } else if (readType == OracleReadType.PYTH) {
            (
                address pyth,
                bytes32[] memory feedIds,
                uint32[] memory stalePeriods,
                uint8[] memory isMultiplied,
                OracleQuoteType quoteType
            ) = abi.decode(data, (address, bytes32[], uint32[], uint8[], OracleQuoteType));
            uint256 quotePrice = quoteAmount(quoteType, baseValue);
            uint256 listLength = feedIds.length;
            for (uint256 i; i < listLength; ++i) {
                quotePrice = readPythFeed(quotePrice, feedIds[i], pyth, isMultiplied[i], stalePeriods[i]);
            }
            return quotePrice;
        } else if (readType == OracleReadType.MAX) {
            (uint256 maxValue, , , ) = abi.decode(data, (uint256, uint96, uint96, uint32));
            return maxValue;
        } else if (readType == OracleReadType.MORPHO_ORACLE) {
            (address contractAddress, uint256 normalizationFactor) = abi.decode(data, (address, uint256));
            return IMorphoOracle(contractAddress).price() / normalizationFactor;
        }
        // If the `OracleReadType` is `EXTERNAL`, it means that this function is called to compute a
        // `targetPrice` in which case the `baseValue` is returned here
        else {
            return baseValue;
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                   SPECIFIC HELPERS                                                 
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Reads a Chainlink feed using a quote amount and converts the quote amount to the out-currency
    /// @param _quoteAmount The amount for which to compute the price expressed in `BASE_18`
    /// @param feed Chainlink feed to query
    /// @param multiplied Whether the ratio outputted by Chainlink should be multiplied or divided to the `quoteAmount`
    /// @param decimals Number of decimals of the corresponding Chainlink pair
    /// @return The `quoteAmount` converted in out-currency
    function readChainlinkFeed(
        uint256 _quoteAmount,
        AggregatorV3Interface feed,
        uint8 multiplied,
        uint256 decimals,
        uint32 stalePeriod
    ) internal view returns (uint256) {
        (, int256 ratio, , uint256 updatedAt, ) = feed.latestRoundData();
        if (ratio <= 0 || block.timestamp - updatedAt > stalePeriod) revert InvalidChainlinkRate();
        // Checking whether we should multiply or divide by the ratio computed
        if (multiplied == 1) return (_quoteAmount * uint256(ratio)) / (10 ** decimals);
        else return (_quoteAmount * (10 ** decimals)) / uint256(ratio);
    }

    /// @notice Reads a Pyth fee using a quote amount and converts the quote amount to the `out-currency`
    function readPythFeed(
        uint256 _quoteAmount,
        bytes32 feedId,
        address pyth,
        uint8 multiplied,
        uint32 stalePeriod
    ) internal view returns (uint256) {
        PythStructs.Price memory pythData = IPyth(pyth).getPriceNoOlderThan(feedId, stalePeriod);
        if (pythData.price <= 0) revert InvalidRate();
        uint256 normalizedPrice = uint64(pythData.price);
        bool isNormalizerExpoNeg = pythData.expo < 0;
        uint256 normalizer = isNormalizerExpoNeg ? 10 ** uint32(-pythData.expo) : 10 ** uint32(pythData.expo);
        if (multiplied == 1 && isNormalizerExpoNeg) return (_quoteAmount * normalizedPrice) / normalizer;
        else if (multiplied == 1 && !isNormalizerExpoNeg) return _quoteAmount * normalizedPrice * normalizer;
        else if (multiplied == 0 && isNormalizerExpoNeg) return (_quoteAmount * normalizer) / normalizedPrice;
        else return _quoteAmount / (normalizer * normalizedPrice);
    }

    /// @notice Parses an `oracleConfig` into several sub fields
    function _parseOracleConfig(
        bytes memory oracleConfig
    ) private pure returns (OracleReadType, OracleReadType, bytes memory, bytes memory, bytes memory) {
        return abi.decode(oracleConfig, (OracleReadType, OracleReadType, bytes, bytes, bytes));
    }

    /// @notice Firewall in case the oracle value reported is too high compared to the target
    /// @dev This mint firewall is useful in the case of assets for which the `targetPrice` is theorically defined as
    /// the maximum value ever observed for the oracle, but this maximum value has simply not been updated.
    /// Typically, imagine a case where target is 100 and oracle is 101, in this setup, during a mint, because
    /// target should be put at 101 but hasn't been modified, the system uses for a price the oracle value
    function _firewallMint(uint256 targetPrice, uint256 oracleValue, uint256 deviation) private pure returns (uint256) {
        if (targetPrice * (BASE_18 + deviation) < oracleValue * BASE_18) oracleValue = targetPrice;
        return oracleValue;
    }

    /// @notice Firewall in case the oracle value reported is low compared to the target
    /// @dev If the oracle value is slightly below its target, then no deviation is reported for the oracle and
    /// the price of burning the stablecoin for other assets is not impacted. Also, the oracle value of this asset
    /// is set to the target price, to not be open to direct arbitrage
    function _burnRatio(
        uint256 targetPrice,
        uint256 oracleValue,
        uint256 deviation
    ) private pure returns (uint256, uint256) {
        uint256 ratio = BASE_18;
        if (oracleValue * BASE_18 < targetPrice * (BASE_18 - deviation)) ratio = (oracleValue * BASE_18) / targetPrice;
        else if (oracleValue < targetPrice) oracleValue = targetPrice;
        return (ratio, oracleValue);
    }

    /// @notice Firewall in case the oracle value reported is reasonably close to the target
    /// --> disregard the oracle value and return the target price
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

    function updateOracle(address collateral) internal {
        TransmuterStorage storage ts = s.transmuterStorage();
        if (ts.collaterals[collateral].decimals == 0) revert NotCollateral();

        (
            OracleReadType oracleType,
            OracleReadType targetType,
            bytes memory oracleData,
            ,
            bytes memory hyperparameters
        ) = _parseOracleConfig(ts.collaterals[collateral].oracleConfig);

        if (targetType != OracleReadType.MAX) revert OracleUpdateFailed();

        uint256 oracleValue = read(oracleType, BASE_18, oracleData);
        ts.collaterals[collateral].oracleConfig = abi.encode(
            oracleType,
            targetType,
            oracleData,
            // There are no checks whether the value increased or not
            abi.encode(oracleValue),
            hyperparameters
        );
    }
}
