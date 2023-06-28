// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import "stringutils/strings.sol";
import { CollateralSetupProd, FakeGnosis } from "contracts/transmuter/configs/FakeGnosis.sol";
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
import { MockTokenPermit } from "borrow/mock/MockTokenPermit.sol";
import { MockCoreBorrow } from "borrow/mock/MockCoreBorrow.sol";
import { MockChainlinkOracle } from "../../../test/mock/MockChainlinkOracle.sol";

contract GnosisDeployTransmuter is Script {
    using strings for *;

    address public config;
    string[] facetNames;
    address[] facetAddressList;

    function run() external {
        uint256 deployerPrivateKey = vm.deriveKey(vm.envString("MNEMONIC_GNOSIS"), 0);
        vm.startBroadcast(deployerPrivateKey);

        address deployer = vm.addr(deployerPrivateKey);
        console.log("address: %s", deployer);

        /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        DEPLOY                                                      
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/
        // Deploy fakes Core borrow, agEUR, and collaterals

        MockCoreBorrow coreBorrow = new MockCoreBorrow();
        console.log("CoreBorrow deployed at: %s", address(coreBorrow));
        coreBorrow.toggleGovernor(deployer);

        MockTokenPermit agEUR = new MockTokenPermit("Mock-AgEUR", "Mock-AgEUR", 18);
        console.log("AgEUR deployed at: %s", address(agEUR));

        address[] memory _collateralAddresses = new address[](3);
        address[] memory _oracleAddresses = new address[](3);
        for (uint256 i; i < 3; i++) {
            MockTokenPermit collateral = new MockTokenPermit(
                string(abi.encodePacked("MockCollat", vm.toString(i))),
                string(abi.encodePacked("MockCollat", vm.toString(i))),
                uint8(6 * (i + 1))
            );
            _collateralAddresses[i] = address(collateral);
            console.log("Collateral %i deployed at: %s", i, address(collateral));

            MockChainlinkOracle oracle = new MockChainlinkOracle();
            console.log("oracle deployed at: %s", address(oracle));
            oracle.setLatestAnswer(1e8);
            _oracleAddresses[i] = address(oracle);
        }

        // Config
        config = address(new FakeGnosis());
        ITransmuter transmuter = _deployTransmuter(
            config,
            abi.encodeWithSelector(
                FakeGnosis.initialize.selector,
                coreBorrow,
                agEUR,
                _collateralAddresses,
                _oracleAddresses
            )
        );

        console.log("Transmuter deployed at: %s", address(transmuter));

        /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    TODO GOVERNANCE                                                 
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/
        // Redeem
        uint64[] memory xRedeemFee = new uint64[](1);
        int64[] memory yRedeemFee = new int64[](1);
        xRedeemFee[0] = 0;
        yRedeemFee[0] = 1e9;
        transmuter.setRedemptionCurveParams(xRedeemFee, yRedeemFee);
        transmuter.togglePause(address(0x0), Storage.ActionType.Redeem);

        vm.stopBroadcast();
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
