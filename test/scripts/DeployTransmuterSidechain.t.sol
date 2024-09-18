// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { stdJson } from "forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";

import { CommonUtils } from "utils/src/CommonUtils.sol";
import "../../scripts/Constants.s.sol";

import "contracts/utils/Errors.sol" as Errors;
import "contracts/transmuter/Storage.sol" as Storage;
import "contracts/transmuter/libraries/LibHelpers.sol";
import { ITransmuter } from "interfaces/ITransmuter.sol";
import "utils/src/Constants.sol";
import { IERC20 } from "oz/interfaces/IERC20.sol";

interface ITreasury {
    function addMinter(address minter) external;
}

contract DeployTransmuterSidechainTest is Test, CommonUtils {
    using stdJson for string;

    ITransmuter transmuter;
    IERC20 agToken;
    ITreasury treasury;
    uint256 fork;
    address alice = vm.addr(1);
    IERC20 constant collateral = IERC20(0x60a3E35Cc302bFA44Cb288Bc5a4F316Fdb1adb42);
    address constant governor = 0x7DF37fc774843b678f586D55483819605228a0ae;

    function setUp() public {
        fork = vm.createSelectFork(vm.envString("ETH_NODE_URI_FORK"));
        vm.label(alice, "Alice");

        // TODO update
        uint256 chain = CHAIN_BASE;
        agToken = IERC20(_chainToContract(chain, ContractType.AgEUR));
        treasury = ITreasury(_chainToContract(chain, ContractType.TreasuryAgEUR));
        transmuter = ITransmuter(0x9DB174139C2f5a187492b762E36B6d61aB036Bb2);

        vm.prank(governor);
        treasury.addMinter(address(transmuter));
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        GETTERS
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testUnit_CheckState() external {
        assertEq(address(transmuter.agToken()), address(agToken));
        address[] memory collaterals = transmuter.getCollateralList();
        assertEq(collaterals.length, 1);
        assertEq(collaterals[0], address(collateral));
        assertEq(transmuter.getStablecoinCap(address(collateral)), 2_000_000 ether);
        assertEq(transmuter.getCollateralDecimals(address(collateral)), 6);
    }

    function testUnit_CheckOracle() external {
        (uint256 mint, uint256 burn, uint256 ratio, uint256 minRatio, uint256 redemption) = transmuter.getOracleValues(
            address(collateral)
        );
        assertEq(mint, BASE_18);
        assertEq(burn, BASE_18);
        assertEq(ratio, BASE_18);
        assertEq(minRatio, BASE_18);
        assertApproxEqRelDecimal(redemption, BASE_18, BASE_18 / 100, 18);
    }

    function testUnit_SwapExactInput_Mint() external {
        uint256 amount = 1_000_000 * 1e6;
        uint256 agTokenAmout = 1_000_000 ether;

        deal(address(collateral), alice, amount);

        vm.startPrank(alice);

        collateral.approve(address(transmuter), amount);
        transmuter.swapExactInput(amount, agTokenAmout - 1, address(collateral), address(agToken), alice, 0);

        assertGe(agToken.balanceOf(alice), agTokenAmout - 1);
        assertLe(agToken.balanceOf(alice), agTokenAmout);

        (uint256 stablecoinsFromCollateral, uint256 stablecoinsIssued) = transmuter.getIssuedByCollateral(
            address(collateral)
        );
        assertEq(stablecoinsFromCollateral, agTokenAmout);
        assertEq(stablecoinsIssued, agTokenAmout);

        vm.stopPrank();
    }

    function testUnit_SwapExactOutput_Mint() external {
        uint256 amount = 1_000_000 * 1e6;
        uint256 agTokenAmout = 1_000_000 ether;

        deal(address(collateral), alice, amount);

        vm.startPrank(alice);

        collateral.approve(address(transmuter), amount);
        transmuter.swapExactOutput(agTokenAmout, amount, address(collateral), address(agToken), alice, 0);

        assertEq(agToken.balanceOf(alice), agTokenAmout);

        (uint256 stablecoinsFromCollateral, uint256 stablecoinsIssued) = transmuter.getIssuedByCollateral(
            address(collateral)
        );
        assertEq(stablecoinsFromCollateral, agTokenAmout);
        assertEq(stablecoinsIssued, agTokenAmout);

        vm.stopPrank();
    }

    function testUnit_SwapExactInput_Burn() external {
        uint256 amount = 1_000_000 * 1e6;
        uint256 agTokenAmout = 1_000_000 ether;

        deal(address(collateral), alice, amount);

        vm.startPrank(alice);

        collateral.approve(address(transmuter), amount);
        // Mint
        transmuter.swapExactInput(amount, agTokenAmout - 1, address(collateral), address(agToken), alice, 0);
        // Burn
        transmuter.swapExactInput(agTokenAmout / 2, (amount - 1) / 2, address(agToken), address(collateral), alice, 0);

        assertEq(agToken.balanceOf(alice), agTokenAmout / 2);
        assertGe(collateral.balanceOf(alice), (amount - 1) / 2);
        assertLe(collateral.balanceOf(alice), amount / 2);

        (uint256 stablecoinsFromCollateral, uint256 stablecoinsIssued) = transmuter.getIssuedByCollateral(
            address(collateral)
        );
        assertEq(stablecoinsFromCollateral, agTokenAmout / 2);
        assertEq(stablecoinsIssued, agTokenAmout / 2);

        vm.stopPrank();
    }

    function testUnit_SwapExactOutput_Burn() external {
        uint256 amount = 1_000_000 * 1e6;
        uint256 agTokenAmout = 1_000_000 ether;

        deal(address(collateral), alice, amount);

        vm.startPrank(alice);

        collateral.approve(address(transmuter), amount);
        transmuter.swapExactInput(amount, agTokenAmout - 1, address(collateral), address(agToken), alice, 0);
        transmuter.swapExactOutput(amount / 2, agTokenAmout / 2, address(agToken), address(collateral), alice, 0);

        assertGe(agToken.balanceOf(alice), (agTokenAmout - 1) / 2);
        assertLe(agToken.balanceOf(alice), agTokenAmout / 2);

        assertEq(collateral.balanceOf(alice), amount / 2);

        (uint256 stablecoinsFromCollateral, uint256 stablecoinsIssued) = transmuter.getIssuedByCollateral(
            address(collateral)
        );
        assertEq(stablecoinsFromCollateral, agTokenAmout / 2);
        assertEq(stablecoinsIssued, agTokenAmout / 2);

        vm.stopPrank();
    }
}
