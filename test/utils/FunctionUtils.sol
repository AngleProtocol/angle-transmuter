// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { StdUtils } from "forge-std/Test.sol";
import "contracts/utils/Constants.sol";

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
        bool increasing,
        bool swap,
        int256 minFee,
        int256 maxFee
    ) internal view returns (uint64[] memory postThres, int64[] memory postIntercep) {
        if (maxFee == 0) maxFee = int256(BASE_9);
        if (minFee == 0) minFee = int256(0);
        thresholds[0] = increasing ? 0 : uint64(BASE_9);
        intercepts[0] = int64(bound(int256(intercepts[0]), minFee, maxFee));
        uint256 nbrInflexion = 1;
        for (uint256 i = 1; i < thresholds.length; ++i) {
            thresholds[i] = increasing
                ? uint64(bound(thresholds[i], thresholds[i - 1] + 1, BASE_9 - 1))
                : uint64(bound(thresholds[i], 0, thresholds[i - 1] - 1));
            intercepts[i] = !(!increasing && i == 1)
                ? int64(bound(int256(intercepts[i]), intercepts[i - 1], maxFee))
                : intercepts[i - 1]; // Because the first degment of a burnFees should be constant
            if (
                // For the swap functions we hardcoded BASE_12 as the maximum fees, after that it is considered as 100% fees
                (swap &&
                    (int256(BASE_9) <= int256(intercepts[i]) ||
                        int256(BASE_18) / (int256(BASE_9) - int256(intercepts[i])) - int256(BASE_9) >=
                        int256(BASE_12) - 1)) ||
                intercepts[i] == int256(BASE_9) ||
                (increasing && thresholds[i] == BASE_9 - 1) ||
                (!increasing && thresholds[i] == 0)
            ) {
                nbrInflexion = i + 1;
                break;
            }
        }
        if (swap) {
            for (uint256 i = 0; i < thresholds.length; ++i) {
                intercepts[i] = (int256(BASE_9) > int256(intercepts[i])) &&
                    (int256(BASE_18) / (int256(BASE_9) - int256(intercepts[i])) - int256(BASE_9) < int256(BASE_12))
                    ? int64(int256(BASE_18) / (int256(BASE_9) - int256(intercepts[i])) - int256(BASE_9))
                    : int64(int256(BASE_12)) - 1;
            }
        }
        postThres = new uint64[](nbrInflexion);
        postIntercep = new int64[](nbrInflexion);
        for (uint256 i; i < nbrInflexion; ++i) {
            postThres[i] = thresholds[i];
            postIntercep[i] = intercepts[i];
        }
    }
}
