// SPDX-License-Identifier: BUSL-1.1

pragma solidity >=0.5.0;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import "../Storage.sol";

/// @title ISetters
/// @author Angle Labs, Inc.
interface ISetters {
    /// @notice Adjusts the normalized amount of stablecoins issued from `collateral` by `amount`
    function adjustNormalizedStablecoins(address collateral, uint128 amount, bool addOrRemove) external;

    /// @notice Recovers `amount` of `token` from the Kheops contract
    function recoverERC20(address collateral, IERC20 token, address to, uint256 amount) external;

    /// @notice Sets a new access control manager address
    function setAccessControlManager(address _newAccessControlManager) external;

    /// @notice Sets (or unsets) a collateral manager  `collateral`
    function setCollateralManager(address collateral, ManagerStorage memory managerData) external;

    /// @notice Changes the pause status for mint or burn transactions for `collateral`
    function togglePause(address collateral, PauseType pausedType) external;

    /// @notice Changes the trusted status for `sender` when it comes to selling rewards or updating the normalizer
    function toggleTrusted(address sender, uint8 trustedType) external;

    /// @notice Add `collateral` as a supported collateral in the system
    function addCollateral(address collateral) external;

    /// @notice Revokes `collateral` from the system
    function revokeCollateral(address collateral) external;

    /// @notice Sets the mint or burn fees for `collateral`
    function setFees(address collateral, uint64[] memory xFee, int64[] memory yFee, bool mint) external;

    /// @notice Sets the parameters for the redemption curve
    function setRedemptionCurveParams(uint64[] memory xFee, int64[] memory yFee) external;

    /// @notice Sets the `oracleConfig` used to read the value of `collateral` for the mint, burn and redemption operations
    function setOracle(address collateral, bytes memory oracleConfig) external;

    /// @notice Updates the normalizer variable by `amount`
    function updateNormalizer(uint256 amount, bool increase) external returns (uint256);
}
