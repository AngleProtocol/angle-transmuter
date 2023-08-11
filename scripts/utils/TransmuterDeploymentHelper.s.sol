// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { Utils } from "./Utils.s.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";
import "stringutils/strings.sol";
import "../Constants.s.sol";

import { CollateralSetupProd, Production } from "contracts/transmuter/configs/Production.sol";
import "contracts/transmuter/Storage.sol" as Storage;
import { DiamondCut } from "contracts/transmuter/facets/DiamondCut.sol";
import { DiamondEtherscan } from "contracts/transmuter/facets/DiamondEtherscan.sol";
import { DiamondLoupe } from "contracts/transmuter/facets/DiamondLoupe.sol";
import { DiamondProxy } from "contracts/transmuter/DiamondProxy.sol";
import { Getters } from "contracts/transmuter/facets/Getters.sol";
import { Redeemer } from "contracts/transmuter/facets/Redeemer.sol";
import { RewardHandler } from "contracts/transmuter/facets/RewardHandler.sol";
import { SettersGovernor } from "contracts/transmuter/facets/SettersGovernor.sol";
import { SettersGuardian } from "contracts/transmuter/facets/SettersGuardian.sol";
import { DummyDiamondImplementation } from "../generated/DummyDiamondImplementation.sol";
import { Swapper } from "contracts/transmuter/facets/Swapper.sol";
import { ITransmuter } from "interfaces/ITransmuter.sol";

interface ImmutableCreate2Factory {
    function safeCreate2(bytes32 salt, bytes memory initCode) external payable returns (address deploymentAddress);

    function findCreate2Address(
        bytes32 salt,
        bytes calldata initCode
    ) external view returns (address deploymentAddress);

    function findCreate2AddressViaHash(
        bytes32 salt,
        bytes32 initCodeHash
    ) external view returns (address deploymentAddress);
}

contract TransmuterDeploymentHelper is Utils {
    using strings for *;
    using stdJson for string;

    address public config;
    string[] facetNames;
    address[] facetAddressList;

    error InvalidVanityAddress();

    /// @dev Deploys diamond and connects facets
    function _deployTransmuter(
        address _init,
        bytes memory _calldata
    ) internal virtual returns (ITransmuter transmuter) {
        // Deploy every facet
        facetNames.push("DiamondCut");
        facetAddressList.push(address(new DiamondCut()));

        facetNames.push("DiamondEtherscan");
        facetAddressList.push(address(new DiamondEtherscan()));

        facetNames.push("DiamondLoupe");
        facetAddressList.push(address(new DiamondLoupe()));

        facetNames.push("Getters");
        facetAddressList.push(address(new Getters()));

        facetNames.push("RewardHandler");
        facetAddressList.push(address(new RewardHandler()));

        facetNames.push("SettersGovernor");
        facetAddressList.push(address(new SettersGovernor()));

        facetNames.push("SettersGuardian");
        facetAddressList.push(address(new SettersGuardian()));

        facetNames.push("Swapper");
        facetAddressList.push(address(new Swapper()));

        facetNames.push("Redeemer");
        facetAddressList.push(address(new Redeemer()));

        string memory json = vm.readFile(JSON_SELECTOR_PATH);
        // Build appropriate payload
        uint256 n = facetNames.length;
        Storage.FacetCut[] memory cut = new Storage.FacetCut[](n);
        for (uint256 i = 0; i < n; ++i) {
            // Get Selectors from json
            bytes4[] memory selectors = _arrayBytes32ToBytes4(
                json.readBytes32Array(string.concat("$.", facetNames[i]))
            );
            cut[i] = Storage.FacetCut({
                facetAddress: facetAddressList[i],
                action: Storage.FacetCutAction.Add,
                functionSelectors: selectors
            });
        }

        bytes memory initCode = abi.encodePacked(type(DiamondProxy).creationCode, abi.encode(cut, _init, _calldata));
        console.logBytes(initCode);
        console.logBytes(type(DiamondProxy).creationCode);
        console.logBytes(abi.encode(cut));
        console.logBytes(abi.encode(_init));
        console.logBytes(abi.encode(_calldata));

        // Deploy diamond
        string memory jsonVanity = vm.readFile(JSON_VANITY_PATH);
        bytes32 salt = jsonVanity.readBytes32(string.concat("$.", "salt"));

        ImmutableCreate2Factory create2Factory = ImmutableCreate2Factory(IMMUTABLE_CREATE2_FACTORY_ADDRESS);

        address computedAddress = create2Factory.findCreate2Address(salt, initCode);
        console.log("Supposed to deploy: %s", address(computedAddress));
        if (computedAddress != 0x002535d40c962646418E26E00Bf810A4b77560C2) revert InvalidVanityAddress();

        transmuter = ITransmuter(create2Factory.safeCreate2(salt, initCode));
    }
}
