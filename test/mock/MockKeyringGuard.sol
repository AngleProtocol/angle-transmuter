// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

contract MockKeyringGuard {
    mapping(address => bool) public authorized;

    function isAuthorized(address, address to) external view returns (bool passed) {
        return authorized[to];
    }

    function setAuthorized(address to, bool status) external {
        authorized[to] = status;
    }
}
