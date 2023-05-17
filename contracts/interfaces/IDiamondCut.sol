// SPDX-License-Identifier: MIT

pragma solidity >=0.5.0;

import "../kheops/Storage.sol";

/// @title IDiamondCut
/// @author Angle Labs, Inc.
/// @dev Reference: EIP-2535 Diamonds
/// @dev Forked from https://github.com/mudgen/diamond-3/blob/master/contracts/interfaces/IDiamondCut.sol by mudgen
interface IDiamondCut {
    /// @notice Add/replace/remove any number of functions and optionally execute a function with delegatecall
    /// @param _diamondCut Contains the facet addresses and function selectors
    /// @param _init The address of the contract or facet to execute _calldata
    /// @param _calldata A function call, including function selector and arguments, executed with delegatecall on _init
    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) external;
}
