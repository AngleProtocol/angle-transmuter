// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.12;

import "oz/token/ERC20/utils/SafeERC20.sol";
import "oz/utils/math/Math.sol";

import { LibManager } from "../libraries/LibManager.sol";

import "../Storage.sol";

/// @title LibHelpers
/// @author Angle Labs, Inc.
library LibHelpers {
    using SafeERC20 for IERC20;

    function transferCollateral(address token, address to, uint256 amount, ManagerStorage memory managerData) internal {
        if (amount > 0) {
            if (managerData.managerConfig.length != 0) LibManager.transfer(token, to, amount, managerData);
            else IERC20(token).safeTransfer(to, amount);
        }
    }

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
    function findLowerBound(
        bool increasingArray,
        uint64[] memory array,
        uint64 element
    ) internal pure returns (uint256) {
        if (array.length == 0) {
            return 0;
        }
        uint256 low = 1;
        uint256 high = array.length;

        if ((increasingArray && array[high - 1] <= element) || (!increasingArray && array[high - 1] >= element))
            return high - 1;

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
        // `low - 1` is the inclusive lower bound.
        return low - 1;
    }

    function piecewiseLinear(
        uint64 x,
        bool increasingArray,
        uint64[] memory xArray,
        int64[] memory yArray
    ) internal pure returns (int64) {
        uint256 indexLowerBound = findLowerBound(increasingArray, xArray, x);

        if (indexLowerBound == xArray.length - 1) return yArray[xArray.length - 1];
        if (increasingArray) {
            return
                yArray[indexLowerBound] +
                ((yArray[indexLowerBound + 1] - yArray[indexLowerBound]) * int64(x - xArray[indexLowerBound])) /
                int64(xArray[indexLowerBound + 1] - xArray[indexLowerBound]);
        } else {
            return
                yArray[indexLowerBound] +
                ((yArray[indexLowerBound + 1] - yArray[indexLowerBound]) * int64(xArray[indexLowerBound] - x)) /
                int64(xArray[indexLowerBound] - xArray[indexLowerBound + 1]);
        }
    }
}

