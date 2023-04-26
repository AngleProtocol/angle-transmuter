// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "../BaseOracleChainlinkTwoFeeds.sol";

/// @title OracleBTokenEURChainlink
/// @author Angle Labs, Inc.
/// @dev Tentative implementation for an oracle with book-kept values

contract OracleBTokenEURChainlink is BaseOracleChainlinkTwoFeeds, IOracleFallback {
    string public constant DESCRIPTION = "EUROC/EUR Oracle";

    // TODO update if the two assets do not have the same amount of decimals
    uint256 public constant DECIMAL_NORMALIZER = 1;

    uint256 public cumulativeVolume;

    uint256 public cumulativePriceWeightedVolume;

    constructor(
        uint32 _stalePeriod,
        address _accessControlManager,
        uint256 newCumulativePriceWeightedVolume,
        uint256 newCumulativeVolume
    ) BaseOracleChainlinkTwoFeeds(_stalePeriod, _accessControlManager) {
        cumulativeVolume = newCumulativeVolume;
        cumulativePriceWeightedVolume = newCumulativePriceWeightedVolume;
    }

    function circuitChainlink() public pure override returns (AggregatorV3Interface[] memory) {
        AggregatorV3Interface[] memory _circuitChainlink = new AggregatorV3Interface[](2);
        // Oracle BTOKEN/USD -> like Oracle Amundi Short-Term Govies ETF
        // TODO: not the actual oracle feed, it's something different here
        _circuitChainlink[0] = AggregatorV3Interface(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c);
        // Oracle EUR/USD
        _circuitChainlink[1] = AggregatorV3Interface(0xb49f677943BC038e9857d61E7d053CaA2C1734C1);
        return _circuitChainlink;
    }

    // TODO: can we do better -> might in fact be problematic to use this as a target value as using this might fix the oracle since
    // you'd always be acquiring at the lowest value -> which is potentially the initial value

    function updateInternalData(uint256 amountIn, uint256 amountOut, bool mint) external override {
        if (mint) {
            // Price is amountIn/amountOut -> if you adjust by volume it makes amountIn
            cumulativePriceWeightedVolume += amountIn;
            cumulativeVolume += amountOut;
        } else {
            cumulativePriceWeightedVolume += amountOut;
            cumulativeVolume += amountIn;
        }
    }

    function targetPrice() public view override returns (uint256) {
        return ((cumulativePriceWeightedVolume * BASE_18) * DECIMAL_NORMALIZER) / cumulativeVolume;
    }

    function adjustValues(uint256 newCumulativePriceWeightedVolume, uint256 newCumulativeVolume) external onlyGovernor {
        cumulativeVolume = newCumulativeVolume;
        cumulativePriceWeightedVolume = newCumulativePriceWeightedVolume;
    }
}
