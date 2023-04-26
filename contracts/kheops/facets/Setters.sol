// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.0;

import { Diamond } from "../libraries/Diamond.sol";
import { AccessControl } from "../utils/AccessControl.sol";

import "../../interfaces/IAccessControlManager.sol";

contract Setters is AccessControl {
    function setAccessControlManager(IAccessControlManager _newAccessControlManager) external onlyGovernor {
        Diamond.setAccessControlManager(_newAccessControlManager);
    }
}
