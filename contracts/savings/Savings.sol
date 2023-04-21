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

/// @title Savings
/// @author Angle Labs, Inc.
/// @notice Savings contract where users can deposit an `asset` and earn a yield on this asset determined
/// by `rate`
/// @dev This contract is functional if it has a mint right on the underlying `asset`
/// @dev The implementation assumes that `asset` is a safe contract to interact with, on which there cannot be reentrancy attacks
/// @dev The ERC4626 interface does not allow users to specify a slippage protection parameter for the main user entry points
/// (like `deposit`, `mint`, `redeem` or `withdraw`). Even though there should be no specific sandwiching issue here,
/// it is still recommended to interact with this contract through a router that can implement such a protection in case of.
contract Savings is ERC4626Upgradeable, AccessControl, Constants {
    using SafeERC20 for IERC20;
    using MathUpgradeable for uint256;

    // ========================== PARAMETERS / REFERENCES ==========================

    /// @notice Inflation rate (per second)
    uint256 public rate;

    /// @notice Last time rewards were accrued
    uint128 public lastUpdate;

    /// @notice Whether the contract is paused or not
    uint128 public paused;

    /// @notice Number of decimals for `_asset`
    uint256 internal _assetDecimals;

    uint256[46] private __gap;

    // ============================== EVENTS / ERRORS ==============================

    event Accrued(uint256 interest);
    event ToggledPause(uint128 pauseStatus);
    event RateUpdated(uint256 newRate);

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
        string memory _name,
        string memory _symbol,
        uint256 divizer
    ) public initializer {
        if (address(_accessControlManager) == address(0)) revert ZeroAddress();
        __ERC4626_init(asset_);
        __ERC20_init(_name, _symbol);
        accessControlManager = _accessControlManager;
        uint256 numDecimals = 10 ** (asset_.decimals());
        _assetDecimals = numDecimals;
        _deposit(msg.sender, address(this), numDecimals / divizer, _BASE_18 / divizer);
    }

    // ================================= MODIFIERS =================================

    /// @notice Checks whether the whole contract is paused or not
    modifier whenNotPaused() {
        if (paused > 0) revert Paused();
        _;
    }

    // =============================== CONTRACT LOGIC ==============================

    /// @notice Accrues interest to this contract by minting agTokens
    function _accrue() internal returns (uint256 newTotalAssets) {
        uint256 currentBalance = super.totalAssets();
        newTotalAssets = _computeUpdatedAssets(currentBalance, block.timestamp - lastUpdate);
        lastUpdate = uint128(block.timestamp);
        uint256 earned = newTotalAssets - currentBalance;
        if (earned > 0) {
            IAgToken(asset()).mint(address(this), earned);
            emit Accrued(earned);
        }
    }

    /// @notice Computes how much `currentBalance` held in the contract would be after `exp` time following
    /// the `rate` of increase
    function _computeUpdatedAssets(uint256 currentBalance, uint256 exp) internal view returns (uint256) {
        uint256 ratePerSecond = rate;
        if (exp == 0 || ratePerSecond == 0) return currentBalance;
        uint256 expMinusOne = exp - 1;
        uint256 expMinusTwo = exp > 2 ? exp - 2 : 0;
        uint256 basePowerTwo = (ratePerSecond * ratePerSecond + _HALF_BASE_27) / _BASE_27;
        uint256 basePowerThree = (basePowerTwo * ratePerSecond + _HALF_BASE_27) / _BASE_27;
        uint256 secondTerm = (exp * expMinusOne * basePowerTwo) / 2;
        uint256 thirdTerm = (exp * expMinusOne * expMinusTwo * basePowerThree) / 6;
        return (currentBalance * (_BASE_27 + ratePerSecond * exp + secondTerm + thirdTerm)) / _BASE_27;
    }

    // =========================== ERC4626 VIEW FUNCTIONS ==========================

    /// @inheritdoc ERC4626Upgradeable
    function totalAssets() public view override returns (uint256) {
        return _computeUpdatedAssets(super.totalAssets(), block.timestamp - lastUpdate);
    }

    // ======================= ERC4626 INTERACTION FUNCTIONS =======================

    /// @inheritdoc ERC4626Upgradeable
    function deposit(uint256 assets, address receiver) public override whenNotPaused returns (uint256 shares) {
        uint256 newTotalAssets = _accrue();
        shares = _convertToShares(assets, newTotalAssets, MathUpgradeable.Rounding.Down);
        _deposit(_msgSender(), receiver, assets, shares);
    }

    /// @inheritdoc ERC4626Upgradeable
    function mint(uint256 shares, address receiver) public override whenNotPaused returns (uint256 assets) {
        uint256 newTotalAssets = _accrue();
        assets = _convertToAssets(shares, newTotalAssets, MathUpgradeable.Rounding.Up);
        _deposit(_msgSender(), receiver, assets, shares);
    }

    /// @inheritdoc ERC4626Upgradeable
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override whenNotPaused returns (uint256 shares) {
        uint256 newTotalAssets = _accrue();
        shares = _convertToShares(assets, newTotalAssets, MathUpgradeable.Rounding.Up);
        _withdraw(_msgSender(), receiver, owner, assets, shares);
    }

    /// @inheritdoc ERC4626Upgradeable
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override whenNotPaused returns (uint256 assets) {
        uint256 newTotalAssets = _accrue();
        assets = _convertToAssets(shares, newTotalAssets, MathUpgradeable.Rounding.Down);
        _withdraw(_msgSender(), receiver, owner, assets, shares);
    }

    // ============================== INTERNAL HELPERS =============================

    /// @inheritdoc ERC4626Upgradeable
    function _convertToShares(
        uint256 assets,
        MathUpgradeable.Rounding rounding
    ) internal view override returns (uint256 shares) {
        return _convertToShares(assets, totalAssets(), rounding);
    }

    /// @notice Same as the function above except that the `totalAssets` value does not have to be recomputed here
    function _convertToShares(
        uint256 assets,
        uint256 newTotalAssets,
        MathUpgradeable.Rounding rounding
    ) internal view returns (uint256 shares) {
        uint256 supply = totalSupply();
        return
            (assets == 0 || supply == 0)
                ? assets.mulDiv(_BASE_18, _assetDecimals, rounding)
                : assets.mulDiv(supply, newTotalAssets, rounding);
    }

    /// @inheritdoc ERC4626Upgradeable
    function _convertToAssets(
        uint256 shares,
        MathUpgradeable.Rounding rounding
    ) internal view override returns (uint256 assets) {
        return _convertToAssets(shares, totalAssets(), rounding);
    }

    /// @notice Same as the function above except that the `totalAssets` value does not have to be recomputed here
    function _convertToAssets(
        uint256 shares,
        uint256 newTotalAssets,
        MathUpgradeable.Rounding rounding
    ) internal view returns (uint256 assets) {
        uint256 supply = totalSupply();
        return
            (supply == 0)
                ? shares.mulDiv(_assetDecimals, _BASE_18, rounding)
                : shares.mulDiv(newTotalAssets, supply, rounding);
    }

    // =================================== HELPER ==================================

    /// @notice Provides an estimated Annual Percentage Rate for base depositors on this contract
    function estimatedAPR() external view returns (uint256 apr) {
        return _computeUpdatedAssets(_BASE_18, 24 * 365 * 3600) - _BASE_18;
    }

    /// @notice Wrapper on top of the `computeUpdatedAssets` function
    function computeUpdatedAssets(uint256 _totalAssets, uint256 exp) external view returns (uint256) {
        return _computeUpdatedAssets(_totalAssets, exp);
    }

    // ================================= GOVERNANCE ================================

    /// @notice Pauses the contract
    function togglePause() external onlyGuardian {
        uint128 pauseStatus = 1 - paused;
        paused = pauseStatus;
        emit ToggledPause(pauseStatus);
    }

    /// @notice Updates the inflation rate for depositing `asset` in this contract
    function setRate(uint256 newRate) external onlyGovernor {
        _accrue();
        rate = newRate;
        emit RateUpdated(newRate);
    }
}
