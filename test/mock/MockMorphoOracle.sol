// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import { IMorphoOracle } from "contracts/interfaces/external/morpho/IMorphoOracle.sol";

contract MockMorphoOracle is IMorphoOracle {
    uint256 value;

    constructor(uint256 _value) {
        value = _value;
    }

    function price() external view returns (uint256) {
        return value;
    }

    function setValue(uint256 _value) external {
        value = _value;
    }
}
