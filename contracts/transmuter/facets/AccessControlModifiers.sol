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

    // @dev Fork from https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/ReentrancyGuard.sol
    // @dev Prevents a contract from calling itself, directly or indirectly.
    // Calling a `nonReentrant` function from another `nonReentrant`
    // function is not supported. It is possible to prevent this from happening
    // by making the `nonReentrant` function external, and making it call a
    // `private` function that does the actual work.
    modifier nonReentrant() {
        TransmuterStorage storage ts = s.transmuterStorage();
        // Reentrant protection
        // On the first call, _notEntered will be true
        if (ts.statusReentrant == ENTERED) revert ReentrantCall();
        // Any calls to nonReentrant after this point will fail
        ts.statusReentrant = ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        ts.statusReentrant = NOT_ENTERED;
    }
}
