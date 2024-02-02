// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import { StdAssertions } from "forge-std/Test.sol";
import "stringutils/strings.sol";

import { TransparentUpgradeableProxy } from "oz/proxy/transparent/TransparentUpgradeableProxy.sol";
import { CommonUtils } from "utils/src/CommonUtils.sol";
import { ContractType } from "utils/src/Constants.sol";

contract Utils is Script, StdAssertions, CommonUtils {
    using strings for *;

    string constant JSON_SELECTOR_PATH = "./scripts/selectors.json";
    string constant JSON_VANITY_PATH = "./scripts/vanity.json";

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        HELPERS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _assertArrayUint64(uint64[] memory _a, uint64[] memory _b) internal {
        assertEq(_a.length, _b.length);
        for (uint i = 0; i < _a.length; ++i) {
            assertEq(_a[i], _b[i]);
        }
    }

    function _assertArrayInt64(int64[] memory _a, int64[] memory _b) internal {
        assertEq(_a.length, _b.length);
        for (uint i = 0; i < _a.length; ++i) {
            assertEq(_a[i], _b[i]);
        }
    }

    function _bytes4ToBytes32(bytes4 _in) internal pure returns (bytes32 out) {
        assembly {
            out := _in
        }
    }

    function _arrayBytes4ToBytes32(bytes4[] memory _in) internal pure returns (bytes32[] memory out) {
        out = new bytes32[](_in.length);
        for (uint i = 0; i < _in.length; ++i) {
            out[i] = _bytes4ToBytes32(_in[i]);
        }
    }

    function _arrayBytes32ToBytes4(bytes32[] memory _in) internal pure returns (bytes4[] memory out) {
        out = new bytes4[](_in.length);
        for (uint i = 0; i < _in.length; ++i) {
            out[i] = bytes4(_in[i]);
        }
    }

    function consoleLogBytes4Array(bytes4[] memory _in) internal view {
        for (uint i = 0; i < _in.length; ++i) {
            console.logBytes4(_in[i]);
        }
    }
}
