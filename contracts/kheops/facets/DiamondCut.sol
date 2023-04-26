// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.12;

import { IDiamondCut } from "../../interfaces/IDiamondCut.sol";
import { Diamond } from "../libraries/Diamond.sol";
import { AccessControl } from "../utils/AccessControl.sol";

// Remember to add the loupe functions from DiamondLoupe to the diamond.
// The loupe functions are required by the EIP2535 Diamonds standard

contract DiamondCut is IDiamondCut, AccessControl {
    /// @notice Add/replace/remove any number of functions and optionally execute
    ///         a function with delegatecall
    /// @param _diamondCut Contains the facet addresses and function selectors
    /// @param _init The address of the contract or facet to execute _calldata
    /// @param _calldata A function call, including function selector and arguments
    ///                  _calldata is executed with delegatecall on _init
    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external onlyGovernor {
        Diamond.diamondCut(_diamondCut, _init, _calldata);
    }
}
