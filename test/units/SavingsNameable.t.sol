// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../utils/Helper.sol";
import { Test } from "forge-std/Test.sol";
import "utils/src/Constants.sol";
import { SavingsNameable } from "contracts/savings/nameable/SavingsNameable.sol";
import { ProxyAdmin } from "oz/proxy/transparent/ProxyAdmin.sol";
import { IERC20Metadata } from "oz/interfaces/IERC20Metadata.sol";
import { TransparentUpgradeableProxy } from "oz/proxy/transparent/TransparentUpgradeableProxy.sol";

contract SavingsNameablesTest is Test, Helper {

    address public savings;
    address public savingsImpl;

    function setUp() public {
        vm.createSelectFork("mainnet");

        savings = _chainToContract(CHAIN_ETHEREUM, ContractType.StEUR);
        savingsImpl = address(new SavingsNameable());
    }

    function _upgradeContract(string memory name, string memory symbol) internal {
        ProxyAdmin proxyAdmin = ProxyAdmin(_chainToContract(CHAIN_ETHEREUM, ContractType.ProxyAdmin));

        address governor = _chainToContract(CHAIN_ETHEREUM, ContractType.GovernorMultisig);
        vm.startPrank(governor, governor);

        proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(savings)), savingsImpl);
        SavingsNameable(savings).setNameAndSymbol(name, symbol);
    }

    function test_Name() public {
        assertEq(IERC20Metadata(savings).name(), "Staked agEUR");
    }

    function test_Symbol() public {
        assertEq(IERC20Metadata(savings).symbol(), "stEUR");
    }

    function test_setNameAndSymbol() public {
        _upgradeContract("Staked EURA", "stEUR");

        assertEq(IERC20Metadata(savings).name(), "Staked EURA");
        assertEq(IERC20Metadata(savings).symbol(), "stEUR");
    }
}
