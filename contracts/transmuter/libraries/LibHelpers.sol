// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "oz/token/ERC20/utils/SafeERC20.sol";
import "oz/utils/math/Math.sol";

import { LibManager } from "../libraries/LibManager.sol";

import "../Storage.sol";

/// @title LibHelpers
/// @author Angle Labs, Inc.
library LibHelpers {
    using SafeERC20 for IERC20;

    /// @notice Performs a collateral transfer from the contract or its underlying managers to another address
    function transferCollateralTo(
        address token,
        address to,
        uint256 amount,
        bool redeem,
        ManagerStorage memory managerData
    ) internal {
        if (amount > 0) {
            if (managerData.managerConfig.length != 0) LibManager.transferTo(token, to, amount, redeem, managerData);
            else IERC20(token).safeTransfer(to, amount);
        }
    }

    /// @notice Performs a collateral transfer to one of the contract of the Transmuter system depending on the
    /// `managerData` associated to `token`
    function transferCollateralFrom(address token, uint256 amount, ManagerStorage memory managerData) internal {
        if (amount > 0) {
            if (managerData.managerConfig.length != 0) LibManager.transferFrom(token, amount, managerData);
            else IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
    }

    /// @notice Rebases the units of `amount` from `fromDecimals` to `toDecimals`
    function convertDecimalTo(uint256 amount, uint8 fromDecimals, uint8 toDecimals) internal pure returns (uint256) {
        if (fromDecimals > toDecimals) return amount / 10 ** (fromDecimals - toDecimals);
        else if (fromDecimals < toDecimals) return amount * 10 ** (toDecimals - fromDecimals);
        else return amount;
    }

    /// @notice Checks whether a `token` is in a list `tokens` and returns the index of the token in the list
    /// or -1 in the other case
    function checkList(address token, address[] memory tokens) internal pure returns (int256) {
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (token == tokens[i]) return int256(i);
        }

        return -1;
    }

    /// @notice Searches a sorted `array` and returns the first index that contains a value strictly greater
    /// (or lower if increasingArray is false)  to `element`
    /// @dev If no such index exists (i.e. all values in the array are strictly less/greater than `element`),
    /// the array length is returned
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
    /// @dev The values in the `xArray` may be increasing or decreasing based on the value of `increasingArray`
    function piecewiseLinear(
        uint64 x,
        bool increasingArray,
        uint64[] memory xArray,
        int64[] memory yArray
    ) internal pure returns (int64) {
        uint256 indexLowerBound = findLowerBound(increasingArray, xArray, 1, x);

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
