// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import "oz/token/ERC20/IERC20.sol";
import "oz/token/ERC20/utils/SafeERC20.sol";

import { LibHelpers } from "../../contracts/transmuter/libraries/LibHelpers.sol";
import { LibOracle, AggregatorV3Interface } from "../../contracts/transmuter/libraries/LibOracle.sol";

import "../../contracts/utils/Constants.sol";
import "../../contracts/utils/Errors.sol";

contract MockManager {
    address public collateral;
    IERC20[] public subCollaterals;
    bytes public config;
    mapping(address => bool) public governors;
    mapping(address => bool) public guardians;

    constructor(address _collateral) {
        collateral = _collateral;
    }

    function setSubCollaterals(IERC20[] memory _subCollaterals, bytes memory _managerConfig) external {
        subCollaterals = _subCollaterals;
        config = _managerConfig;
    }

    function transferTo(address token, address to, uint256 amount) external {
        bool found;
        for (uint256 i; i < subCollaterals.length; ++i) {
            if (token == address(subCollaterals[i])) {
                found = true;
                break;
            }
        }
        if (!found) revert NotCollateral();
        IERC20(token).transfer(to, amount);
    }

    function withdrawAndTransfer(address token, address to, uint256 amount) external {
        bool found;
        for (uint256 i; i < subCollaterals.length; ++i) {
            if (token == address(subCollaterals[i])) {
                found = true;
                break;
            }
        }
        if (!found) revert NotCollateral();
        IERC20(token).transfer(to, amount);
    }

    function pullAll() external {
        for (uint256 i; i < subCollaterals.length; ++i) {
            subCollaterals[i].transfer(msg.sender, subCollaterals[i].balanceOf(address(this)));
        }
    }

    /// @notice Gets the balances of all the tokens controlled be the manager contract
    /// @return balances An array of size `subCollaterals` with current balances
    /// @return totalValue The sum of the balances corrected by an oracle
    function getUnderlyingBalances() external view returns (uint256[] memory balances, uint256 totalValue) {
        uint256 nbrCollaterals = subCollaterals.length;
        balances = new uint256[](nbrCollaterals);
        if (nbrCollaterals == 0) return (balances, totalValue);
        (
            uint8[] memory tokenDecimals,
            AggregatorV3Interface[] memory oracles,
            uint32[] memory stalePeriods,
            uint8[] memory oracleIsMultiplied,
            uint8[] memory chainlinkDecimals
        ) = abi.decode(config, (uint8[], AggregatorV3Interface[], uint32[], uint8[], uint8[]));

        for (uint256 i = 0; i < nbrCollaterals; ++i) {
            balances[i] = subCollaterals[i].balanceOf(address(this));
            if (i > 0) {
                totalValue += LibOracle.readChainlinkFeed(
                    LibHelpers.convertDecimalTo(balances[i], tokenDecimals[i], 18),
                    oracles[i - 1],
                    oracleIsMultiplied[i - 1],
                    chainlinkDecimals[i - 1],
                    stalePeriods[i - 1]
                );
            }
        }
    }

    /// @notice Gives the maximum amount of collateral immediately available for a transfer
    function maxAvailable() external view returns (uint256) {
        return IERC20(collateral).balanceOf(address(this));
    }
}
