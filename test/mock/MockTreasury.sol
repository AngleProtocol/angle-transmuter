// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

interface IStablecoin {
    function addMinter(address minter) external;
}

contract MockTreasury {
    function addMinter(address _agToken, address _minter) external {
        IStablecoin(_agToken).addMinter(_minter);
    }
}
