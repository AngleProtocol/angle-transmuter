// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "./BaseOracleChainlink.sol";

/// @title BaseOracleChainlinkTwoFeeds
/// @author Angle Labs, Inc.
/// @notice Base contract for an oracle that reads into two Chainlink feeds (including an EUR/USD feed) which both have
/// 8 decimals
abstract contract BaseOracleChainlinkTwoFeeds is BaseOracleChainlink {
    constructor(
        uint32 _stalePeriod,
        address _accessControlManager
    ) BaseOracleChainlink(_stalePeriod, _accessControlManager) {}

    function read() public view virtual override returns (uint256 quoteAmount) {
        quoteAmount = _quoteAmount();
        AggregatorV3Interface[] memory _circuitChainlink = circuitChainlink();
        uint8[2] memory circuitChainIsMultiplied = [1, 0];
        uint8[2] memory chainlinkDecimals = [8, 8];
        uint256 circuitLength = _circuitChainlink.length;
        for (uint256 i; i < circuitLength; ++i) {
            quoteAmount = _readChainlinkFeed(
                quoteAmount,
                _circuitChainlink[i],
                circuitChainIsMultiplied[i],
                chainlinkDecimals[i]
            );
        }
    }

    function _quoteAmount() internal view virtual returns (uint256) {
        return _BASE_18;
    }
}
