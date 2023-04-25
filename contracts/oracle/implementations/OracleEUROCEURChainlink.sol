// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "../BaseOracleChainlinkTwoFeeds.sol";

/// @title OracleEUROCEURChainlink
/// @author Angle Labs, Inc.
/// @notice Gives the price of EUROC in Euro in base 18
contract OracleEUROCEURChainlink is BaseOracleChainlinkTwoFeeds {
    string public constant DESCRIPTION = "EUROC/EUR Oracle";

    constructor(
        uint32 _stalePeriod,
        address _accessControlManager
    ) BaseOracleChainlinkTwoFeeds(_stalePeriod, _accessControlManager) {}

    function circuitChainlink() public pure override returns (AggregatorV3Interface[] memory) {
        AggregatorV3Interface[] memory _circuitChainlink = new AggregatorV3Interface[](2);
        // Oracle EUROC/USD
        // TODO: not the actual oracle feed, it's something different here
        _circuitChainlink[0] = AggregatorV3Interface(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c);
        // Oracle EUR/USD
        _circuitChainlink[1] = AggregatorV3Interface(0xb49f677943BC038e9857d61E7d053CaA2C1734C1);
        return _circuitChainlink;
    }

    function targetPrice() public pure override returns (uint256) {
        return c._BASE_18;
    }
}
