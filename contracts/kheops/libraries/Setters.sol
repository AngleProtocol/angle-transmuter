// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Storage as s } from "./Storage.sol";
import { Utils } from "../utils/Utils.sol";
import { Oracle } from "./Oracle.sol";
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

    function setOracle(address collateral, bytes memory oracle) internal {
        KheopsStorage storage ks = s.kheopsStorage();
        Collateral storage collatInfo = ks.collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        Oracle.readMint(oracle); // Checks oracle validity
        collatInfo.oracle = oracle;
    }

    function setFees(address collateral, uint64[] memory xFee, int64[] memory yFee, bool mint) internal {
        KheopsStorage storage ks = s.kheopsStorage();
        Collateral storage collatInfo = ks.collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        uint8 setter;
        if (!mint) setter = 1;
        _checkFees(xFee, yFee, setter);
        if (mint) {
            collatInfo.xFeeMint = xFee;
            collatInfo.yFeeMint = yFee;
        } else {
            collatInfo.xFeeBurn = xFee;
            collatInfo.yFeeBurn = yFee;
        }
    }

    function _checkFees(uint64[] memory xFee, int64[] memory yFee, uint8 setter) private view {
        uint256 n = xFee.length;
        if (n != yFee.length || n == 0) revert InvalidParams();
        for (uint256 i = 0; i < n - 1; ++i) {
            if (
                (xFee[i] >= xFee[i + 1]) ||
                (setter == 0 && (yFee[i + 1] < yFee[i])) ||
                (setter == 1 && (yFee[i + 1] > yFee[i])) ||
                (setter == 2 && yFee[i] < 0) ||
                xFee[i] > uint64(BASE_9) ||
                yFee[i] < -int64(uint64(BASE_9)) ||
                yFee[i] > int64(uint64(BASE_9))
            ) revert InvalidParams();
        }

        KheopsStorage storage ks = s.kheopsStorage();
        address[] memory collateralListMem = ks.collateralList;
        uint256 length = collateralListMem.length;
        if (setter == 0 && yFee[0] < 0) {
            // Checking that the mint fee is still bigger than the smallest burn fee everywhere
            for (uint256 i; i < length; ++i) {
                int64[] memory burnFees = ks.collaterals[collateralListMem[i]].yFeeBurn;
                if (burnFees[burnFees.length - 1] + yFee[0] < 0) revert InvalidParams();
            }
        }
        if (setter == 1 && yFee[n - 1] < 0) {
            for (uint256 i; i < length; ++i) {
                int64[] memory mintFees = ks.collaterals[collateralListMem[i]].yFeeMint;
                if (mintFees[0] + yFee[n - 1] < 0) revert InvalidParams();
            }
        }
    }
}
