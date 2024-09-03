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
import "utils/src/CommonUtils.sol";
import { IERC20 } from "oz/interfaces/IERC20.sol";
import { IAgToken } from "interfaces/IAgToken.sol";
import { HarvesterSwap } from "contracts/helpers/HarvesterSwap.sol";
import { MockRouter } from "../mock/MockRouter.sol";

import { RebalancerFlashloanSwap, IERC3156FlashLender } from "contracts/helpers/RebalancerFlashloanSwap.sol";

interface IFlashAngle {
    function addStablecoinSupport(address _treasury) external;

    function setFlashLoanParameters(address stablecoin, uint64 _flashLoanFee, uint256 _maxBorrowable) external;
}

contract HarvesterSwapUSDATest is Test, CommonUtils {
    using stdJson for string;

    ITransmuter transmuter;
    IERC20 USDA;
    IAgToken treasuryUSDA;
    IFlashAngle FLASHLOAN;
    address governor;
    RebalancerFlashloanSwap public rebalancer;
    MockRouter public router;
    HarvesterSwap harvester;
    uint64 public targetExposure;
    uint64 public maxExposureYieldAsset;
    uint64 public minExposureYieldAsset;

    address constant WHALE = 0x54D7aE423Edb07282645e740C046B9373970a168;

    function setUp() public {
        ethereumFork = vm.createSelectFork(vm.envString("ETH_NODE_URI_MAINNET"), 20590478);

        transmuter = ITransmuter(_chainToContract(CHAIN_ETHEREUM, ContractType.TransmuterAgUSD));
        USDA = IERC20(_chainToContract(CHAIN_ETHEREUM, ContractType.AgUSD));
        FLASHLOAN = IFlashAngle(_chainToContract(CHAIN_ETHEREUM, ContractType.FlashLoan));
        treasuryUSDA = IAgToken(_chainToContract(CHAIN_ETHEREUM, ContractType.TreasuryAgUSD));
        governor = _chainToContract(CHAIN_ETHEREUM, ContractType.GovernorMultisig);

        // Setup rebalancer
        router = new MockRouter();
        rebalancer = new RebalancerFlashloanSwap(
            // Mock access control manager for USDA
            IAccessControlManager(0x3fc5a1bd4d0A435c55374208A6A81535A1923039),
            transmuter,
            IERC3156FlashLender(address(FLASHLOAN)),
            address(router),
            address(router),
            50
        );
        targetExposure = uint64((15 * 1e9) / 100);
        maxExposureYieldAsset = uint64((80 * 1e9) / 100);
        minExposureYieldAsset = uint64((5 * 1e9) / 100);

        harvester = new HarvesterSwap(
            address(rebalancer),
            USDC,
            USDM,
            targetExposure,
            1,
            maxExposureYieldAsset,
            minExposureYieldAsset,
            1e8
        );

        vm.startPrank(governor);
        deal(address(USDA), address(rebalancer), BASE_18 * 1000);
        rebalancer.setOrder(USDM, address(USDC), BASE_18 * 500, 0);
        rebalancer.setOrder(address(USDC), USDM, BASE_18 * 500, 0);
        transmuter.toggleWhitelist(Storage.WhitelistType.BACKED, NEW_DEPLOYER);
        transmuter.toggleTrusted(governor, Storage.TrustedType.Seller);
        transmuter.toggleTrusted(address(harvester), Storage.TrustedType.Seller);

        vm.stopPrank();

        // Initialize Transmuter reserves
        deal(USDC, NEW_DEPLOYER, 100000 * BASE_18);
        vm.startPrank(NEW_DEPLOYER);
        IERC20(USDC).approve(address(transmuter), type(uint256).max);
        transmuter.swapExactOutput(
            1200 * 10 ** 21,
            type(uint256).max,
            USDC,
            address(USDA),
            NEW_DEPLOYER,
            block.timestamp
        );
        vm.stopPrank();
        vm.startPrank(WHALE);
        IERC20(USDM).approve(address(transmuter), type(uint256).max);
        transmuter.swapExactOutput(1200 * 10 ** 21, type(uint256).max, USDM, address(USDA), WHALE, block.timestamp);
        vm.stopPrank();
    }

    function testUnit_Harvest_IncreaseUSDMExposure() external {
        (uint256 fromUSDC, uint256 total) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromUSDM, ) = transmuter.getIssuedByCollateral(USDM);

        uint256 amount = 877221843438992898201107;
        uint256 quoteAmount = transmuter.quoteIn(amount, address(USDA), USDC);
        vm.prank(WHALE);
        IERC20(USDM).transfer(address(router), quoteAmount * 1e12);

        bytes memory data = abi.encodeWithSelector(
            MockRouter.swap.selector,
            quoteAmount,
            USDC,
            quoteAmount * 1e12,
            USDM
        );
        harvester.harvest(USDC, 1e9, data);
        (uint256 fromUSDC2, uint256 total2) = transmuter.getIssuedByCollateral(address(USDC));
        (uint256 fromUSDM2, ) = transmuter.getIssuedByCollateral(USDM);
        assertGt(fromUSDC, fromUSDC2);
        assertGt(fromUSDM2, fromUSDM);
        assertGt(total, total2);
        assertApproxEqRel((fromUSDC2 * 1e9) / total2, targetExposure, 100 * BPS);
        assertApproxEqRel(fromUSDC2 * 1e9, targetExposure * total, 100 * BPS);
    }
}
