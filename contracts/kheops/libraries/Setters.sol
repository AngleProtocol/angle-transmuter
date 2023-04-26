// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Storage as s } from "./Storage.sol";
import "../Storage.sol";
import "../../utils/Constants.sol";
import "../../utils/Errors.sol";

library Setters {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function setAccessControlManager(IAccessControlManager _newAccessControlManager) internal {
        DiamondStorage storage ds = s.diamondStorage();
        IAccessControlManager previousAccessControlManager = ds.accessControlManager;
        ds.accessControlManager = _newAccessControlManager;
        emit OwnershipTransferred(address(previousAccessControlManager), address(_newAccessControlManager));
    }

    function addCollateral(address collateral) internal {
        KheopsStorage storage ks = s.kheopsStorage();
        Collateral storage collatInfo = ks.collaterals[collateral];
        if (collatInfo.decimals != 0) revert AlreadyAdded();
        collatInfo.decimals = uint8(IERC20Metadata(collateral).decimals());
        ks.collateralList.push(collateral);
    }
}
