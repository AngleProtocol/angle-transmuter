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

pragma solidity ^0.8.12;

import "../interfaces/IOracle.sol";
import "../interfaces/IOracleFallback.sol";
import "../utils/AccessControl.sol";
import "../utils/Constants.sol";
import "../utils/Errors.sol";

/// @title BaseOracle
/// @author Angle Labs, Inc.
/// @notice Base Contract to be overriden by all contracts of the protocol
abstract contract BaseOracle is IOracle, AccessControl, Constants {
    /// @notice Constructor for an oracle using Chainlink with multiple pools to read from
    constructor(address _accessControlManager) {
        if (_accessControlManager == address(0)) revert ZeroAddress();
        accessControlManager = IAccessControlManager(_accessControlManager);
    }

    /// @notice Returns the price targeted by the oracle
    function targetPrice() public view virtual returns (uint256);

    /// @inheritdoc IOracle
    function read() public view virtual returns (uint256);

    /// @inheritdoc IOracle
    function readMint() external view returns (uint256 oracleValue) {
        oracleValue = read();
        uint256 _targetPrice = targetPrice();
        if (_targetPrice < oracleValue) oracleValue = _targetPrice;
    }

    /// @inheritdoc IOracle
    function readBurn() external view returns (uint256 oracleValue, uint256 deviation) {
        oracleValue = read();
        uint256 _targetPrice = targetPrice();
        deviation = _BASE_18;
        if (oracleValue < _targetPrice) {
            // TODO: does it work well in terms of non manipulability of the redemptions to give the prices like that
            deviation = (oracleValue * _BASE_18) / _targetPrice;
            // Overestimating the oracle value
            oracleValue = _targetPrice;
        }
    }
}
