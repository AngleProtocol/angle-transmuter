// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../utils/Helper.sol";
import { Test } from "forge-std/Test.sol";
import "utils/src/Constants.sol";
import { SavingsNameable } from "contracts/savings/nameable/SavingsNameable.sol";
import { ProxyAdmin } from "oz/proxy/transparent/ProxyAdmin.sol";
import { IERC20Metadata } from "oz/interfaces/IERC20Metadata.sol";
import { TransparentUpgradeableProxy } from "oz/proxy/transparent/TransparentUpgradeableProxy.sol";

contract SavingsNameableUpgradeTest is Test, Helper {
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
    address public governor;
    address public guardian;
    ProxyAdmin public proxyAdmin;

    function setUp() public {
        vm.createSelectFork(CHAIN_NAME);

        savings = _chainToContract(CHAIN, ContractType.StUSD);

        if (CHAIN == CHAIN_BASE || CHAIN == CHAIN_POLYGONZKEVM)
            proxyAdmin = ProxyAdmin(_chainToContract(CHAIN, ContractType.ProxyAdminGuardian));
        else proxyAdmin = ProxyAdmin(_chainToContract(CHAIN, ContractType.ProxyAdmin));
        governor = _chainToContract(CHAIN, ContractType.GovernorMultisig);
        guardian = _chainToContract(CHAIN, ContractType.GuardianMultisig);

        // TODO: to be removed when chainToContract works
        // savings = 0x0022228a2cc5E7eF0274A7Baa600d44da5aB5776;
        savings = 0x004626A008B1aCdC4c74ab51644093b155e59A23;
        proxyAdmin = ProxyAdmin(0x1D941EF0D3Bba4ad67DBfBCeE5262F4CEE53A32b);
        governor = 0xdC4e6DFe07EFCa50a197DF15D9200883eF4Eb1c8;
        guardian = 0x0C2553e4B9dFA9f83b1A6D3EAB96c4bAaB42d430;

        assertEq(IERC20Metadata(savings).name(), "Staked EURA");
        assertEq(IERC20Metadata(savings).symbol(), "stEUR");
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

        // savingsImpl = address(new SavingsNameable());
        savingsImpl = 0x2C28Bd22aB59341892e85aD76d159d127c4B03FA;
    }

    function _upgradeContract(string memory name, string memory symbol) internal {
        vm.prank(governor, governor);
        proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(savings)), savingsImpl);
        vm.prank(governor, governor);
        SavingsNameable(savings).setNameAndSymbol(name, symbol);
    }

    function test_UpdatedValues() public {
        _upgradeContract("Staked USDA", "stUSD");
        assertEq(IERC20Metadata(savings).name(), "Staked USDA");
        assertEq(IERC20Metadata(savings).symbol(), "stUSD");
        assertEq(SavingsNameable(savings).previewRedeem(BASE_18), previewRedeem);
        assertEq(SavingsNameable(savings).previewWithdraw(BASE_18), previewWithdraw);
        assertEq(SavingsNameable(savings).previewMint(BASE_18), previewMint);
        assertEq(SavingsNameable(savings).previewDeposit(BASE_18), previewDeposit);
        assertEq(SavingsNameable(savings).totalAssets(), totalAssets);
        assertEq(SavingsNameable(savings).totalSupply(), totalSupply);
        assertEq(SavingsNameable(savings).maxRate(), maxRate);
        assertEq(SavingsNameable(savings).paused(), paused);
        assertEq(SavingsNameable(savings).lastUpdate(), lastUpdate);
        assertEq(SavingsNameable(savings).rate(), rate);
    }
}
