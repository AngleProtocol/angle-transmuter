// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { LibManager } from "../libraries/LibManager.sol";
import "../Storage.sol";

/// @title LibHelper
/// @author Angle Labs, Inc.
library LibHelper {
    using SafeERC20 for IERC20;

    function transferCollateral(
        address token,
        address to,
        uint256 amount,
        bool revertIfNotEnough,
        ManagerStorage memory managerData
    ) internal {
        if (token != address(0)) LibManager.transfer(token, to, amount, revertIfNotEnough, managerData);
        else IERC20(token).safeTransfer(to, amount);
    }
}
