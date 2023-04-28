// SPDX-License-Identifier: GPL-3.0

/*
                  *                                                  █                              
                *****                                               ▓▓▓                             
                  *                                               ▓▓▓▓▓▓▓                         
                                   *            ///.           ▓▓▓▓▓▓▓▓▓▓▓▓▓                       
                                 *****        ////////            ▓▓▓▓▓▓▓                          
                                   *       /////////////            ▓▓▓                             
                     ▓▓                  //////////////////          █         ▓▓                   
                   ▓▓  ▓▓             ///////////////////////                ▓▓   ▓▓                
                ▓▓       ▓▓        ////////////////////////////           ▓▓        ▓▓              
              ▓▓            ▓▓    /////////▓▓▓///////▓▓▓/////////       ▓▓             ▓▓            
           ▓▓                 ,////////////////////////////////////// ▓▓                 ▓▓         
        ▓▓                  //////////////////////////////////////////                     ▓▓      
      ▓▓                  //////////////////////▓▓▓▓/////////////////////                          
                       ,////////////////////////////////////////////////////                        
                    .//////////////////////////////////////////////////////////                     
                     .//////////////////////////██.,//////////////////////////█                     
                       .//////////////////////████..,./////////////////////██                       
                        ...////////////////███████.....,.////////////////███                        
                          ,.,////////////████████ ........,///////////████                          
                            .,.,//////█████████      ,.......///////████                            
                               ,..//████████           ........./████                               
                                 ..,██████                .....,███                                 
                                    .██                     ,.,█                                    
                                                                                                    
                                                                                                    
                                                                                                    
               ▓▓            ▓▓▓▓▓▓▓▓▓▓       ▓▓▓▓▓▓▓▓▓▓        ▓▓               ▓▓▓▓▓▓▓▓▓▓          
             ▓▓▓▓▓▓          ▓▓▓    ▓▓▓       ▓▓▓               ▓▓               ▓▓   ▓▓▓▓         
           ▓▓▓    ▓▓▓        ▓▓▓    ▓▓▓       ▓▓▓    ▓▓▓        ▓▓               ▓▓▓▓▓             
          ▓▓▓        ▓▓      ▓▓▓    ▓▓▓       ▓▓▓▓▓▓▓▓▓▓        ▓▓▓▓▓▓▓▓▓▓       ▓▓▓▓▓▓▓▓▓▓          
*/

pragma solidity ^0.8.17;

import "../external/openZeppelinExtensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

import "../utils/Errors.sol";
import "../utils/AccessControl.sol";
import "../utils/Constants.sol";

import "../interfaces/IERC4626.sol";
import "../interfaces/IAgToken.sol";
import "../interfaces/IKheops.sol";

