// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/utils/math/Math.sol";

library Utils {
    function convertDecimalTo(uint256 amount, uint8 fromDecimals, uint8 toDecimals) internal pure returns (uint256) {
        if (fromDecimals > toDecimals) return amount / 10 ** (fromDecimals - toDecimals);
        else if (fromDecimals < toDecimals) return amount * 10 ** (toDecimals - fromDecimals);
        else return amount;
    }

    function checkForfeit(address token, address[] memory tokens) internal pure returns (int256) {
        for (uint256 i = 0; i < tokens.length; ++i) {
            // if tokens.length>type(uint256).max, then it will return a negative value if found
            // for no attack surface any negative value should be considered as not found
            if (token == tokens[i]) return int256(i);
        }

        return -1;
    }

    // Inspired from OpenZeppelin
    // OpenZeppelin Contracts v4.4.1 (utils/Arrays.sol)
    // https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Arrays.sol
    // Modified Angle Labs to support uint64, monotonous arrays and exclusive upper bounds
    /**
     * @dev Searches a sorted `array` and returns the first index that contains
     * a value strictly greater (or lower if increasingArray is false)  to `element`.
     * If no such index exists (i.e. all values in the array are strictly less/greater than `element`),
     * the array length is returned. Time complexity O(log n).
     *
     * `array` is expected to be sorted, and to contain no repeated elements.
     */
    function findUpperBound(
        bool increasingArray,
        uint64[] memory array,
        uint64 element
    ) internal pure returns (uint256) {
        if (array.length == 0) {
            return 0;
        }
        uint256 low = 0;
        uint256 high = array.length;

        if ((increasingArray && array[high - 1] <= element) || (!increasingArray && array[high - 1] >= element))
            return high;

        while (low < high) {
            uint256 mid = Math.average(low, high);

            // Note that mid will always be strictly less than high (i.e. it will be a valid array index)
            // because Math.average rounds down (it does integer division with truncation).
            if (increasingArray ? array[mid] > element : array[mid] < element) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        // At this point `low` is the exclusive upper bound.
        return low;
    }

    function piecewiseLinear(
        uint64 x,
        bool increasingArray,
        uint64[] memory xArray,
        uint64[] memory yArray
    ) internal pure returns (uint64) {
        uint256 indexUpperBound = findUpperBound(increasingArray, xArray, x);

        if (indexUpperBound == xArray.length) return yArray[xArray.length - 1];
        if (increasingArray) {
            return
                yArray[indexUpperBound - 1] +
                ((yArray[indexUpperBound] - yArray[indexUpperBound - 1]) * (x - xArray[indexUpperBound - 1])) /
                (xArray[indexUpperBound] - xArray[indexUpperBound - 1]);
        } else {
            return
                yArray[indexUpperBound - 1] -
                ((yArray[indexUpperBound] - yArray[indexUpperBound - 1]) * (xArray[indexUpperBound - 1] - x)) /
                (xArray[indexUpperBound - 1] - xArray[indexUpperBound]);
        }
    }
}
