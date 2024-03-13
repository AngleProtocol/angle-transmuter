// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "./utils/Utils.s.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import "stringutils/strings.sol";
import "./Constants.s.sol";
import {Helpers} from "./Helpers.s.sol";

import "contracts/utils/Errors.sol" as Errors;
import "contracts/transmuter/Storage.sol" as Storage;
import {Getters} from "contracts/transmuter/facets/Getters.sol";
import {Redeemer} from "contracts/transmuter/facets/Redeemer.sol";
import {SettersGovernor} from "contracts/transmuter/facets/SettersGovernor.sol";
import {SettersGuardian} from "contracts/transmuter/facets/SettersGuardian.sol";
import {Swapper} from "contracts/transmuter/facets/Swapper.sol";
import "contracts/transmuter/libraries/LibHelpers.sol";
import {ITransmuter} from "interfaces/ITransmuter.sol";
import "utils/src/Constants.sol";
import {IERC20} from "oz/interfaces/IERC20.sol";
import {OldTransmuter} from "test/scripts/UpdateTransmuterFacets.t.sol";

contract UpdateTransmuterFacets is Helpers {
    string[] replaceFacetNames;
    address[] facetAddressList;

    ITransmuter transmuter;
    IERC20 agEUR;
    address governor;
    bytes public oracleConfigEUROC;
    bytes public oracleConfigBC3M;

    function run() external {
        // TODO: make sure that selectors are well generated `yarn generate` before running this script
        // Here the `selectors.json` file is normally up to date
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        governor = _chainToContract(CHAIN_SOURCE, ContractType.Timelock);
        transmuter = ITransmuter(_chainToContract(CHAIN_SOURCE, ContractType.TransmuterAgEUR));
        agEUR = IERC20(_chainToContract(CHAIN_SOURCE, ContractType.AgEUR));

        Storage.FacetCut[] memory replaceCut;
        Storage.FacetCut[] memory addCut;

        replaceFacetNames.push("Getters");
        facetAddressList.push(address(new Getters()));
        console.log("Getters deployed at: ", facetAddressList[facetAddressList.length - 1]);

        replaceFacetNames.push("Redeemer");
        facetAddressList.push(address(new Redeemer()));
        console.log("Redeemer deployed at: ", facetAddressList[facetAddressList.length - 1]);

        replaceFacetNames.push("SettersGovernor");
        facetAddressList.push(address(new SettersGovernor()));
        console.log("SettersGovernor deployed at: ", facetAddressList[facetAddressList.length - 1]);

        replaceFacetNames.push("Swapper");
        facetAddressList.push(address(new Swapper()));
        console.log("Swapper deployed at: ", facetAddressList[facetAddressList.length - 1]);

        // TODO Governance should pass tx to upgrade them from the `angle-governance` repo
    }
}
