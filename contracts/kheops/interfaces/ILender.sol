// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

interface ILender {
    function borrow(uint256 amount) external returns (uint256);

    function repay(uint256 amount) external;
}
