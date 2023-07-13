// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import { ITransmuter } from "interfaces/ITransmuter.sol";

import { DiamondProxy } from "contracts/transmuter/DiamondProxy.sol";
import "contracts/transmuter/Storage.sol";
import { DiamondCut } from "contracts/transmuter/facets/DiamondCut.sol";
import { DiamondLoupe } from "contracts/transmuter/facets/DiamondLoupe.sol";
import { Getters } from "contracts/transmuter/facets/Getters.sol";
import { Redeemer } from "contracts/transmuter/facets/Redeemer.sol";
import { RewardHandler } from "contracts/transmuter/facets/RewardHandler.sol";
import { SettersGovernor } from "contracts/transmuter/facets/SettersGovernor.sol";
import { SettersGuardian } from "contracts/transmuter/facets/SettersGuardian.sol";
import { Swapper } from "contracts/transmuter/facets/Swapper.sol";
import "contracts/utils/Errors.sol";
import { DummyDiamondImplementation } from "../../scripts/generated/DummyDiamondImplementation.sol";

import "./Helper.sol";

abstract contract Transmuter is Helper {
    // Diamond
    ITransmuter transmuter;

    string[] facetNames;
    address[] facetAddressList;

    // @dev Deploys diamond and connects facets
    function deployTransmuter(address _init, bytes memory _calldata) public virtual {
        // Deploy every facet
        facetNames.push("DiamondCut");
        facetAddressList.push(address(new DiamondCut()));

        facetNames.push("DiamondLoupe");
        facetAddressList.push(address(new DiamondLoupe()));

        facetNames.push("Getters");
        facetAddressList.push(address(new Getters()));

        facetNames.push("Redeemer");
        facetAddressList.push(address(new Redeemer()));

        facetNames.push("RewardHandler");
        facetAddressList.push(address(new RewardHandler()));

        facetNames.push("SettersGovernor");
        facetAddressList.push(address(new SettersGovernor()));

        facetNames.push("SettersGuardian");
        facetAddressList.push(address(new SettersGuardian()));

        facetNames.push("Swapper");
        facetAddressList.push(address(new Swapper()));

        // Build appropriate payload
        uint256 n = facetNames.length;
        FacetCut[] memory cut = new FacetCut[](n);
        for (uint256 i = 0; i < n; ++i) {
            cut[i] = FacetCut({
                facetAddress: facetAddressList[i],
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors(facetNames[i])
            });
        }

        // Deploy diamond
        transmuter = ITransmuter(address(new DiamondProxy(cut, _init, _calldata)));
    }

    // @dev Deploys diamond and connects facets
    function deployReplicaTransmuter(
        address _init,
        bytes memory _calldata
    ) public virtual returns (ITransmuter _transmuter) {
        // Build appropriate payload
        uint256 n = facetNames.length;
        FacetCut[] memory cut = new FacetCut[](n);
        for (uint256 i = 0; i < n; ++i) {
            cut[i] = FacetCut({
                facetAddress: facetAddressList[i],
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors(facetNames[i])
            });
        }

        // Deploy diamond
        _transmuter = ITransmuter(address(new DiamondProxy(cut, _init, _calldata)));

        return _transmuter;
    }

    // @dev Helper to deploy a given Facet
    function deployFacet(address facet, string memory name) public {
        bytes4[] memory fromGenSelectors = generateSelectors(name);

        // Array of functions to add
        FacetCut[] memory facetCut = new FacetCut[](1);
        facetCut[0] = FacetCut({
            facetAddress: address(facet),
            action: FacetCutAction.Add,
            functionSelectors: fromGenSelectors
        });

        // Add functions to diamond
        transmuter.diamondCut(facetCut, address(0x0), "");
    }
}
