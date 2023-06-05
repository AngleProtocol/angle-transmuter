// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "contracts/transmuter/Storage.sol";
import { LibDiamond } from "contracts/transmuter/libraries/LibDiamond.sol";
import { LibStorage as s } from "contracts/transmuter/libraries/LibStorage.sol";
import "contracts/utils/Errors.sol";

interface IMockFacet {
    function newFunction() external returns (uint256);

    function newFunction2() external returns (uint256);
}

/*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    NEW STRUCT                                                    
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

struct NewStorage {
    uint256 slot1;
}

bytes32 constant NEW_STORAGE_POSITION = keccak256("new.storage");

/*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    INITIALIZER                                                   
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

contract MockInitializer {
    function initialize() external {
        NewStorageExpanded storage newStorage;
        bytes32 position = NEW_STORAGE_POSITION;
        assembly {
            newStorage.slot := position
        }
        newStorage.slot1 = 2;
        newStorage.slot2 = 20; // This eventually corresponds to nothing
    }

    function initializeRevert() external pure returns (uint256) {
        revert();
    }

    error CustomError();

    function initializeRevertWithMessage() external pure returns (uint256) {
        revert CustomError();
    }
}

/*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    FACETS                                                      
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

contract MockPureFacet is IMockFacet {
    function newFunction() external pure returns (uint256) {
        return 1;
    }

    function newFunction2() external pure returns (uint256) {
        return 2;
    }
}

contract MockWriteFacet is IMockFacet {
    // Reads the new struct
    function newFunction() external view returns (uint256) {
        NewStorage storage newStorage;
        bytes32 position = NEW_STORAGE_POSITION;
        assembly {
            newStorage.slot := position
        }
        return newStorage.slot1;
    }

    // Write 1 in the new struct
    function newFunction2() external returns (uint256) {
        NewStorage storage newStorage;
        bytes32 position = NEW_STORAGE_POSITION;
        assembly {
            newStorage.slot := position
        }
        newStorage.slot1 = 1;
        return newStorage.slot1;
    }
}

struct NewStorageExpanded {
    uint256 slot1;
    uint256 slot2;
}

contract MockWriteExpanded is IMockFacet {
    // Reads the new struct
    function newFunction() external view returns (uint256) {
        NewStorageExpanded storage newStorage;
        bytes32 position = NEW_STORAGE_POSITION;
        assembly {
            newStorage.slot := position
        }
        return newStorage.slot1;
    }

    // Write 1 in the new struct
    function newFunction2() external view returns (uint256) {
        NewStorageExpanded storage newStorage;
        bytes32 position = NEW_STORAGE_POSITION;
        assembly {
            newStorage.slot := position
        }
        return newStorage.slot2;
    }
}

/*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                            DIAMOND PROXY IMMUTABLE                                             
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

contract DiamondProxy {
    function initialize() external {
        bytes4[] memory functionSelectors = new bytes4[](1);
        functionSelectors[0] = DiamondProxy.diamondCut.selector;

        FacetCut[] memory facetCut = new FacetCut[](1);
        facetCut[0] = FacetCut({
            facetAddress: address(this),
            action: FacetCutAction.Add,
            functionSelectors: functionSelectors
        });

        LibDiamond.diamondCut(facetCut, address(0), "0x");
    }

    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) external {
        LibDiamond.diamondCut(_diamondCut, _init, _calldata);
    }

    fallback() external payable {
        DiamondStorage storage ds = s.diamondStorage();
        // Get facet from function selector
        address facetAddress = ds.selectorInfo[msg.sig].facetAddress;
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
