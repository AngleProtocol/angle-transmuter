// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { LibStorage as s } from "./LibStorage.sol";

import "../../utils/Errors.sol";
import "../Storage.sol";

/// @title LibWhitelist
/// @author Angle Labs, Inc.
library LibWhitelist {
    /// @notice Checks whether an address is whitelisted for a collateral with `whitelistData`
    function checkWhitelist(bytes memory whitelistData, address sender) internal view returns (bool) {
        (WhitelistType whitelistType, ) = parseWhitelistData(whitelistData);
        if (whitelistType == WhitelistType.BACKED) {
            if (s.transmuterStorage().isWhitelistedForType[whitelistType][sender] > 0) return true;
        }
        return false;
    }

    /// @notice Parses the whitelist data given for a collateral
    function parseWhitelistData(bytes memory whitelistData) internal pure returns (WhitelistType, bytes memory) {
        return abi.decode(whitelistData, (WhitelistType, bytes));
    }
}
