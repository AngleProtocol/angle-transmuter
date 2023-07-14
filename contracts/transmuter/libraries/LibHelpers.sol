// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import { Math } from "oz/utils/math/Math.sol";

import "../Storage.sol";

/// @title LibHelpers
/// @author Angle Labs, Inc.
library LibHelpers {
    /// @notice Rebases the units of `amount` from `fromDecimals` to `toDecimals`
    function convertDecimalTo(uint256 amount, uint8 fromDecimals, uint8 toDecimals) internal pure returns (uint256) {
        if (fromDecimals > toDecimals) return amount / 10 ** (fromDecimals - toDecimals);
        else if (fromDecimals < toDecimals) return amount * 10 ** (toDecimals - fromDecimals);
        else return amount;
    }

    /// @notice Checks whether a `token` is in a list `tokens` and returns the index of the token in the list
    /// or -1 in the other case
    function checkList(address token, address[] memory tokens) internal pure returns (int256) {
        uint256 tokensLength = tokens.length;
        for (uint256 i = 0; i < tokensLength; ++i) {
            if (token == tokens[i]) return int256(i);
        }
        return -1;
    }

    /// @notice Searches a sorted `array` and returns the first index that contains a value strictly greater
    /// (or lower if increasingArray is false) to `element` minus 1
    /// @dev If no such index exists (i.e. all values in the array are strictly lesser/greater than `element`),
    /// either array length minus 1, or 0 are returned
    /// @dev The time complexity of the search is O(log n).
    /// @dev Inspired from OpenZeppelin Contracts v4.4.1:
    /// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Arrays.sol
    /// @dev Modified by Angle Labs to support `uint64`, monotonous arrays and exclusive upper bounds
    function findLowerBound(
        bool increasingArray,
        uint64[] memory array,
        uint64 normalizerArray,
        uint64 element
    ) internal pure returns (uint256) {
        if (array.length == 0) {
            return 0;
        }
        uint256 low = 1;
        uint256 high = array.length;

        if (
            (increasingArray && array[high - 1] * normalizerArray <= element) ||
            (!increasingArray && array[high - 1] * normalizerArray >= element)
        ) return high - 1;

        while (low < high) {
            uint256 mid = Math.average(low, high);

            // Note that mid will always be strictly less than high (i.e. it will be a valid array index)
            // because Math.average rounds down (it does integer division with truncation).
            if (increasingArray ? array[mid] * normalizerArray > element : array[mid] * normalizerArray < element) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        // At this point `low` is the exclusive upper bound.
        // `low - 1` is the inclusive lower bound.
        return low - 1;
    }

    /// @notice Evaluates for `x` a piecewise linear function defined with the breaking points in the arrays
    /// `xArray` and `yArray`
    /// @dev The values in the `xArray` must be increasing
    function piecewiseLinear(uint64 x, uint64[] memory xArray, int64[] memory yArray) internal pure returns (int64) {
        uint256 indexLowerBound = findLowerBound(true, xArray, 1, x);
        if (indexLowerBound == 0 && x < xArray[0]) return yArray[0];
        else if (indexLowerBound == xArray.length - 1) return yArray[xArray.length - 1];
        return
            yArray[indexLowerBound] +
            ((yArray[indexLowerBound + 1] - yArray[indexLowerBound]) * int64(x - xArray[indexLowerBound])) /
            int64(xArray[indexLowerBound + 1] - xArray[indexLowerBound]);
    }
}
