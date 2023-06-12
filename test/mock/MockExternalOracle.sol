// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import { AggregatorV3Interface } from "contracts/interfaces/external/chainlink/AggregatorV3Interface.sol";
import { ITransmuterOracle } from "contracts/interfaces/ITransmuterOracle.sol";

contract MockExternalOracle is ITransmuterOracle {
    AggregatorV3Interface feed;

    constructor(AggregatorV3Interface _feed) {
        feed = _feed;
    }

    function readRedemption() external view returns (uint256) {
        (, int256 ratio, , , ) = feed.latestRoundData();
        return uint256(ratio) * 1e12;
    }

    function readMint() external view returns (uint256) {
        (, int256 ratio, , , ) = feed.latestRoundData();
        return uint256(ratio) * 1e12;
    }

    function readBurn() external view returns (uint256 oracleValue, uint256 deviation) {
        (, int256 ratio, , , ) = feed.latestRoundData();
        return (uint256(ratio) * 1e12, 1e18);
    }
}
