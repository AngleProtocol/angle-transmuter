// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import { IERC20 } from "oz/interfaces/IERC20.sol";

import { IAccessControlManager } from "interfaces/IAccessControlManager.sol";
import { IAgToken } from "interfaces/IAgToken.sol";
import { IManager } from "interfaces/IManager.sol";
import { AggregatorV3Interface } from "interfaces/external/chainlink/AggregatorV3Interface.sol";

import { ProxyAdmin, TransparentUpgradeableProxy } from "mock/MockProxyAdmin.sol";
import { MockAccessControlManager } from "mock/MockAccessControlManager.sol";
import { MockChainlinkOracle } from "mock/MockChainlinkOracle.sol";
import { MockTokenPermit } from "mock/MockTokenPermit.sol";

import { CollateralSetup, Test } from "contracts/transmuter/configs/Test.sol";
import "contracts/utils/Constants.sol";
import "contracts/utils/Errors.sol";

import { ITransmuter, Transmuter } from "./utils/Transmuter.sol";

import { console } from "forge-std/console.sol";

contract Fixture is Transmuter {
    IAccessControlManager public accessControlManager;
    ProxyAdmin public proxyAdmin;
    IAgToken public agToken;

    IERC20 public eurA;
    AggregatorV3Interface public oracleA;
    IERC20 public eurB;
    AggregatorV3Interface public oracleB;
    IERC20 public eurY;
    AggregatorV3Interface public oracleY;

    address public config;

    // Percentage tolerance on test - 0.0001%
    uint256 internal constant _MAX_PERCENTAGE_DEVIATION = 1e12;
    uint256 internal constant _MAX_SUB_COLLATERALS = 10;

    address public constant governor = 0xdC4e6DFe07EFCa50a197DF15D9200883eF4Eb1c8;
    address public constant guardian = 0x0C2553e4B9dFA9f83b1A6D3EAB96c4bAaB42d430;
    address public constant angle = 0x31429d1856aD1377A8A0079410B297e1a9e214c2;

    address public alice;
    address public bob;
    address public charlie;
    address public dylan;
    address public sweeper;

    function setUp() public virtual {
        alice = vm.addr(1);
        bob = vm.addr(2);
        charlie = vm.addr(3);
        dylan = vm.addr(4);
        sweeper = vm.addr(5);

        vm.label(governor, "Governor");
        vm.label(guardian, "Guardian");
        vm.label(angle, "ANGLE");
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
        vm.label(dylan, "Dylan");

        // Access Control
        accessControlManager = IAccessControlManager(address(new MockAccessControlManager()));
        MockAccessControlManager(address(accessControlManager)).toggleGovernor(governor);
        MockAccessControlManager(address(accessControlManager)).toggleGuardian(guardian);
        proxyAdmin = new ProxyAdmin();

        // agToken
        agToken = IAgToken(address(new MockTokenPermit("agEUR", "agEUR", 18)));

        // Collaterals
        eurA = IERC20(address(new MockTokenPermit("EUR_A", "EUR_A", 6)));
        oracleA = AggregatorV3Interface(address(new MockChainlinkOracle()));
        MockChainlinkOracle(address(oracleA)).setLatestAnswer(int256(BASE_8));

        eurB = IERC20(address(new MockTokenPermit("EUR_B", "EUR_B", 12)));
        oracleB = AggregatorV3Interface(address(new MockChainlinkOracle()));
        MockChainlinkOracle(address(oracleB)).setLatestAnswer(int256(BASE_8));

        eurY = IERC20(address(new MockTokenPermit("EUR_Y", "EUR_Y", 18)));
        oracleY = AggregatorV3Interface(address(new MockChainlinkOracle()));
        MockChainlinkOracle(address(oracleY)).setLatestAnswer(int256(BASE_8));

        // Config
        config = address(new Test());
        deployTransmuter(
            config,
            abi.encodeWithSelector(
                Test.initialize.selector,
                accessControlManager,
                agToken,
                CollateralSetup(address(eurA), address(oracleA)),
                CollateralSetup(address(eurB), address(oracleB)),
                CollateralSetup(address(eurY), address(oracleY))
            )
        );

        vm.label(address(agToken), "AgToken");
        vm.label(address(transmuter), "Transmuter");
        vm.label(address(eurA), "eurA");
        vm.label(address(eurB), "eurB");
        vm.label(address(eurY), "eurY");
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         UTILS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function deployUpgradeable(address implementation, bytes memory data) public returns (address) {
        return address(new TransparentUpgradeableProxy(implementation, address(proxyAdmin), data));
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                      ASSERTIONS                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    // Allow to have larger deviation for very small amounts
    function _assertApproxEqRelDecimalWithTolerance(
        uint256 a,
        uint256 b,
        uint256 condition,
        uint256 maxPercentDelta, // An 18 decimal fixed point number, where 1e18 == 100%
        uint256 decimals
    ) internal virtual {
        for (uint256 tol = BASE_18 / maxPercentDelta; tol > 0; tol /= 10) {
            if (condition > tol) {
                assertApproxEqRelDecimal(a, b, tol == 0 ? BASE_18 : (BASE_18 / tol), decimals);
                break;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        ACTIONS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _mintExactOutput(
        address owner,
        address tokenIn,
        uint256 amountStable,
        uint256 estimatedAmountIn
    ) internal {
        vm.startPrank(owner);
        deal(tokenIn, owner, estimatedAmountIn);
        IERC20(tokenIn).approve(address(transmuter), type(uint256).max);
        transmuter.swapExactOutput(
            amountStable,
            estimatedAmountIn,
            tokenIn,
            address(agToken),
            owner,
            block.timestamp * 2
        );
        vm.stopPrank();
    }

    function _mintExactInput(address owner, address tokenIn, uint256 amountIn, uint256 estimatedStable) internal {
        vm.startPrank(owner);
        deal(tokenIn, owner, amountIn);
        IERC20(tokenIn).approve(address(transmuter), type(uint256).max);
        transmuter.swapExactInput(amountIn, estimatedStable, tokenIn, address(agToken), owner, block.timestamp * 2);
        vm.stopPrank();
    }
}