/// @title SavingsVest
/// @author Angle Labs, Inc.
/// @notice Savings contract where users can deposit an `asset` and earn a yield on this asset when it is distributed
/// @dev This contract is functional if it has a mint right on the underlying `asset` and if it a trusted address for the kheops contract
/// @dev The implementation assumes that `asset` is a safe contract to interact with, on which there cannot be reentrancy attacks
/// @dev The ERC4626 interface does not allow users to specify a slippage protection parameter for the main user entry points
/// (like `deposit`, `mint`, `redeem` or `withdraw`). Even though there should be no specific sandwiching issue here,
/// it is still recommended to interact with this contract through a router that can implement such a protection in case of.
contract SavingsVest is ERC4626Upgradeable, AccessControl {
    using SafeERC20 for IERC20;
    using MathUpgradeable for uint256;

    // ========================== PARAMETERS / REFERENCES ==========================

    address public surplusManager;

    /// @notice Amount of profit that needs to be vested
    uint256 public vestingProfit;

    IKheops public kheops;

    /// @notice Last time rewards were accrued
    uint64 public lastUpdate;

    uint64 public protocolSafetyFee;

    /// @notice The period in seconds over which locked profit is unlocked
    /// @dev Cannot be 0 as it opens harvests up to sandwich attacks
    uint32 public vestingPeriod;

    uint32 public updateDelay;

    /// @notice Whether the contract is paused or not
    uint8 public paused;

    /// @notice Number of decimals for `_asset`
    uint8 internal _assetDecimals;

    uint256[46] private __gap;

    // ============================== EVENTS / ERRORS ==============================

    event FiledUint64(uint64 param, bytes32 what);

    // =============================== INITIALIZATION ==============================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    /// @notice Initializes the contract
    /// @param _accessControlManager Reference to the `AccessControlManager` contract
    /// @param _name Name of the savings contract
    /// @param _symbol Symbol of the savings contract
    /// @param divizer Quantifies how much the first initial deposit should (should be typically 1 for tokens like agEUR)
    /// @dev A first deposit is done at initialization to protect for the classical issue of ERC4626 contracts where the
    /// the first user of the contract tries to steal everyone else's tokens
    function initialize(
        IAccessControlManager _accessControlManager,
        IERC20MetadataUpgradeable asset_,
        IKheops _kheops,
        string memory _name,
        string memory _symbol,
        uint256 divizer
    ) public initializer {
        if (address(_accessControlManager) == address(0) || address(_kheops) == address(0)) revert ZeroAddress();
        __ERC4626_init(asset_);
        __ERC20_init(_name, _symbol);
        kheops = _kheops;
        accessControlManager = _accessControlManager;
        uint8 numDecimals = asset_.decimals();
        _assetDecimals = numDecimals;
        _deposit(msg.sender, address(this), 10 ** numDecimals / divizer, BASE_18 / divizer);
    }

    // ================================= MODIFIERS =================================

    /// @notice Checks whether the whole contract is paused or not
    modifier whenNotPaused() {
        if (paused > 0) revert Paused();
        _;
    }

    // =============================== CONTRACT LOGIC ==============================

    /// @notice Accrues interest to this contract by minting agTokens
    function accrue() external returns (uint256 minted) {
        if (block.timestamp - lastUpdate < updateDelay && !accessControlManager.isGovernorOrGuardian(msg.sender))
            revert NotAllowed();
        IKheops _kheops = kheops;
        IAgToken _agToken = IAgToken(asset());
        (uint64 collatRatio, uint256 reserves) = _kheops.getCollateralRatio();
        if (collatRatio > BASE_9) {
            minted = (collatRatio * reserves) / BASE_9 - reserves;
            _kheops.updateNormalizer(minted, true);
            uint256 surplusForProtocol = (minted * protocolSafetyFee) / BASE_9;
            address _surplusManager = surplusManager;
            _surplusManager = _surplusManager == address(0) ? address(_kheops) : _surplusManager;
            _agToken.mint(_surplusManager, surplusForProtocol);
            uint256 surplus = minted - surplusForProtocol;
            if (surplus != 0) {
                vestingProfit = (lockedProfit() + surplus);
                lastUpdate = uint64(block.timestamp);
                _agToken.mint(address(this), surplus);
            }
        } else {
            uint256 missing = reserves - (collatRatio * reserves) / BASE_9;
            uint256 currentLockedProfit = lockedProfit();
            missing = missing > currentLockedProfit ? currentLockedProfit : missing;
            if (missing > 0) {
                vestingProfit -= missing;
                lastUpdate = uint64(block.timestamp);
                _agToken.burnSelf(missing, address(this));
                _kheops.updateNormalizer(missing, false);
            }
        }
    }

    function lockedProfit() public view virtual returns (uint256) {
        // Get the last update and vesting delay.
        uint256 _lastUpdate = lastUpdate;
        uint256 _vestingPeriod = vestingPeriod;

        unchecked {
            // If the vesting period has passed, there is no locked profit.
            // This cannot overflow on human timescales
            if (block.timestamp >= _lastUpdate + _vestingPeriod) return 0;

            // Get the maximum amount we could return.
            uint256 currentlyVestingProfit = vestingProfit;

            // Compute how much profit remains locked based on the last time a profit was acknowledged and the vesting period
            // It's impossible for an update to be in the future, so this will never underflow.
            return currentlyVestingProfit - (currentlyVestingProfit * (block.timestamp - _lastUpdate)) / _vestingPeriod;
        }
    }

    // =========================== ERC4626 VIEW FUNCTIONS ==========================

    /// @inheritdoc ERC4626Upgradeable
    function totalAssets() public view override returns (uint256) {
        return super.totalAssets() - lockedProfit();
    }

    // ======================= ERC4626 INTERACTION FUNCTIONS =======================

    /// @inheritdoc ERC4626Upgradeable
    function deposit(uint256 assets, address receiver) public override whenNotPaused returns (uint256 shares) {
        shares = _convertToShares(assets, MathUpgradeable.Rounding.Down);
        _deposit(_msgSender(), receiver, assets, shares);
    }

    /// @inheritdoc ERC4626Upgradeable
    function mint(uint256 shares, address receiver) public override whenNotPaused returns (uint256 assets) {
        assets = _convertToAssets(shares, MathUpgradeable.Rounding.Up);
        _deposit(_msgSender(), receiver, assets, shares);
    }

    /// @inheritdoc ERC4626Upgradeable
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override whenNotPaused returns (uint256 shares) {
        shares = _convertToShares(assets, MathUpgradeable.Rounding.Up);
        _withdraw(_msgSender(), receiver, owner, assets, shares);
    }

    /// @inheritdoc ERC4626Upgradeable
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override whenNotPaused returns (uint256 assets) {
        assets = _convertToAssets(shares, MathUpgradeable.Rounding.Down);
        _withdraw(_msgSender(), receiver, owner, assets, shares);
    }

    // ============================== INTERNAL HELPERS =============================

    /// @notice Same as the function above except that the `totalAssets` value does not have to be recomputed here
    function _convertToShares(
        uint256 assets,
        MathUpgradeable.Rounding rounding
    ) internal view override returns (uint256 shares) {
        uint256 supply = totalSupply();
        return
            (assets == 0 || supply == 0)
                ? assets.mulDiv(BASE_18, 10 ** _assetDecimals, rounding)
                : assets.mulDiv(supply, totalAssets(), rounding);
    }

    /// @notice Same as the function above except that the `totalAssets` value does not have to be recomputed here
    function _convertToAssets(
        uint256 shares,
        MathUpgradeable.Rounding rounding
    ) internal view override returns (uint256 assets) {
        uint256 supply = totalSupply();
        return
            (supply == 0)
                ? shares.mulDiv(10 ** _assetDecimals, BASE_18, rounding)
                : shares.mulDiv(totalAssets(), supply, rounding);
    }

    // =================================== HELPER ==================================

    /// @notice Provides an estimated Annual Percentage Rate for base depositors on this contract
    function estimatedAPR() external view returns (uint256 apr) {
        uint256 currentlyVestingProfit = vestingProfit;
        uint256 weightedAssets = vestingPeriod * totalAssets();
        if (currentlyVestingProfit != 0 && weightedAssets != 0)
            apr = (currentlyVestingProfit * 3600 * 24 * 365 * BASE_9) / weightedAssets;
    }

    // ================================= GOVERNANCE ================================

    function setSurplusManager(address _surplusManager) external onlyGuardian {
        surplusManager = _surplusManager;
    }

    function setUint64(bytes32 what, uint64 param) external onlyGuardian {
        if (param > BASE_9) revert InvalidParam();
        else if (what == "PF") protocolSafetyFee = param;
        else if (what == "VP") vestingPeriod = uint32(param);
        else if (what == "UD") updateDelay = uint32(param);
        else if (what == "P") paused = uint8(param);
        else revert InvalidParam();
        emit FiledUint64(param, what);
    }
}
