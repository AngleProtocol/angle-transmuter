// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

/// @title IModule
/// @author Angle Labs, Inc.
interface IModule {
    /// @notice Returns the current balance and value of the asset
    /// @notice `value` should not be trickable by external participant
    /// as this function is called in `getCollateralRatio` and could inflate the collateral ratio
    /// when stable is under collateralise they have an incentive to inflate it up to 100%
    /// to get out with more tokens than expected.
    function getBalanceAndValue() external view returns (uint256, uint256);

    // It must return the address of the token
    function transfer(address receiver, uint256 amount) external;
}
