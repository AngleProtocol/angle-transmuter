// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.12;

import { IDiamondCut } from "../interfaces/IDiamondCut.sol";

import { Diamond } from "../libraries/Diamond.sol";

import { AccessControlModifiers } from "../utils/AccessControlModifiers.sol";
import "../Storage.sol";

// Remember to add the loupe functions from DiamondLoupe to the diamond.
// The loupe functions are required by the EIP2535 Diamonds standard

contract DiamondCut is IDiamondCut, AccessControlModifiers {
    /// @inheritdoc IDiamondCut
    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external onlyGovernor {
        Diamond.diamondCut(_diamondCut, _init, _calldata);
    }
}
