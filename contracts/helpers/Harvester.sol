// // SPDX-License-Identifier: GPL-3.0

// pragma solidity ^0.8.19;

// import { IERC20 } from "oz/interfaces/IERC20.sol";
// import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";
// import { SafeCast } from "oz/utils/math/SafeCast.sol";

// import { ITransmuter } from "interfaces/ITransmuter.sol";

// import { AccessControl, IAccessControlManager } from "../utils/AccessControl.sol";
// import "../utils/Constants.sol";
// import "../utils/Errors.sol";

// import { RebalancerFlashloan } from "./RebalancerFlashloan.sol";

// /// @title Rebalancer
// /// @author Angle Labs, Inc.
// /// @notice Contract built to subsidize rebalances between collateral tokens
// /// @dev This contract is meant to "wrap" the Transmuter contract and provide a way for governance to
// /// subsidize rebalances between collateral tokens. Rebalances are done through 2 swaps collateral <> agToken.
// /// @dev This contract is not meant to hold any transient funds aside from the rebalancing budget
// contract Harvester is AccessControl {
//     using SafeERC20 for IERC20;
//     using SafeCast for uint256;

//     /// @notice Reference to the `transmuter` implementation this contract aims at rebalancing
//     ITransmuter public immutable TRANSMUTER;
//     /// @notice AgToken handled by the `transmuter` of interest
//     RebalancerFlashloan public rebalancer;

//     address public collateral;

//     address public vault;

//     uint64 public maxExposureYieldAsset;

//     uint64 public minExposureYieldAsset;

//     uint64 public targetExposureLiquid;

//     uint64 public maxSlippage;

//     /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                     INITIALIZATION                                                  
//     //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

//     /// @notice Initializes the immutable variables of the contract: `accessControlManager`, `transmuter` and `agToken`
//     constructor(RebalancerFlashloan _rebalancer, address _collateral, address _vault) {
//         ITransmuter _transmuter = _rebalancer.TRANSMUTER();
//         TRANSMUTER = _transmuter;
//         rebalancer = _rebalancer;
//         accessControlManager = IAccessControlManager(_transmuter.accessControlManager());
//         vault = _vault;
//         collateral = _collateral;
//         _getLimitExposuresYieldAsset();
//     }

//     // Due to potential transaction fees, multiple harvests may be needed to arrive at the target exposure
//     function harvest() external {
//         (uint256 stablecoinsFromCollateral, uint256 stablecoinsIssued) = TRANSMUTER.getIssuedByCollateral(collateral);
//         (uint256 stablecoinsFromVault, ) = TRANSMUTER.getIssuedByCollateral(vault);
//         uint8 increase;
//         uint256 amount;
//         if (stablecoinsFromCollateral * 1e9 > targetExposureLiquid * stablecoinsIssued) {
//             // Need to increase exposure to yield bearing asset
//             increase = 1;
//             amount = stablecoinsFromCollateral - (targetExposureLiquid * stablecoinsIssued) / 1e9;
//             if (stablecoinsFromVault + amount > (maxExposureYieldAsset * stablecoinsIssued) / 1e9) {
//                 amount = maxExposureYieldAsset * stablecoinsIssued - stablecoinsFromVault / 1e9;
//             }
//         } else {
//             amount = targetExposureLiquid * stablecoinsIssued - stablecoinsFromCollateral / 1e9;
//             if (amount >= stablecoinsFromVault) amount = stablecoinsFromVault;
//             if (stablecoinsFromVault - amount < (minExposureYieldAsset * stablecoinsIssued) / 1e9) {
//                 amount = stablecoinsFromVault - (minExposureYieldAsset * stablecoinsIssued) / 1e9;
//             }
//         }
//         TRANSMUTER.updateOracle(vault);
//         rebalancer.adjustYieldExposure(amount, increase, collateral, vault, (amount * (1e9 - maxSlippage)) / 1e9);
//     }

//     function setRebalancer(address _newRebalancer) external onlyGuardian {
//         rebalancer = _newRebalancer;
//         // Assumption is done that being built on the same Transmuter contract
//     }

//     function setTargetExposure(uint64 _targetExposure) external onlyGuardian {
//         targetExposureLiquid = _targetExposure;
//     }

//     function setMaxSlippage(uint64 _maxSlippage) external onlyGuardian {
//         maxSlippage = _maxSlippage;
//     }

//     function getLimitExposuresYieldAsset() external {
//         _getLimitExposuresYieldAsset();
//     }

//     function _getLimitExposuresYieldAsset() internal {
//         uint64[] memory xFeeMint;
//         (xFeeMint, ) = TRANSMUTER.getCollateralMintFees(vault);
//         uint256 length = xFeeMint.length;
//         if (length <= 1) maxExposureYieldAsset = 1e9;
//         else maxExposureYieldAsset = xFeeMint[length - 2];

//         uint64[] memory xFeeBurn;
//         (xFeeBurn, ) = TRANSMUTER.getCollateralBurnFees(vault);
//         length = xFeeBurn.length;
//         if (length <= 1) minExposureYieldAsset = 0;
//         else minExposureYieldAsset = xFeeBurn[length - 2];
//     }
// }
