// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import { IKeyringGuard } from "interfaces/external/Keyring/IKeyringGuard.sol";

import { LibStorage as s } from "./LibStorage.sol";

import "../../utils/Errors.sol";
import "../Storage.sol";

/// @title LibWhitelist
/// @author Angle Labs, Inc.
library LibWhitelist {
    /// @notice Checks whether `sender` is whitelisted for a collateral with `whitelistData`
    function checkWhitelist(bytes memory whitelistData, address sender) internal returns (bool) {
        (WhitelistType whitelistType, bytes memory data) = abi.decode(whitelistData, (WhitelistType, bytes));
        if (s.transmuterStorage().isWhitelistedForType[whitelistType][sender] > 0) return true;
        if (data.length != 0) {
            if (whitelistType == WhitelistType.BACKED) {
                address keyringGuard = abi.decode(data, (address));
                if (keyringGuard != address(0)) return IKeyringGuard(keyringGuard).isAuthorized(address(this), sender);
            }
        }
        return false;
    }
}
