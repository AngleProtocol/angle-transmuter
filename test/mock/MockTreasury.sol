// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

interface IStablecoin {
    function addMinter(address minter) external;
}

contract MockTreasury {
    uint256 public counter;

    function addMinter(address) external {
        counter += 1;
    }
}
