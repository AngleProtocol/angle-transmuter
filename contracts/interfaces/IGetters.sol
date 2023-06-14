// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.5.0;

import { IAccessControlManager } from "interfaces/IAccessControlManager.sol";
import { IAgToken } from "interfaces/IAgToken.sol";

import "../transmuter/Storage.sol";

/// @title IGetters
/// @author Angle Labs, Inc.
interface IGetters {
    /// @notice Checks whether a given `selector` is actually a valid selector corresponding to a function in one of the
    /// facets of the proxy
    function isValidSelector(bytes4 selector) external view returns (bool);

    /// @notice Reference to the `accessControlManager` contract of the system
    function accessControlManager() external view returns (IAccessControlManager);

    /// @notice Stablecoin minted by transmuter
    function agToken() external view returns (IAgToken);

    /// @notice Returns the list of collateral assets supported by the system
    function getCollateralList() external view returns (address[] memory);

    /// @notice Returns the decimals of a given `collateral`
    function getCollateralDecimals(address collateral) external view returns (uint8);

    /// @notice Returns the `xFee` and `yFee` arrays from which fees are computed when coming to mint
    /// with `collateral`
    function getCollateralMintFees(address collateral) external view returns (uint64[] memory, int64[] memory);

    /// @notice Returns the `xFee` and `yFee` arrays from which fees are computed when coming to burn
    /// for `collateral`
    function getCollateralBurnFees(address collateral) external view returns (uint64[] memory, int64[] memory);

    /// @notice Returns the `xFee` and `yFee` arrays used to compute the penalty factor depending on the collateral
    /// ratio when users come to redeem
    function getRedemptionFees() external view returns (uint64[] memory, int64[] memory);

    /// @notice Returns the collateral ratio of Transmuter in base `10**9` and a rounded version of the total amount
    /// of stablecoins issued
    function getCollateralRatio() external view returns (uint64 collatRatio, uint256 stablecoinsIssued);

    /// @notice Returns the total amount of stablecoins issued through Transmuter
    function getTotalIssued() external view returns (uint256 stablecoinsIssued);

    /// @notice Returns the amount of stablecoins issued from `collateral` and the total amount of stablecoins issued
    /// through Transmuter
    function getIssuedByCollateral(
        address collateral
    ) external view returns (uint256 stablecoinsFromCollateral, uint256 stablecoinsIssued);

    /// @notice Returns if a collateral is "managed" and the associated manager configuration
    function getManagerData(
        address collateral
    ) external view returns (bool isManaged, IERC20[] memory subCollaterals, bytes memory config);

    /// @notice Returns the oracle values associated to `collateral`
    /// @return mint Oracle value that will be used for `collateral` for a mint transaction
    /// @return burn Oracle value that will be used for `collateral` for a burn transaction. This value
    /// is computed using the oracle values of all the other `collateral` assets of the system.
    /// @return ratio Ratio, in base `10**18` between the oracle value of the `collateral` its target price.
    /// This value is 10**18 if the oracle is greater than the collateral price
    /// @return redemption Oracle value that would be used to price `collateral` when computing the collateral ratio
    /// during a redemption
    function getOracleValues(
        address collateral
    ) external view returns (uint256 mint, uint256 burn, uint256 ratio, uint256 redemption);

    /// @notice Returns the data used to compute oracle values for `collateral`
    /// @return readType Type of oracle (Chainlink, external smart contract, ...)
    /// @return targetType Type of target price for the collateral: is it that of the stablecoin or evolve
    /// following something like wstETH?
    /// @return data Extra data needed to read the oracle. For Chainlink type of oracles, this data is supposed to give
    /// the addresses of the Chainlink feeds to read, the stale periods for each feed, ...
    function getOracle(
        address collateral
    ) external view returns (OracleReadType readType, OracleTargetType targetType, bytes memory data);

    /// @notice Returns if the associated functionality is paused or not
    function isPaused(address collateral, ActionType action) external view returns (bool);

    /// @notice Returns if `sender` is trusted to update normalizers
    function isTrusted(address sender) external view returns (bool);

    /// @notice Returns if `sender` is trusted to update sell rewards
    function isTrustedSeller(address sender) external view returns (bool);

    /// @notice Checks whether `sender` is whitelisted for collaterals with type `whitelistType`
    function isWhitelistedForType(WhitelistType whitelistType, address sender) external view returns (bool);

    /// @notice Checks whether `sender` can deal with `collateral` during burns and redemptions
    function isWhitelistedForCollateral(address collateral, address sender) external view returns (bool);

    /// @notice Checks whether only whitelisted address can deal with `collateral` during burns and redemptions
    function isWhitelistedCollateral(address collateral) external view returns (bool);

    /// @notice Gets the data needed to deal with whitelists for `collateral`
    function getCollateralWhitelistData(address collateral) external view returns (bytes memory);
}
