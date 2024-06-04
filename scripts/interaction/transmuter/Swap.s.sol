// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "../../utils/Utils.s.sol";
import { console } from "forge-std/console.sol";
import "stringutils/strings.sol";
import "../../Constants.s.sol";

import "contracts/transmuter/Storage.sol" as Storage;
import { ITransmuter } from "interfaces/ITransmuter.sol";
import { Helpers } from "../../Helpers.s.sol";
import { IERC20 } from "oz/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "oz/token/ERC20/extensions/IERC20Metadata.sol";

contract SwapTransmuter is Utils, Helpers {
    ITransmuter public transmuter;
    address public tokenIn;
    uint256 public decimalsIn;
    address public tokenOut;
    uint256 public decimalsOut;
    uint256 public amount;

    function run() external {
        // TODO: make sure that selectors are well generated `yarn generate` before running this script
        // Here the `selectors.json` file is normally up to date
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // TODO
        {
            uint256 chain = CHAIN_GNOSIS;
            StablecoinType fiat = StablecoinType.USD;
            address agToken = _chainToContract(chain, ContractType.AgUSD);
            (address liquidStablecoin, ) = _chainToLiquidStablecoinAndOracle(chain, fiat);
            transmuter = ITransmuter(_chainToContract(chain, ContractType.TransmuterAgUSD));
            tokenIn = agToken;
            decimalsIn = IERC20Metadata(agToken).decimals();
            tokenOut = liquidStablecoin;
            decimalsOut = IERC20Metadata(liquidStablecoin).decimals();
            amount = 1.2375 ether;
        }
        // TODO END

        uint256 minAmountOut = (((amount * 10 ** decimalsOut) / 10 ** decimalsIn) * 99) / 100;

        IERC20(tokenIn).approve(address(transmuter), amount);
        transmuter.swapExactInput(amount, minAmountOut, tokenIn, tokenOut, deployer, 0);
        vm.stopBroadcast();
    }
}
