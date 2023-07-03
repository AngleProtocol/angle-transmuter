// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { Utils } from "./Utils.s.sol";
import { console } from "forge-std/console.sol";
import "stringutils/strings.sol";

contract GenerateSelectors is Utils {
    using strings for *;

    address public config;
    string[] facetNames;

    function run() external {
        facetNames.push("DiamondCut");
        facetNames.push("DiamondLoupe");
        facetNames.push("Getters");
        facetNames.push("Redeemer");
        facetNames.push("RewardHandler");
        facetNames.push("SettersGovernor");
        facetNames.push("SettersGuardian");
        facetNames.push("Swapper");
        facetNames.push("DiamondEtherscanFacet");

        string memory json = "";
        for (uint256 i = 0; i < facetNames.length; ++i) {
            bytes4[] memory selectors = _generateSelectors(facetNames[i]);
            vm.serializeBytes32(json, facetNames[i], _arrayBytes4ToBytes32(selectors));
        }
        string memory finalJson = vm.serializeString(json, "useless", "");
        vm.writeJson(finalJson, JSON_SELECTOR_PATH);
    }
}
