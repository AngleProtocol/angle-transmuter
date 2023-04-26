// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/IAgToken.sol";
import "../../interfaces/IModule.sol";
import "../../interfaces/IManager.sol";

library Utils {
    using SafeERC20 for IERC20;

    function transferCollateral(address collateral, address manager, address to, uint256 amount) internal {
        if (manager != address(0)) {
            IManager(manager).transfer(to, amount, false);
        } else {
            IERC20(collateral).safeTransfer(to, amount);
        }
    }

    /// @dev This function should only be called in settings where:
    /// - `x1 <= x2`
    /// - `xFee` values are given in a strictly ascending order
    /// - yFee is monotonous
    /// - `xFee` and `yFee` must have the same length
    function piecewiseMean(
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

        return area / int64(x2 - x1);
    }

    function findIndexThres(uint64 x, uint64[] memory xArray) internal pure returns (uint256 indexThres) {
        if (x >= xArray[xArray.length - 1]) {
            return xArray.length - 1;
        } else if (x <= xArray[0]) {
            return 0;
        } else {
            uint256 lower;
            uint256 upper = xArray.length - 1;
            uint256 mid;
            while (upper - lower > 1) {
                mid = lower + (upper - lower) / 2;
                if (xArray[mid] <= x) {
                    lower = mid;
                } else {
                    upper = mid;
                }
            }
            return lower;
        }
    }

    function convertDecimalTo(uint256 amount, uint8 fromDecimals, uint8 toDecimals) internal pure returns (uint256) {
        if (fromDecimals > toDecimals) return amount / 10 ** (fromDecimals - toDecimals);
        else if (fromDecimals < toDecimals) return amount * 10 ** (toDecimals - fromDecimals);
        else return amount;
    }

    function checkForfeit(address token, uint256 startIndex, address[] memory tokens) internal pure returns (int256) {
        for (uint256 i = startIndex; i < tokens.length; ++i) {
            // if tokens.length>type(uint256).max, then it will return a negative value if found
            // for no attack surface any negative value should be considered as not found
            if (token == tokens[i]) return int256(i);
        }

        return -1;
    }
}
