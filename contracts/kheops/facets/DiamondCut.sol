// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import { IDiamondCut } from "interfaces/IDiamondCut.sol";

import { LibDiamond } from "../libraries/LibDiamond.sol";
import { AccessControlModifiers } from "./AccessControlModifiers.sol";

import "../Storage.sol";

/// @title DiamondCut
/// @author Angle Labs, Inc.
/// @dev Reference: EIP-2535 Diamonds
/// @dev Forked from https://github.com/mudgen/diamond-3/blob/master/contracts/facets/DiamondCutFacet.sol by mudgen

contract DiamondCut is IDiamondCut, AccessControlModifiers {
    /// @inheritdoc IDiamondCut
    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external onlyGovernor {
        LibDiamond.diamondCut(_diamondCut, _init, _calldata);
    }
}
