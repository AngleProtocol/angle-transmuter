// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.17;

import { IDiamondCut } from "../interfaces/IDiamondCut.sol";

import { LibDiamond } from "../libraries/LibDiamond.sol";

import { AccessControlModifiers } from "../utils/AccessControlModifiers.sol";
import "../Storage.sol";

// Remember to add the loupe functions from DiamondLoupe to the diamond.
// The loupe functions are required by the EIP2535 Diamonds standard

/// @title DiamondCut
/// @author Nick Mudge <nick@perfectabstractions.com>, Twitter/Github: @mudgen
/// @dev Reference: EIP-2535 Diamonds
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
