// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.17;

import { LibDiamond } from "./libraries/LibDiamond.sol";
import { LibStorage as s } from "./libraries/LibStorage.sol";

import "../utils/Errors.sol";
import "./Storage.sol";

/// @title DiamondProxy
/// @author Nick Mudge <nick@perfectabstractions.com>, Twitter/Github: @mudgen
/// @notice Implementation of a Diamond Proxy
/// @dev Reference: EIP-2535 Diamonds
contract DiamondProxy {
    constructor(FacetCut[] memory _diamondCut, address _init, bytes memory _calldata) payable {
        LibDiamond.diamondCut(_diamondCut, _init, _calldata);
    }

    /// @dev 1. Find the facet for the function that is called.
    /// @dev 2. Delegate the execution to the found facet via `delegatecall`.
    fallback() external payable {
        DiamondStorage storage ds = s.diamondStorage();
        // Get facet from function selector
        address facetAddress = ds.facetAddressAndSelectorPosition[msg.sig].facetAddress;
        if (facetAddress == address(0)) {
            revert FunctionNotFound(msg.sig);
        }

        assembly {
            // The pointer to the free memory slot
            let ptr := mload(0x40)
            // Copy function signature and arguments from calldata at zero position into memory at pointer position
            calldatacopy(ptr, 0, calldatasize())
            // Delegatecall method of the implementation contract returns 0 on error
            let result := delegatecall(gas(), facetAddress, ptr, calldatasize(), 0, 0)
            // Get the size of the last return data
            let size := returndatasize()
            // Copy the size length of bytes from return data at zero position to pointer position
            returndatacopy(ptr, 0, size)
            // Depending on the result value
            switch result
            case 0 {
                // End execution and revert state changes
                revert(ptr, size)
            }
            default {
                // Return data with length of size at pointers position
                return(ptr, size)
            }
        }
    }
}
