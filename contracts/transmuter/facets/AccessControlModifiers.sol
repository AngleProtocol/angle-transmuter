// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import { LibDiamond } from "../libraries/LibDiamond.sol";
import { LibStorage as s, TransmuterStorage } from "../libraries/LibStorage.sol";
import "../../utils/Errors.sol";
import "../../utils/Constants.sol";

/// @title AccessControlModifiers
/// @author Angle Labs, Inc.
contract AccessControlModifiers {
    /// @notice Checks whether the `msg.sender` has the governor role
    modifier onlyGovernor() {
        if (!LibDiamond.isGovernor(msg.sender)) revert NotGovernor();
        _;
    }

    /// @notice Checks whether the `msg.sender` has the guardian role
    modifier onlyGuardian() {
        if (!LibDiamond.isGovernorOrGuardian(msg.sender)) revert NotGovernorOrGuardian();
        _;
    }

    /// @notice Prevents a contract from calling itself, directly or indirectly
    /// @dev This implementation is an adaptation of the OpenZepellin `ReentrancyGuard` for the purpose of this
    /// Diamond Proxy system. The base implementation can be found here
    /// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/ReentrancyGuard.sol
    modifier nonReentrant() {
        TransmuterStorage storage ts = s.transmuterStorage();
        // Reentrant protection
        // On the first call, `_notEntered` will be true
        if (ts.statusReentrant == ENTERED) revert ReentrantCall();
        // Any calls to the `nonReentrant` modifier after this point will fail
        ts.statusReentrant = ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see https://eips.ethereum.org/EIPS/eip-2200)
        ts.statusReentrant = NOT_ENTERED;
    }
}
