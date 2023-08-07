// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { Utils } from "../utils/Utils.s.sol";
import { TransmuterDeploymentHelper } from "../utils/TransmuterDeploymentHelper.s.sol";
import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
import "stringutils/strings.sol";
import { CollateralSetupProd, FakeGnosis } from "contracts/transmuter/configs/FakeGnosis.sol";
import "contracts/transmuter/Storage.sol" as Storage;
import { ITransmuter } from "interfaces/ITransmuter.sol";
import { MockTokenPermit } from "test/mock/MockTokenPermit.sol";
import { MockCoreBorrow } from "borrow/mock/MockCoreBorrow.sol";
import { DummyDiamondImplementation } from "../generated/DummyDiamondImplementation.sol";
import { MockChainlinkOracle } from "test/mock/MockChainlinkOracle.sol";

contract DeployTransmuterGnosis is TransmuterDeploymentHelper {
    using strings for *;
    using stdJson for string;

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

        // Redeem
        uint64[] memory xRedeemFee = new uint64[](1);
        int64[] memory yRedeemFee = new int64[](1);
        xRedeemFee[0] = 0;
        yRedeemFee[0] = 1e9;
        transmuter.setRedemptionCurveParams(xRedeemFee, yRedeemFee);
        transmuter.togglePause(address(0x0), Storage.ActionType.Redeem);

        vm.stopBroadcast();
    }
}
