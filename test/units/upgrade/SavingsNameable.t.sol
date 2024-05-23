// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../utils/Helper.sol";
import { Test } from "forge-std/Test.sol";
import "utils/src/Constants.sol";
import { SavingsNameable } from "contracts/savings/nameable/SavingsNameable.sol";
import { ProxyAdmin } from "oz/proxy/transparent/ProxyAdmin.sol";
import { IERC20Metadata } from "oz/interfaces/IERC20Metadata.sol";
import { TransparentUpgradeableProxy } from "oz/proxy/transparent/TransparentUpgradeableProxy.sol";

contract SavingsNameableTest is Test, Helper {
    uint256 constant CHAIN = CHAIN_ETHEREUM;
    string constant CHAIN_NAME = "mainnet";

    address public savings;
    address public savingsImpl;

    uint208 public rate;
    uint40 public lastUpdate;
    uint8 public paused;
    uint256 public maxRate;
    uint256 public totalSupply;
    uint256 public totalAssets;
    uint256 public previewDeposit;
    uint256 public previewMint;
    uint256 public previewWithdraw;
    uint256 public previewRedeem;

    function setUp() public {
        vm.createSelectFork(CHAIN_NAME);

        savings = _chainToContract(CHAIN, ContractType.StUSD);

        assertEq(IERC20Metadata(savings).name(), "Staked USDA");
        assertEq(IERC20Metadata(savings).symbol(), "stUSD");
        rate = SavingsNameable(savings).rate();
        lastUpdate = SavingsNameable(savings).lastUpdate();
        paused = SavingsNameable(savings).paused();
        maxRate = SavingsNameable(savings).maxRate();
        totalSupply = SavingsNameable(savings).totalSupply();
        totalAssets = SavingsNameable(savings).totalAssets();
        previewDeposit = SavingsNameable(savings).previewDeposit(BASE_18);
        previewMint = SavingsNameable(savings).previewMint(BASE_18);
        previewWithdraw = SavingsNameable(savings).previewWithdraw(BASE_18);
        previewRedeem = SavingsNameable(savings).previewRedeem(BASE_18);

        savingsImpl = address(new SavingsNameable());
    }

    function _upgradeContract(string memory name, string memory symbol) internal {
        ProxyAdmin proxyAdmin;
        if (CHAIN == CHAIN_BASE || CHAIN == CHAIN_POLYGONZKEVM)
            proxyAdmin = ProxyAdmin(_chainToContract(CHAIN, ContractType.ProxyAdminGuardian));
        else proxyAdmin = ProxyAdmin(_chainToContract(CHAIN, ContractType.ProxyAdmin));

        address governor = _chainToContract(CHAIN, ContractType.GovernorMultisig);
        address guardian = _chainToContract(CHAIN, ContractType.GuardianMultisig);

        // vm.prank(guardian, guardian);
        if (CHAIN == CHAIN_BASE || CHAIN == CHAIN_POLYGONZKEVM) vm.prank(guardian, guardian);
        else vm.prank(governor, governor);
        proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(savings)), savingsImpl);

        vm.prank(governor, governor);
        SavingsNameable(savings).setNameAndSymbol(name, symbol);
    }

    function test_NameAndSymbol() public {
        _upgradeContract("Staked USDA", "stUSD");

        assertEq(IERC20Metadata(savings).name(), "Staked USDA");
        assertEq(IERC20Metadata(savings).symbol(), "stUSD");
    }

    function test_Rate() public {
        assertEq(SavingsNameable(savings).rate(), rate);
    }

    function test_LastUpdate() public {
        assertEq(SavingsNameable(savings).lastUpdate(), lastUpdate);
    }

    function test_Paused() public {
        assertEq(SavingsNameable(savings).paused(), paused);
    }

    function test_MaxRate() public {
        assertEq(SavingsNameable(savings).maxRate(), maxRate);
    }

    function test_TotalSupply() public {
        assertEq(SavingsNameable(savings).totalSupply(), totalSupply);
    }

    function test_TotalAssets() public {
        assertEq(SavingsNameable(savings).totalAssets(), totalAssets);
    }

    function test_PreviewDeposit() public {
        assertEq(SavingsNameable(savings).previewDeposit(BASE_18), previewDeposit);
    }

    function test_PreviewMint() public {
        assertEq(SavingsNameable(savings).previewMint(BASE_18), previewMint);
    }

    function test_PreviewWithdraw() public {
        assertEq(SavingsNameable(savings).previewWithdraw(BASE_18), previewWithdraw);
    }

    function test_PreviewRedeem() public {
        assertEq(SavingsNameable(savings).previewRedeem(BASE_18), previewRedeem);
    }
}
