// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import { SafeCast } from "oz/utils/math/SafeCast.sol";
import { IERC20 } from "oz/interfaces/IERC20.sol";
import { IERC20Metadata } from "oz/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";

import { IAccessControlManager } from "interfaces/IAccessControlManager.sol";
import { ISettersGuardian } from "interfaces/ISetters.sol";

import { LibDiamond } from "../libraries/LibDiamond.sol";
import { LibHelpers } from "../libraries/LibHelpers.sol";
import { LibManager } from "../libraries/LibManager.sol";
import { LibRedeemer } from "../libraries/LibRedeemer.sol";
import { LibSetters } from "../libraries/LibSetters.sol";
import { LibStorage as s } from "../libraries/LibStorage.sol";
import { LibWhitelist } from "../libraries/LibWhitelist.sol";
import { AccessControlModifiers } from "./AccessControlModifiers.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import "../Storage.sol";

/// @title SettersGuardian
/// @author Angle Labs, Inc.
contract SettersGuardian is AccessControlModifiers, ISettersGuardian {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    event RedemptionCurveParamsSet(uint64[] xFee, int64[] yFee);
    event WhitelistStatusToggled(WhitelistType whitelistType, address indexed who, uint256 whitelistStatus);

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                  GUARDIAN FUNCTIONS                                                
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

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
        TransmuterStorage storage ks = s.transmuterStorage();
        LibSetters.checkFees(xFee, yFee, ActionType.Redeem);
        ks.xRedemptionCurve = xFee;
        ks.yRedemptionCurve = yFee;
        emit RedemptionCurveParamsSet(xFee, yFee);
    }

    /// @inheritdoc ISettersGuardian
    function toggleWhitelist(WhitelistType whitelistType, address who) external onlyGuardian {
        TransmuterStorage storage ks = s.transmuterStorage();
        uint256 whitelistStatus = 1 - ks.isWhitelistedForType[whitelistType][who];
        ks.isWhitelistedForType[whitelistType][who] = whitelistStatus;
        emit WhitelistStatusToggled(whitelistType, who, whitelistStatus);
    }
}
