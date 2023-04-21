// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

/// @title FunctionUtils
/// @author Angle Labs, Inc.
contract FunctionUtils {
    /// @dev This function should only be called in settings where:
    /// - `x1 <= x2`
    /// - `xFee` values are given in a strictly ascending order
    /// - yFee is monotonous
    /// - `xFee` and `yFee` must have the same length
    function _piecewiseMean(
        uint64 x1,
        uint64 x2,
        uint64[] memory xFee,
        int64[] memory yFee
    ) internal pure returns (int64 area) {
        uint256 n = xFee.length;
        if (n == 1) return yFee[0];
        uint64 xPos = x1;
        if (x1 < xFee[0]) {
            if (x2 <= xFee[0]) return yFee[0];
            else area += yFee[0] * int64(xFee[0] - x1);
        }
        if (x2 > xFee[n - 1]) {
            if (x1 >= xFee[n - 1]) return yFee[n - 1];
            else area += yFee[n - 1] * int64(x2 - xFee[n - 1]);
        }
        for (uint256 i; i < n - 1 && xPos <= x2; ++i) {
            uint64 xEnd = xFee[i + 1];
            if (xPos >= xEnd) continue;
            uint64 xStart = xFee[i];
            int64 yStart = yFee[i];
            int64 yEnd = yFee[i + 1];
            uint64 xSegmentStart = xPos > xStart ? xPos : xStart;
            // TODO check overflows here
            int64 ySegmentStart = yStart + (int64(xSegmentStart - xStart) * (yEnd - yStart)) / int64(xEnd - xStart);
            if (x1 == x2) return ySegmentStart;
            uint64 xSegmentEnd = x2 < xEnd ? x2 : xEnd;
            int64 ySegmentEnd = yStart + (int64(xSegmentEnd - xStart) * (yEnd - yStart)) / int64(xEnd - xStart);
            area += ((ySegmentStart + ySegmentEnd) * int64(xSegmentEnd - xSegmentStart)) / 2;
            xPos = xSegmentEnd;
        }

        return x1 == x2 ? area : area / int64(x2 - x1);
    }

    function _convertDecimalTo(uint256 amount, uint8 fromDecimals, uint8 toDecimals) internal pure returns (uint256) {
        if (fromDecimals > toDecimals) return amount / 10 ** (fromDecimals - toDecimals);
        else if (fromDecimals < toDecimals) return amount * 10 ** (toDecimals - fromDecimals);
        else return amount;
    }

    function _checkForfeit(address token, uint256 startIndex, address[] memory tokens) internal pure returns (int256) {
        for (uint256 i = startIndex; i < tokens.length; ++i) {
            // if tokens.length>type(uint256).max, then it will return a negative value if found
            // for no attack surface any negative value should be considered as not found
            if (token == tokens[i]) return int256(i);
        }

        return -1;
    }
}
