// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IXEVT {
    function isAllowed(address) external returns (bool);
}
