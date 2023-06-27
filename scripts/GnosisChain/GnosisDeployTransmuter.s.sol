// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import "stringutils/strings.sol";
import { CollateralSetupProd, Production } from "contracts/transmuter/configs/Production.sol";
import "contracts/transmuter/Storage.sol" as Storage;
import { DiamondCut } from "contracts/transmuter/facets/DiamondCut.sol";
import { DiamondLoupe } from "contracts/transmuter/facets/DiamondLoupe.sol";
import { DiamondProxy } from "contracts/transmuter/DiamondProxy.sol";
import { Getters } from "contracts/transmuter/facets/Getters.sol";
import { Redeemer } from "contracts/transmuter/facets/Redeemer.sol";
import { RewardHandler } from "contracts/transmuter/facets/RewardHandler.sol";
import { SettersGovernor } from "contracts/transmuter/facets/SettersGovernor.sol";
import { SettersGuardian } from "contracts/transmuter/facets/SettersGuardian.sol";
import { Swapper } from "contracts/transmuter/facets/Swapper.sol";
import { ITransmuter } from "interfaces/ITransmuter.sol";

contract GnosisDeployTransmuter is Script {
    using strings for *;

    address public config;
    string[] facetNames;
    address[] facetAddressList;

    function run() external {
        uint256 deployerPrivateKey = vm.deriveKey(vm.envString("MNEMONIC_GNOSIS"), 0);
        vm.startBroadcast(deployerPrivateKey);

        address deployer = vm.addr(deployerPrivateKey);

        /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        DEPLOY                                                      
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/
        // Deploy fakes Core borrow, agEUR, and collaterals

        // Config
        config = address(new Production());
        ITransmuter transmuter = _deployTransmuter(
            config,
            abi.encodeWithSelector(Production.initialize.selector, CORE_BORROW, AGEUR)
        );

        console.log("Transmuter deployed at: %s", address(transmuter));
        vm.stopBroadcast();

        /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    TODO GOVERNANCE                                                 
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/
        // Redeem
        // SettersGuardian.setRedemptionCurveParams(xRedeemFee, yRedeemFee);
        // SettersGuardian.togglePause(collaterals[0].token, ActionType.Redeem);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        HELPERS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    // @dev Deploys diamond and connects facets
    function _deployTransmuter(
        address _init,
        bytes memory _calldata
    ) internal virtual returns (ITransmuter transmuter) {
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
        Storage.FacetCut[] memory cut = new Storage.FacetCut[](n);
        for (uint256 i = 0; i < n; ++i) {
            cut[i] = Storage.FacetCut({
                facetAddress: facetAddressList[i],
                action: Storage.FacetCutAction.Add,
                functionSelectors: _generateSelectors(facetNames[i])
            });
        }

        // Deploy diamond
        transmuter = ITransmuter(address(new DiamondProxy(cut, _init, _calldata)));
    }

    // return array of function selectors for given facet name
    function _generateSelectors(string memory _facetName) internal returns (bytes4[] memory selectors) {
        //get string of contract methods
        string[] memory cmd = new string[](4);
        cmd[0] = "forge";
        cmd[1] = "inspect";
        cmd[2] = _facetName;
        cmd[3] = "methods";
        bytes memory res = vm.ffi(cmd);
        string memory st = string(res);

        // extract function signatures and take first 4 bytes of keccak
        strings.slice memory s = st.toSlice();
        strings.slice memory delim = ":".toSlice();
        strings.slice memory delim2 = ",".toSlice();
        selectors = new bytes4[]((s.count(delim)));
        for (uint i = 0; i < selectors.length; ++i) {
            s.split('"'.toSlice());
            selectors[i] = bytes4(s.split(delim).until('"'.toSlice()).keccak());
            s.split(delim2);
        }
        return selectors;
    }
}
