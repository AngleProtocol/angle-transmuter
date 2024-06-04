// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "./utils/Utils.s.sol";
import { TransmuterDeploymentHelper } from "./utils/TransmuterDeploymentHelper.s.sol";
import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
import "stringutils/strings.sol";
import "./Constants.s.sol";

import { CollateralSetupProd, ProductionSidechain } from "contracts/transmuter/configs/ProductionSidechain.sol";
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
import { DummyDiamondImplementation } from "./generated/DummyDiamondImplementation.sol";
import { Swapper } from "contracts/transmuter/facets/Swapper.sol";
import { ITransmuter } from "interfaces/ITransmuter.sol";
import { Helpers } from "./Helpers.s.sol";

contract DeployTransmuterSidechain is TransmuterDeploymentHelper, Helpers {
    function run() external {
        // TODO: make sure that selectors are well generated `yarn generate` before running this script
        // Here the `selectors.json` file is normally up to date
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // TODO
        uint256 chain = CHAIN_BASE;
        uint256 hardCap = 1000 ether;
        address core = _chainToContract(chain, ContractType.CoreBorrow);
        address agToken = _chainToContract(chain, ContractType.AgUSD);
        StablecoinType fiat = StablecoinType.USD;

        // Config
        config = address(new ProductionSidechain());

        address dummyImplementation = address(new DummyDiamondImplementation());
        (address liquidStablecoin, address oracleLiquidStablecoin) = _chainToLiquidStablecoinAndOracle(chain, fiat);
        ITransmuter transmuter = _deployTransmuter(
            config,
            abi.encodeWithSelector(
                ProductionSidechain.initialize.selector,
                core,
                agToken,
                liquidStablecoin,
                oracleLiquidStablecoin,
                hardCap,
                dummyImplementation
            )
        );

        console.log("Transmuter on chain %s deployed at: %s", chain, address(transmuter));
        vm.stopBroadcast();
    }
}
