// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {MAX_MINT_FEE, MAX_BURN_FEE, BASE_6, BPS} from "contracts/utils/Constants.sol";
import "utils/src/Constants.sol";

/*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                   MAINNET CONSTANTS                                                
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

uint256 constant CHAIN_SOURCE = CHAIN_ETHEREUM;

address constant DEPLOYER = 0xfdA462548Ce04282f4B6D6619823a7C64Fdc0185;
address constant KEEPER = 0xcC617C6f9725eACC993ac626C7efC6B96476916E;
address constant NEW_DEPLOYER = 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701;
address constant NEW_KEEPER = 0xa9bbbDDe822789F123667044443dc7001fb43C01;

address constant EUROC = 0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c;
address constant EUROE = 0x820802Fa8a99901F52e39acD21177b0BE6EE2974;
address constant EURE = 0x3231Cb76718CDeF2155FC47b5286d82e6eDA273f;
address constant BC3M = 0x2F123cF3F37CE3328CC9B5b8415f9EC5109b45e7;
address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

/*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    FACET ADDRESSES                                                 
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

address constant DIAMOND_CUT_FACET = 0x53B7d70013dEC21A97F216e80eEFCF45F25c2900;
address constant DIAMOND_ETHERSCAN_FACET = 0xFa94Cd9d711de75695693c877BecA5473462Cf12;
address constant DIAMOND_LOUPE_FACET = 0x65Ddeedf8e68f26D787B678E28Af13fde0249967;
address constant GETTERS_FACET = 0xd1b575ED715e4630340BfdC4fB8A37dF3383C84a;
address constant REWARD_HANDLER_FACET = 0x770756e43b9ac742538850003791deF3020211F3;
address constant SETTERS_GOVERNOR_FACET = 0x1F37F93c6aA7d987AE04786145d3066EAb8EEB43;
address constant SETTERS_GUARDIAN_FACET = 0xdda8f002925a0DfB151c0EaCb48d7136ce6a999F;
address constant SWAPPER_FACET = 0x06c33a0C80C3970cbeDDE641C7A6419d703D93d7;
address constant REDEEMER_FACET = 0x1e45b65CdD3712fEf0024d063d6574A609985E59;

/*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    SAVINGS IMPLEM                                                  
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

address constant SAVINGS_IMPLEM = 0xfD2cCc920d498db30FBE9c13D5705aE2C72670F9;
