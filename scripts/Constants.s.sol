// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

// TODO test fork on Arbitrum
uint256 constant BASE_6 = 1e6;
uint256 constant BASE_8 = 1e8;
uint256 constant BASE_9 = 1e9;
uint256 constant BASE_12 = 1e12;
uint256 constant BASE_18 = 1e18;
uint256 constant HALF_BASE_27 = 1e27 / 2;
uint256 constant BASE_27 = 1e27;
uint256 constant BASE_36 = 1e36;
uint256 constant MAX_BURN_FEE = 999_000_000;

address constant GOVERNOR = 0xdC4e6DFe07EFCa50a197DF15D9200883eF4Eb1c8;
address constant GUARDIAN = 0x0C2553e4B9dFA9f83b1A6D3EAB96c4bAaB42d430;
address constant PROXY_ADMIN = 0x1D941EF0D3Bba4ad67DBfBCeE5262F4CEE53A32b;
address constant PROXY_ADMIN_GUARDIAN = 0xD9F1A8e00b0EEbeDddd9aFEaB55019D55fcec017;
address constant CORE_BORROW = 0x5bc6BEf80DA563EBf6Df6D6913513fa9A7ec89BE;

/*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                  COLLATERALS RELATED                                               
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

address constant EUROC = 0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c;
address constant EUROE = 0x820802Fa8a99901F52e39acD21177b0BE6EE2974;
address constant EURE = 0x3231Cb76718CDeF2155FC47b5286d82e6eDA273f;

// // TODO on Mainnet

// import "contracts/utils/Constants.sol";

// address constant GOVERNOR = 0xdC4e6DFe07EFCa50a197DF15D9200883eF4Eb1c8;
// address constant GUARDIAN = 0x0C2553e4B9dFA9f83b1A6D3EAB96c4bAaB42d430;
// address constant PROXY_ADMIN = 0x1D941EF0D3Bba4ad67DBfBCeE5262F4CEE53A32b;
// address constant PROXY_ADMIN_GUARDIAN = 0xD9F1A8e00b0EEbeDddd9aFEaB55019D55fcec017;
// address constant CORE_BORROW = 0x5bc6BEf80DA563EBf6Df6D6913513fa9A7ec89BE;

// /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                   COLLATERALS RELATED
// //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

// address constant EUROC = 0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c;
// address constant EUROE = 0x820802Fa8a99901F52e39acD21177b0BE6EE2974;
// address constant EURE = 0x3231Cb76718CDeF2155FC47b5286d82e6eDA273f;

address constant CHAINLINK_EUROC_EUR = address(0x0);
address constant CHAINLINK_EUROE_EUR = address(0x0);
address constant CHAINLINK_EURE_EUR = address(0x0);
