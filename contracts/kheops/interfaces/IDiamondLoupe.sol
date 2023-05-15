// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.5.0;

import "../Storage.sol";

/// @notice IDiamondLoupe
/// @author Nick Mudge <nick@perfectabstractions.com>, Twitter/Github: @mudgen
/// @dev Reference: EIP-2535 Diamonds
/// @dev A loupe is a small magnifying glass used to look at diamonds. The functions here look at diamonds
interface IDiamondLoupe {
    /// @notice Gets all facet addresses and their four byte function selectors.
    /// @return facets_ Facet
    function facets() external view returns (Facet[] memory facets_);

    /// @notice Gets all the function selectors supported by a specific facet.
    /// @param _facet The facet address.
    /// @return facetFunctionSelectors_
    function facetFunctionSelectors(address _facet) external view returns (bytes4[] memory facetFunctionSelectors_);

    /// @notice Get all the facet addresses used by a diamond.
    /// @return facetAddresses_
    function facetAddresses() external view returns (address[] memory facetAddresses_);

    /// @notice Gets the facet that supports the given selector.
    /// @dev If facet is not found return address(0).
    /// @param _functionSelector The function selector.
    /// @return facetAddress_ The facet address.
    function facetAddress(bytes4 _functionSelector) external view returns (address facetAddress_);
}
