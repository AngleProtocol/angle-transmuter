// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import { StdUtils } from "forge-std/Test.sol";
import "contracts/utils/Constants.sol";
//solhint-disable-next-line
import { console } from "forge-std/console.sol";

/// @title FunctionUtils
/// @author Angle Labs, Inc.
contract FunctionUtils is StdUtils {
    function _convertDecimalTo(uint256 amount, uint8 fromDecimals, uint8 toDecimals) internal pure returns (uint256) {
        if (fromDecimals > toDecimals) return amount / 10 ** (fromDecimals - toDecimals);
        else if (fromDecimals < toDecimals) return amount * 10 ** (toDecimals - fromDecimals);
        else return amount;
    }

    function _generateCurves(
        uint64[10] memory thresholds,
        int64[10] memory intercepts,
        bool increasing
    ) internal view returns (uint64[] memory postThres, int64[] memory postIntercep) {
        thresholds[0] = increasing ? 0 : uint64(BASE_9);
        intercepts[0] = int64(bound(int256(intercepts[0]), 0, int256(BASE_9)));
        uint256 nbrInflexion = 1;
        for (uint256 i = 1; i < thresholds.length; i++) {
            thresholds[i] = increasing
                ? uint64(bound(thresholds[i], thresholds[i - 1] + 1, BASE_9 - 1))
                : uint64(bound(thresholds[i], 0, thresholds[i - 1] - 1));
            intercepts[i] = int64(bound(int256(intercepts[i]), intercepts[i - 1], int256(BASE_9)));
            if (
                intercepts[i] == int256(BASE_9) ||
                (increasing && thresholds[i] == BASE_9 - 1) ||
                (!increasing && thresholds[i] == 0)
            ) {
                nbrInflexion = i + 1;
                break;
            }
        }
        postThres = new uint64[](nbrInflexion);
        postIntercep = new int64[](nbrInflexion);
        for (uint256 i; i < nbrInflexion; i++) {
            postThres[i] = thresholds[i];
            postIntercep[i] = intercepts[i];
        }
    }
}
