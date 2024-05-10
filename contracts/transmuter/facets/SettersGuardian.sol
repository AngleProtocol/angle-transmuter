// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import { ISettersGuardian } from "interfaces/ISetters.sol";

import { LibSetters } from "../libraries/LibSetters.sol";
import { AccessControlModifiers } from "./AccessControlModifiers.sol";

import "../Storage.sol";

/// @title SettersGuardian
/// @author Angle Labs, Inc.
contract SettersGuardian is AccessControlModifiers, ISettersGuardian {
    /// @inheritdoc ISettersGuardian
    function togglePause(address collateral, ActionType pausedType) external onlyGuardian {
        LibSetters.togglePause(collateral, pausedType);
    }

    /// @inheritdoc ISettersGuardian
    function setFees(address collateral, uint64[] memory xFee, int64[] memory yFee, bool mint) external onlyGuardian {
        LibSetters.setFees(collateral, xFee, yFee, mint);
    }

    /// @inheritdoc ISettersGuardian
    function setRedemptionCurveParams(uint64[] memory xFee, int64[] memory yFee) external onlyGuardian {
        LibSetters.setRedemptionCurveParams(xFee, yFee);
    }

    /// @inheritdoc ISettersGuardian
    function toggleWhitelist(WhitelistType whitelistType, address who) external onlyGuardian {
        LibSetters.toggleWhitelist(whitelistType, who);
    }

    /// @inheritdoc ISettersGuardian
    function setStablecoinCap(address collateral, uint256 stablecoinCap) external onlyGuardian {
        LibSetters.setStablecoinCap(collateral, stablecoinCap);
    }
}
