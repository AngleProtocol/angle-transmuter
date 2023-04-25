// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import "../Structs.sol";

library Storage {
    bytes32 internal constant _DIAMOND_STORAGE_POSITION = keccak256("diamond.standard.diamond.storage");

    bytes32 internal constant _KHEOPS_STORAGE_POSITION = keccak256("diamond.standard.kheops.storage");

    function diamondStorage() internal pure returns (DiamondStorage storage ds) {
        bytes32 position = _DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    function kheopsStorage() internal pure returns (KheopsStorage storage ds) {
        bytes32 position = _KHEOPS_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }
}
