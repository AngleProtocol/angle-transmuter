// SPDX-License-Identifier: BUSL-1.1

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

import { IERC1155Receiver } from "oz/token/ERC1155/IERC1155Receiver.sol";

import { IDiamondCut } from "./IDiamondCut.sol";
import { IDiamondLoupe } from "./IDiamondLoupe.sol";
import { IGetters } from "./IGetters.sol";
import { IRedeemer } from "./IRedeemer.sol";
import { IRewardHandler } from "./IRewardHandler.sol";
import { ISetters } from "./ISetters.sol";
import { ISwapper } from "./ISwapper.sol";

/// @title ITransmuter
/// @author Angle Labs, Inc.
interface ITransmuter is
    IDiamondCut,
    IDiamondLoupe,
    IGetters,
    IRedeemer,
    IRewardHandler,
    ISetters,
    ISwapper,
    IERC1155Receiver
{

}
