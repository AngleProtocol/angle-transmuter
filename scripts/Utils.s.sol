// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import { StdAssertions } from "forge-std/Test.sol";
import "stringutils/strings.sol";

contract Utils is Script, StdAssertions {
    using strings for *;

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

    // return array of function selectors for given facet name
    function _generateSelectors(string memory _facetName) internal returns (bytes4[] memory selectors) {
        //get string of contract methods
        string[] memory cmd = new string[](4);
        cmd[0] = "forge";
        cmd[1] = "inspect";
        cmd[2] = _facetName;
        cmd[3] = "methods";
        bytes memory res = vm.ffi(cmd);
        string memory st = string(res);

        // extract function signatures and take first 4 bytes of keccak
        strings.slice memory s = st.toSlice();
        strings.slice memory delim = ":".toSlice();
        strings.slice memory delim2 = ",".toSlice();
        selectors = new bytes4[]((s.count(delim)));
        for (uint i = 0; i < selectors.length; ++i) {
            s.split('"'.toSlice());
            selectors[i] = bytes4(s.split(delim).until('"'.toSlice()).keccak());
            s.split(delim2);
        }
        return selectors;
    }
}
