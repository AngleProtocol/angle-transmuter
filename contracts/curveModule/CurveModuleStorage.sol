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
import "../kheops/interfaces/IKheops.sol";
import "../interfaces/IModule.sol";
import { IOracle } from "../interfaces/IOracle.sol";

import "../utils/Constants.sol";
import "../utils/AccessControl.sol";
import "../utils/FunctionUtils.sol";

/// @title CurveModuleStorage
/// @author Angle Labs
/// @notice This contract stores the references, parameters, and mappings for the CurveModule contract.
contract CurveModuleStorage is Initializable, AccessControl, FunctionUtils {
    // ================================= REFERENCES ================================

    /// @notice Reference to the `Minter` contract
    IKheops public kheops;

    /// @notice Address of the Curve pool on which this contract deposits liquidity
    IMetaPool2 public curvePool;

    /// @notice Address of the agToken
    IERC20 public agToken;

    /// @notice Address of the other token
    IERC20 public otherToken;

    /// @notice StakeDAO vault address
    IStakeCurveVault public stakeCurveVault;

    /// @notice StakeDAO gauge address
    ILiquidityGauge public stakeGauge;

    /// @notice Address of the Convex contract on which to claim rewards
    IConvexBaseRewardPool public convexBaseRewardPool;

    /// @notice Oracle contract for the other token
    IOracle public oracle;

    /// @notice Address of the contract handling liquidations of rewards accumulated
    address public rewardHandler;

    /// @notice List of reward tokens accruing to this contract
    IERC20[] public rewardTokens;

    // ================================= PARAMETERS ================================

    /// @notice Deviation threshold from which the other token is considered as depegged and liquidity must be pulled
    uint64 public oracleDeviationThreshold;

    /// @notice Slippage authorization when depositing/withdrawing from the pool
    uint64 public slippage;

    /// @notice Target proportion of `AgToken` in the pool
    uint64 public depositThreshold;

    /// @notice Limit above which AgToken should be removed from the pool
    uint64 public withdrawThreshold;

    /// @notice Decimals of the other token
    uint8 public decimalsOtherToken;

    /// @notice Index of agToken in the Curve pool
    uint16 public indexAgToken;

    /// @notice ID of the associated Convex pool
    uint16 public convexPoolId;

    /// @notice Whether permissionless adjust are paused or not
    uint8 public paused;

    /// @notice Defines the proportion of the LP tokens which should be staked on StakeDAO
    uint8 public stakeDAOProportion;

    // ================================= MAPPINGS ==================================

    uint256[43] private __gapStorage;

    // ================================= EVENTS ================================

    event Recovered(address tokenAddress, address to, uint256 amountToRecover);
    event ToggledPause(uint8 pauseStatus);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}
}
