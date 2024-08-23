// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Constants.s.sol";
import "./utils/Utils.s.sol";

/// @title Utils
/// @author Angle Labs, Inc.
contract Helpers is Utils {
    address public alice;
    address public bob;
    address public charlie;
    address public dylan;
    address public sweeper;

    function setUp() public virtual {
        super.setUpForks();

        alice = vm.addr(1);
        bob = vm.addr(2);
        charlie = vm.addr(3);
        dylan = vm.addr(4);
        sweeper = address(uint160(uint256(keccak256(abi.encodePacked("sweeper")))));
    }

    function _chainToLiquidStablecoinAndOracle(
        uint256 chain,
        StablecoinType fiat
    ) internal pure returns (address, address) {
        if (chain == CHAIN_ARBITRUM) {
            if (fiat == StablecoinType.USD)
                return (
                    address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831),
                    address(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3)
                );
            else revert("chain not supported");
        }
        if (chain == CHAIN_AVALANCHE) {
            // USDC
            if (fiat == StablecoinType.USD)
                return (
                    address(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E),
                    address(0xF096872672F44d6EBA71458D74fe67F9a77a23B9)
                );
            // EURC
            else return (address(0xC891EB4cbdEFf6e073e859e987815Ed1505c2ACD), address(0));
        }
        if (chain == CHAIN_BASE) {
            // USDC
            if (fiat == StablecoinType.USD)
                return (
                    address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913),
                    address(0x7e860098F58bBFC8648a4311b374B1D669a2bc6B)
                );
            else revert("chain not supported");
        }
        if (chain == CHAIN_BNB) {
            if (fiat == StablecoinType.USD) revert("chain not supported");
            else revert("chain not supported");
        }
        if (chain == CHAIN_CELO) {
            // USDC
            if (fiat == StablecoinType.USD)
                return (
                    address(0xcebA9300f2b948710d2653dD7B07f33A8B32118C),
                    address(0xc7A353BaE210aed958a1A2928b654938EC59DaB2)
                );
            else revert("chain not supported");
        }
        if (chain == CHAIN_ETHEREUM) {
            // USDC
            if (fiat == StablecoinType.USD)
                return (
                    address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48),
                    address(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6)
                );
            // EURC
            else return (address(0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c), address(0));
        }
        if (chain == CHAIN_LINEA) {
            if (fiat == StablecoinType.USD) revert("chain not supported");
            else revert("chain not supported");
        }
        if (chain == CHAIN_GNOSIS) {
            if (fiat == StablecoinType.USD)
                return (0xDDAfbb505ad214D7b80b1f830fcCc89B60fb7A83, 0x26C31ac71010aF62E6B486D1132E266D6298857D);
            // EURe
            else return (address(0xcB444e90D8198415266c6a2724b7900fb12FC56E), address(0));
        }
        if (chain == CHAIN_OPTIMISM) {
            // USDC
            if (fiat == StablecoinType.USD)
                return (
                    address(0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85),
                    address(0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3)
                );
            else revert("chain not supported");
        }
        if (chain == CHAIN_POLYGON) {
            // USDC
            if (fiat == StablecoinType.USD)
                return (
                    address(0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359),
                    address(0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7)
                );
            // EURe
            else return (address(0x18ec0A6E18E5bc3784fDd3a3634b31245ab704F6), address(0));
        }
        if (chain == CHAIN_POLYGONZKEVM) {
            if (fiat == StablecoinType.USD) revert("chain not supported");
            else revert("chain not supported");
        } else revert("chain not supported");
    }
}
