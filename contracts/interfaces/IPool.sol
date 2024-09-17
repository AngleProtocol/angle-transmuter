// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.5.0;

interface IPool {
    function deposit(uint256 assets, address lender) external returns (uint256 shares, uint256 transferInDayTimestamp);

    function requestRedeem(uint256 shares) external returns (uint256 assets);
}
