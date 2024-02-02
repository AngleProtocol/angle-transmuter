// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import "interfaces/IDiamondLoupe.sol";

import { Test, stdError } from "forge-std/Test.sol";
import { CommonUtils } from "utils/src/CommonUtils.sol";

import "stringutils/strings.sol";

/******************************************************************************\
* Authors: Timo Neumann <timo@fyde.fi>
* EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
* Helper functions for the translation from the jest tests in the original repo
* to solidity tests.
/******************************************************************************/

abstract contract Helper is Test, CommonUtils {
    using strings for *;

    // helper to remove index from bytes4[] array
    function removeElement(uint index, bytes4[] memory array) public pure returns (bytes4[] memory) {
        bytes4[] memory newarray = new bytes4[](array.length - 1);
        uint j = 0;
        for (uint i = 0; i < array.length; ++i) {
            if (i != index) {
                newarray[j] = array[i];
                j += 1;
            }
        }
        return newarray;
    }

    // helper to remove value from bytes4[] array
    function removeElement(bytes4 el, bytes4[] memory array) public pure returns (bytes4[] memory) {
        for (uint i = 0; i < array.length; ++i) {
            if (array[i] == el) {
                return removeElement(i, array);
            }
        }
        return array;
    }

    function containsElement(bytes4[] memory array, bytes4 el) public pure returns (bool) {
        for (uint i = 0; i < array.length; ++i) {
            if (array[i] == el) {
                return true;
            }
        }

        return false;
    }

    function containsElement(address[] memory array, address el) public pure returns (bool) {
        for (uint i = 0; i < array.length; ++i) {
            if (array[i] == el) {
                return true;
            }
        }

        return false;
    }

    function sameMembers(bytes4[] memory array1, bytes4[] memory array2) public pure returns (bool) {
        if (array1.length != array2.length) {
            return false;
        }
        for (uint i = 0; i < array1.length; ++i) {
            if (containsElement(array1, array2[i])) {
                return true;
            }
        }

        return false;
    }
}
