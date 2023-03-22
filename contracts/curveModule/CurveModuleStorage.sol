// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/external/convex/IBooster.sol";
import "../interfaces/external/convex/IBaseRewardPool.sol";
import "../interfaces/external/convex/IClaimZap.sol";
import "../interfaces/external/convex/ICvxRewardPool.sol";
import "../interfaces/external/stakeDAO/IStakeCurveVault.sol";
import "../interfaces/external/stakeDAO/IClaimerRewards.sol";
import "../interfaces/external/stakeDAO/ILiquidityGauge.sol";
import "../interfaces/external/curve/IMetaPool2.sol";
import "../interfaces/ICurveModule.sol";
import "../interfaces/IMinter.sol";
import "../interfaces/ITreasury.sol";

import "../utils/Constants.sol";
import "../utils/AccessControl.sol";

/// @title CurveModuleStorage
/// @author Angle Labs
/// @notice This contract stores the references, parameters, and mappings for the CurveModule contract.
contract CurveModuleStorage is Initializable, AccessControl, Constants {
    // ================================= REFERENCES ================================

    /// @notice Reference to the `AmoMinter` contract
    IMinter public minter;

    // ================================= PARAMETERS ================================

    /// @notice Define the proportion of the AMO controlled by stakeDAO `amo`
    uint256 public stakeDAOProportion;

    // ================================= MAPPINGS ==================================

    /// @notice Maps a token supported by an AMO to the last known balance of it: it is needed to track
    /// gains and losses made on a specific token
    mapping(IERC20 => uint256) public lastBalances;
    /// @notice Maps a token to the loss made on it by the AMO
    mapping(IERC20 => uint256) public protocolDebts;
    /// @notice Maps a token to the gain made on it by the AMO
    mapping(IERC20 => uint256) public protocolGains;
    /// @notice Whether an address can call permissioned methods
    mapping(address => uint256) public isTrusted;

    uint256[43] private __gapStorage;

    // ================================= EVENTS ================================

    event Recovered(address tokenAddress, address to, uint256 amountToRecover);
    event TrustedToggled(address who, bool trusted);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}
}
