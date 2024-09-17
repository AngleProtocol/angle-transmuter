// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { stdJson } from "forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";

import "../../scripts/Constants.s.sol";

import "contracts/utils/Errors.sol" as Errors;
import "contracts/transmuter/Storage.sol" as Storage;
import "contracts/transmuter/libraries/LibHelpers.sol";
import { CollateralSetupProd } from "contracts/transmuter/configs/ProductionTypes.sol";
import { ITransmuter } from "interfaces/ITransmuter.sol";
import "utils/src/Constants.sol";
import { IERC20 } from "oz/interfaces/IERC20.sol";
import { IAgToken } from "interfaces/IAgToken.sol";

import { RebalancerFlashloanVault, IERC4626, IERC3156FlashLender } from "contracts/helpers/RebalancerFlashloanVault.sol";

interface IFlashAngle {
    function addStablecoinSupport(address _treasury) external;

    function setFlashLoanParameters(address stablecoin, uint64 _flashLoanFee, uint256 _maxBorrowable) external;
}

contract RebalancerUSDATest is Test {
    using stdJson for string;

    ITransmuter transmuter;
    IERC20 agToken;
    IERC20 constant collateral = IERC20(0x60a3E35Cc302bFA44Cb288Bc5a4F316Fdb1adb42);
    uint256 fork;

    function setUp() public {
        fork = vm.createSelectFork(vm.envString("ETH_NODE_URI_FORK"));

        // TODO update
        uint256 chain = CHAIN_BASE;
        agToken = _chainToContract(chain, ContractType.AgEUR);
        transmuter = ITransmuter(0);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        GETTERS
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testUnit_CheckState() external {
        assertEq(address(transmuter.agToken()), agToken);
        address[] memory collaterals = transmuter.getCollateralList();
        assertEq(collaterals.length, 1);
        assertEq(collaterals[0], collateral);
        assertEq(transmuter.getStablecoinCap(collateral), 2_000_000 ether);
        assertEq(transmuter.getCollateralDecimals(collateral), 8);
    }

    function testUnit_CheckOracle() external {
        (uint256 mint, uint256 burn, uint256 ratio, uint256 minRatio, uint256 redemption) = transmuter.getOracleValues(
            collateral
        );
        assertEq(mint, BASE_18);
        assertEq(burn, BASE_18);
        assertEq(ratio, BASE_18);
        assertEq(minRatio, BASE_18);
        assertEq(redemption, BASE_18);
    }

    function testUnit_SwapExactInput_Mint() external {
        uint256 amount = 1_000_000 ether;

        deal(collateral, alice, amount);

        vm.startPrank(alice);

        collateral.approve(address(transmuter), amount);
        transmuter.swapExactInput(amount, amount - 1, collateral, agToken, alice, 0);

        assertGe(agToken.balanceOf(alice), amount - 1);
        assertLe(agToken.balanceOf(alice), amount);

        (uint256 stablecoinsFromCollateral, uint256 stablecoinsIssued) = transmuter.getIssuedByCollateral(collateral);
        assertEq(stablecoinsFromCollateral, amount);
        assertEq(stablecoinsIssued, amount);

        vm.stopPrank();
    }

    function testUnit_SwapExactOutput_Mint() external {
        uint256 amount = 1_000_000 ether;

        deal(collateral, alice, amount);

        vm.startPrank(alice);

        collateral.approve(address(transmuter), amount);
        transmuter.swapExactOutput(amount, amount + 1, collateral, agToken, alice, 0);

        assertGe(agToken.balanceOf(alice), amount - 1);
        assertLe(agToken.balanceOf(alice), amount);

        (uint256 stablecoinsFromCollateral, uint256 stablecoinsIssued) = transmuter.getIssuedByCollateral(collateral);
        assertEq(stablecoinsFromCollateral, amount);
        assertEq(stablecoinsIssued, amount);

        vm.stopPrank();
    }

    function testUnit_SwapExactInput_Burn() external {
        uint256 amount = 1_000_000 ether;

        deal(collateral, alice, amount);

        vm.startPrank(alice);

        collateral.approve(address(transmuter), amount);
        transmuter.swapExactInput(amount, amount - 1, collateral, agToken, alice, 0);
        transmuter.swapExactInput(amount / 2, (amount - 1) / 2, agToken, collateral, alice, 0);

        assertGe(agToken.balanceOf(alice), (amount - 1) / 2);
        assertLe(agToken.balanceOf(alice), amount / 2);

        assertGe(collateral.balanceOf(alice), (amount - 1) / 2);
        assertLe(collateral.balanceOf(alice), amount / 2);

        (uint256 stablecoinsFromCollateral, uint256 stablecoinsIssued) = transmuter.getIssuedByCollateral(collateral);
        assertEq(stablecoinsFromCollateral, amount / 2);
        assertEq(stablecoinsIssued, amount / 2);

        vm.stopPrank();
    }

    function testUnit_SwapExactOutput_Burn() external {
        uint256 amount = 1_000_000 ether;

        deal(collateral, alice, amount);

        vm.startPrank(alice);

        collateral.approve(address(transmuter), amount);
        transmuter.swapExactInput(amount, amount - 1, collateral, agToken, alice, 0);
        transmuter.swapExactOutput(amount / 2, (amount - 1) / 2, agToken, collateral, alice, 0);

        assertGe(agToken.balanceOf(alice), (amount - 1) / 2);
        assertLe(agToken.balanceOf(alice), amount / 2);

        assertGe(collateral.balanceOf(alice), (amount - 1) / 2);
        assertLe(collateral.balanceOf(alice), amount / 2);

        (uint256 stablecoinsFromCollateral, uint256 stablecoinsIssued) = transmuter.getIssuedByCollateral(collateral);
        assertEq(stablecoinsFromCollateral, amount / 2);
        assertEq(stablecoinsIssued, amount / 2);

        vm.stopPrank();
    }
}
