// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "../Storage.sol";
import "../../utils/Constants.sol";

library Storage {
    function diamondStorage() internal pure returns (DiamondStorage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    function kheopsStorage() internal pure returns (KheopsStorage storage ds) {
        bytes32 position = KHEOPS_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }
}
