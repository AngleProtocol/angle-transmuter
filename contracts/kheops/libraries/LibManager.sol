// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "oz/token/ERC20/IERC20.sol";
import "oz/token/ERC20/utils/SafeERC20.sol";

import { LibHelpers } from "./LibHelpers.sol";
import { LibOracle, AggregatorV3Interface } from "./LibOracle.sol";
import { LibStorage as s } from "./LibStorage.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import "../Storage.sol";

/// @title LibManager
/// @author Angle Labs, Inc.
/// Mock implementation of what would be needed if a collateral was linked to a manager
library LibManager {
    using SafeERC20 for IERC20;

    function parseManagerData(ManagerStorage memory managerData) internal {}

    // Should implement this function to transfer underlying tokens to the right address
    // The facet itself will handle itself how to free the funds necessary
    /// @param token Is the actual token we want to send
    // TODO add element potentially for a refund or not
    function transfer(address token, address to, uint256 amount, ManagerStorage memory managerData) internal {
        (ManagerType managerType, bytes memory data) = abi.decode(managerData.managerConfig, (ManagerType, bytes));
        if (managerType == ManagerType.EXTERNAL) {
            address managerAddress = abi.decode(data, (address));
        }

        IERC20[] memory subCollaterals = managerData.subCollaterals;
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

    /// @notice Tries to remove all funds from the manager, except the underlying as reserves can handle it
    function pullAll(address collateral, ManagerStorage memory managerData) internal {}

    /// @notice Get all the token balances owned by the manager
    /// @return balances An array of size `subCollaterals` with current balances
    /// @return totalValue The sum of the balances corrected by an oracle
    /// @dev 'subCollaterals' should always have as first token the collateral itself
    function getUnderlyingBalances(
        ManagerStorage memory managerData
    ) internal view returns (uint256[] memory balances, uint256 totalValue) {
        // not optimal but mock contract
        KheopsStorage storage ks = s.kheopsStorage();

        IERC20[] memory subCollaterals = managerData.subCollaterals;
        (
            uint8[] memory tokenDecimals,
            AggregatorV3Interface[] memory oracles,
            uint32[] memory stalePeriods,
            uint8[] memory oracleIsMultiplied,
            uint8[] memory chainlinkDecimals
        ) = abi.decode(managerData.managerConfig, (uint8[], AggregatorV3Interface[], uint32[], uint8[], uint8[]));
        uint256 nbrCollaterals = subCollaterals.length;
        balances = new uint256[](nbrCollaterals);
        for (uint256 i = 0; i < nbrCollaterals; ++i) {
            balances[i] = subCollaterals[i].balanceOf(address(this));
            totalValue += i == 0
                ? (LibOracle.readRedemption(ks.collaterals[address(subCollaterals[i])].oracleConfig) *
                    LibHelpers.convertDecimalTo(balances[i], tokenDecimals[i], 18)) / BASE_18
                : LibOracle.readChainlinkFeed(
                    LibHelpers.convertDecimalTo(balances[i], tokenDecimals[i], 18),
                    oracles[i - 1],
                    oracleIsMultiplied[i - 1],
                    chainlinkDecimals[i - 1],
                    stalePeriods[i - 1]
                );
        }
    }

    /// @notice Return available underlying tokens, for instance if liquidity fully used and
    /// not withdrawable the function will return 0
    function maxAvailable(address collateral, ManagerStorage memory managerData) internal view returns (uint256) {
        // silence compilation
        managerData;
        return IERC20(collateral).balanceOf(address(this));
    }
}
