// // SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "contracts/savings/Savings.sol";
import "contracts/savings/SavingsVest.sol";
import "contracts/transmuter/facets/Swapper.sol";
import "contracts/transmuter/facets/Getters.sol";
import "contracts/transmuter/facets/Redeemer.sol";
import "contracts/transmuter/facets/RewardHandler.sol";
import "contracts/transmuter/facets/SettersGovernor.sol";
import "contracts/transmuter/facets/SettersGuardian.sol";
import "contracts/transmuter/facets/DiamondCut.sol";
import "contracts/transmuter/DiamondProxy.sol";
import "contracts/transmuter/Storage.sol";

// Workaround to have only 1 file to run slither on
contract Mock {

}
