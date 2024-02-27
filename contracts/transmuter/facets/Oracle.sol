// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import { IOracle } from "interfaces/IOracle.sol";

import { LibOracle } from "../libraries/LibOracle.sol";
import { LibStorage as s } from "../libraries/LibStorage.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import "../Storage.sol";

/// @title Getters
/// @author Angle Labs, Inc.
contract Oracle is IOracle {
    /// @inheritdoc IOracle
    function updateOracle(address collateral) external {
        if (s.transmuterStorage().isTrusted[msg.sender] == 0) revert NotTrusted();
        LibOracle.updateOracle(collateral);
    }
}
