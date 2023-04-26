// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.0;

import { Storage as s } from "../libraries/Storage.sol";
import "../../utils/Constants.sol";

import "../Storage.sol";

/// @dev This contract is used only once to initialize the diamond proxy.
contract Test {
    function initialize(address _accessControlManager) external {
        DiamondStorage storage ds = s.diamondStorage();
        ds.accessControlManager = IAccessControlManager(_accessControlManager);
    }
}
