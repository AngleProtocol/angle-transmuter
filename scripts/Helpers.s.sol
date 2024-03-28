// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Constants.s.sol";
import "./utils/Utils.s.sol";

/// @title Utils
/// @author Angle Labs, Inc.
contract Helpers is Utils {
    mapping(uint256 => uint256) internal forkIdentifier;
    uint256 public arbitrumFork;
    uint256 public avalancheFork;
    uint256 public ethereumFork;
    uint256 public optimismFork;
    uint256 public polygonFork;
    uint256 public gnosisFork;
    uint256 public bnbFork;
    uint256 public celoFork;
    uint256 public polygonZkEVMFork;
    uint256 public baseFork;
    uint256 public lineaFork;

    address public alice;
    address public bob;
    address public charlie;
    address public dylan;
    address public sweeper;

    function setUp() public virtual {
        ethereumFork = vm.createFork(vm.envString("ETH_NODE_URI_MAINNET"));
        arbitrumFork = vm.createFork(vm.envString("ETH_NODE_URI_ARBITRUM"));
        avalancheFork = vm.createFork(vm.envString("ETH_NODE_URI_AVALANCHE"));
        optimismFork = vm.createFork(vm.envString("ETH_NODE_URI_OPTIMISM"));
        polygonFork = vm.createFork(vm.envString("ETH_NODE_URI_POLYGON"));
        gnosisFork = vm.createFork(vm.envString("ETH_NODE_URI_GNOSIS"));
        bnbFork = vm.createFork(vm.envString("ETH_NODE_URI_BSC"));
        celoFork = vm.createFork(vm.envString("ETH_NODE_URI_CELO"));
        polygonZkEVMFork = vm.createFork(vm.envString("ETH_NODE_URI_POLYGON_ZKEVM"));
        baseFork = vm.createFork(vm.envString("ETH_NODE_URI_BASE"));
        lineaFork = vm.createFork(vm.envString("ETH_NODE_URI_LINEA"));

        forkIdentifier[CHAIN_ETHEREUM] = ethereumFork;
        forkIdentifier[CHAIN_ARBITRUM] = arbitrumFork;
        forkIdentifier[CHAIN_AVALANCHE] = avalancheFork;
        forkIdentifier[CHAIN_OPTIMISM] = optimismFork;
        forkIdentifier[CHAIN_POLYGON] = polygonFork;
        forkIdentifier[CHAIN_GNOSIS] = gnosisFork;
        forkIdentifier[CHAIN_BNB] = bnbFork;
        forkIdentifier[CHAIN_CELO] = celoFork;
        forkIdentifier[CHAIN_POLYGONZKEVM] = polygonZkEVMFork;
        forkIdentifier[CHAIN_BASE] = baseFork;
        forkIdentifier[CHAIN_LINEA] = lineaFork;

        alice = vm.addr(1);
        bob = vm.addr(2);
        charlie = vm.addr(3);
        dylan = vm.addr(4);
        sweeper = address(uint160(uint256(keccak256(abi.encodePacked("sweeper")))));
    }
}
