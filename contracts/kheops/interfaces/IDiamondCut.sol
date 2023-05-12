// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.5.0;

import "../Storage.sol";

/// @title IDiamondCut
/// @dev EIP-235 Diamonds
/// @author Nick Mudge <nick@perfectabstractions.com>, Twitter/Github: @mudgen
interface IDiamondCut {
    /// @notice Add/replace/remove any number of functions and optionally execute a function with delegatecall
    /// @param _diamondCut Contains the facet addresses and function selectors
    /// @param _init The address of the contract or facet to execute _calldata
    /// @param _calldata A function call, including function selector and arguments, executed with delegatecall on _init
    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) external;
}
