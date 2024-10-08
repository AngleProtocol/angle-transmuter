// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

import { IERC20Metadata } from "oz/interfaces/IERC20Metadata.sol";
import { IERC4626 } from "interfaces/external/IERC4626.sol";
import { AggregatorV3Interface } from "interfaces/external/chainlink/AggregatorV3Interface.sol";

contract ERC4626Oracle is AggregatorV3Interface {
    IERC4626 private _asset;

    constructor(IERC4626 asset) {
        _asset = asset;
    }

    function decimals() public view override returns (uint8) {
        return IERC20Metadata(address(_asset)).decimals();
    }

    function description() external view override returns (string memory) {
        return "ERC4626 Oracle";
    }

    function version() external view returns (uint256) {
        return 1;
    }

    function getRoundData(
        uint80 _roundId
    )
        public
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, int256(_asset.convertToAssets(10 ** decimals())), 0, block.timestamp, 0);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return getRoundData(0);
    }
}
