// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import "interfaces/external/pyth/IPyth.sol";

contract MockPyth {
    int64 public price;
    int32 public expo;

    function getPriceNoOlderThan(bytes32, uint) external view returns (PythStructs.Price memory) {
        return PythStructs.Price({ price: price, conf: 0, expo: expo, publishTime: block.timestamp });
    }

    function setParams(int64 _price, int32 _expo) external {
        price = _price;
        expo = _expo;
    }
}
