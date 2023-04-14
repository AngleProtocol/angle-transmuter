// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

/// @title FunctionUtils
/// @author Angle Labs, Inc.
contract FunctionUtils {
    /// @notice Computes the value of a linear by part function at a given point
    /// @param x Point of the function we want to compute
    /// @param xArray List of breaking points (in ascending order) that define the linear by part function
    /// @param yArray List of values at breaking points (not necessarily in ascending order)
    /// @dev The evolution of the linear by part function between two breaking points is linear
    /// @dev Before the first breaking point and after the last one, the function is constant with a value
    /// equal to the first or last value of the yArray
    /// @dev This function is relevant if `x` is between O and `1e9`. If `x` is greater than that, then
    /// everything will be as if `x` is equal to the greater element of the `xArray`
    function _piecewiseLinear(uint64 x, uint64[] memory xArray, int64[] memory yArray) internal pure returns (int64) {
        uint256 arrayLength = xArray.length;
        if (x >= xArray[arrayLength - 1]) {
            return yArray[arrayLength - 1];
        } else if (x <= xArray[0]) {
            return yArray[0];
        } else {
            uint256 lower;
            uint256 upper = arrayLength - 1;
            uint256 mid;
            while (upper - lower > 1) {
                mid = lower + (upper - lower) / 2;
                if (xArray[mid] <= x) {
                    lower = mid;
                } else {
                    upper = mid;
                }
            }
            if (yArray[upper] > yArray[lower]) {
                // There is no risk of overflow here as in the product of the difference of `y`
                // with the difference of `x`, the product is inferior to `1e9**2` which does not
                // overflow for `uint64`
                return
                    yArray[lower] +
                    ((yArray[upper] - yArray[lower]) * int64(x - xArray[lower])) /
                    int64((xArray[upper] - xArray[lower]));
            } else {
                return
                    yArray[lower] -
                    ((yArray[lower] - yArray[upper]) * int64(x - xArray[lower])) /
                    int64(xArray[upper] - xArray[lower]);
            }
        }
    }
}
