// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import { IDiamondLoupe } from "interfaces/IDiamondLoupe.sol";

import { LibStorage as s } from "../libraries/LibStorage.sol";

import "../Storage.sol";

/// @title DiamondLoupe
/// @author Angle Labs, Inc.
/// @dev Reference: EIP-2535 Diamonds
/// @dev Forked from https://github.com/mudgen/diamond-3/blob/master/contracts/facets/DiamondLoupeFacet.sol by mudgen
contract DiamondLoupe is IDiamondLoupe {
    /// @inheritdoc IDiamondLoupe
    function facets() external view override returns (Facet[] memory facets_) {
        DiamondStorage storage ds = s.diamondStorage();
        uint256 selectorCount = ds.selectors.length;
        facets_ = new Facet[](selectorCount);
        uint16[] memory numFacetSelectors = new uint16[](selectorCount);
        uint256 numFacets;

        for (uint256 selectorIndex; selectorIndex < selectorCount; selectorIndex++) {
            bytes4 selector = ds.selectors[selectorIndex];
            address facetAddress_ = ds.selectorInfo[selector].facetAddress;
            bool continueLoop = false;
            // Find the functionSelectors array for selector and add selector to it
            for (uint256 facetIndex; facetIndex < numFacets; facetIndex++) {
                if (facets_[facetIndex].facetAddress == facetAddress_) {
                    facets_[facetIndex].functionSelectors[numFacetSelectors[facetIndex]] = selector;
                    numFacetSelectors[facetIndex]++;
                    continueLoop = true;
                    break;
                }
            }
            // If functionSelectors array exists for selector then continue loop
            if (continueLoop) {
                continueLoop = false;
                continue;
            }

            // Create a new functionSelectors array for selector
            facets_[numFacets].facetAddress = facetAddress_;
            facets_[numFacets].functionSelectors = new bytes4[](selectorCount);
            facets_[numFacets].functionSelectors[0] = selector;
            numFacetSelectors[numFacets] = 1;
            numFacets++;
        }
        for (uint256 facetIndex; facetIndex < numFacets; facetIndex++) {
            uint256 numSelectors = numFacetSelectors[facetIndex];
            bytes4[] memory selectors = facets_[facetIndex].functionSelectors;
            // Set the number of selectors
            assembly {
                mstore(selectors, numSelectors)
            }
        }
        // Set the number of facets
        assembly {
            mstore(facets_, numFacets)
        }
    }

    /// @inheritdoc IDiamondLoupe
    function facetFunctionSelectors(
        address _facet
    ) external view override returns (bytes4[] memory _facetFunctionSelectors) {
        DiamondStorage storage ds = s.diamondStorage();
        uint256 selectorCount = ds.selectors.length;
        uint256 numSelectors;
        _facetFunctionSelectors = new bytes4[](selectorCount);

        for (uint256 selectorIndex; selectorIndex < selectorCount; selectorIndex++) {
            bytes4 selector = ds.selectors[selectorIndex];
            address facetAddress_ = ds.selectorInfo[selector].facetAddress;
            if (_facet == facetAddress_) {
                _facetFunctionSelectors[numSelectors] = selector;
                numSelectors++;
            }
        }
        // Set the number of selectors in the array
        assembly {
            mstore(_facetFunctionSelectors, numSelectors)
        }
    }

    /// @inheritdoc IDiamondLoupe
    function facetAddresses() external view override returns (address[] memory facetAddresses_) {
        DiamondStorage storage ds = s.diamondStorage();
        uint256 selectorCount = ds.selectors.length;
        // Create an array set to the maximum size possible
        facetAddresses_ = new address[](selectorCount);
        uint256 numFacets;
        // Loop through function selectors
        for (uint256 selectorIndex; selectorIndex < selectorCount; selectorIndex++) {
            bytes4 selector = ds.selectors[selectorIndex];
            address facetAddress_ = ds.selectorInfo[selector].facetAddress;
            bool continueLoop = false;
            // See if we have collected the address already and break out of loop if we have
            for (uint256 facetIndex; facetIndex < numFacets; facetIndex++) {
                if (facetAddress_ == facetAddresses_[facetIndex]) {
                    continueLoop = true;
                    break;
                }
            }
            // Continue loop if we already have the address
            if (continueLoop) {
                continueLoop = false;
                continue;
            }
            // Include address
            facetAddresses_[numFacets] = facetAddress_;
            numFacets++;
        }
        // Set the number of facet addresses in the array
        assembly {
            mstore(facetAddresses_, numFacets)
        }
    }

    /// @inheritdoc IDiamondLoupe
    function facetAddress(bytes4 _functionSelector) external view override returns (address facetAddress_) {
        DiamondStorage storage ds = s.diamondStorage();
        facetAddress_ = ds.selectorInfo[_functionSelector].facetAddress;
    }
}
