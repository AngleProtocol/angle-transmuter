// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.0;

import { DiamondLib } from "../libraries/DiamondLib.sol";
import { AccessControl } from "../utils/AccessControl.sol";

import "../../interfaces/IAccessControlManager.sol";

contract SettersFacet is AccessControl {
    function setAccessControlManager(IAccessControlManager _newAccessControlManager) external onlyGovernor {
        DiamondLib.setAccessControlManager(_newAccessControlManager);
    }
}
