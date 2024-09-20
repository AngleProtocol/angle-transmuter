// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "./utils/Utils.s.sol";
import { console } from "forge-std/console.sol";
import { MultiBlockRebalancer } from "contracts/helpers/MultiBlockRebalancer.sol";
import { IAccessControlManager } from "contracts/utils/AccessControl.sol";
import { IAgToken } from "contracts/interfaces/IAgToken.sol";
import { ITransmuter } from "contracts/interfaces/ITransmuter.sol";
import "./Constants.s.sol";

contract DeployMultiBlockRebalancer is Utils {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address: ", deployer);
        uint256 maxMintAmount = 1000000e18;
        uint96 maxSlippage = 1e9 / 100;
        address agToken = _chainToContract(CHAIN_SOURCE, ContractType.AgEUR);
        address transmuter = _chainToContract(CHAIN_SOURCE, ContractType.TransmuterAgEUR);
        IAccessControlManager accessControlManager = ITransmuter(transmuter).accessControlManager();

        MultiBlockRebalancer harvester = new MultiBlockRebalancer(
            maxMintAmount,
            maxSlippage,
            accessControlManager,
            IAgToken(agToken),
            ITransmuter(transmuter)
        );
        console.log("HarvesterVault deployed at: ", address(harvester));

        vm.stopBroadcast();
    }
}
