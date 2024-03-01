// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import "../Savings.sol";

/// @title SavingsNameable
/// @author Angle Labs, Inc.
contract SavingsNameable is Savings {

    string internal __name;

    string internal __symbol;

    uint256[48] private __gapNameable;

    /// @inheritdoc ERC20Upgradeable
    function name() public view override(ERC20Upgradeable, IERC20MetadataUpgradeable) returns (string memory) {
        return __name;
    }

    /// @inheritdoc ERC20Upgradeable
    function symbol() public view override(ERC20Upgradeable, IERC20MetadataUpgradeable) returns (string memory) {
        return __symbol;
    }

    /// @notice Updates the name and symbol of the token
    function setNameAndSymbol(string memory newName, string memory newSymbol) external onlyGovernor {
        __name = newName;
        __symbol = newSymbol;
    }


}