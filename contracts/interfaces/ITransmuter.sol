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
                ▓▓                ,////////////////////////////////////// ▓▓                 ▓▓         
              ▓▓                 //////////////////////////////////////////                     ▓▓      
            ▓▓                //////////////////////▓▓▓▓/////////////////////                          
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

pragma solidity >=0.5.0;

import { IDiamondCut } from "./IDiamondCut.sol";
import { IDiamondLoupe } from "./IDiamondLoupe.sol";
import { IGetters } from "./IGetters.sol";
import { IRedeemer } from "./IRedeemer.sol";
import { IRewardHandler } from "./IRewardHandler.sol";
import { ISettersGovernor, ISettersGuardian } from "./ISetters.sol";
import { ISwapper } from "./ISwapper.sol";
import { IEtherscan } from "./IEtherscan.sol";

/// @title ITransmuter
/// @author Angle Labs, Inc.
interface ITransmuter is
    IDiamondCut,
    IDiamondLoupe,
    IGetters,
    IRedeemer,
    IRewardHandler,
    ISettersGovernor,
    ISettersGuardian,
    ISwapper,
    IEtherscan
{

}
