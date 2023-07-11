// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import { console } from "forge-std/console.sol";
import { IERC20 } from "oz/interfaces/IERC20.sol";
import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";
import { IERC1820Registry } from "oz/utils/introspection/IERC1820Registry.sol";
import { IERC20Metadata } from "../mock/MockTokenPermit.sol";

import { IAccessControlManager } from "interfaces/IAccessControlManager.sol";
import { IAgToken } from "interfaces/IAgToken.sol";
import { AggregatorV3Interface } from "interfaces/external/chainlink/AggregatorV3Interface.sol";

import { MockAccessControlManager } from "mock/MockAccessControlManager.sol";
import { MockChainlinkOracle } from "mock/MockChainlinkOracle.sol";
import { MockERC777 } from "mock/MockERC777.sol";
import { MockTokenPermit } from "mock/MockTokenPermit.sol";
import { ReentrantRedeemGetCollateralRatio, ReentrantRedeemSwap } from "mock/MockReentrant.sol";

import { CollateralSetup, Test } from "contracts/transmuter/configs/Test.sol";
import { LibGetters } from "contracts/transmuter/libraries/LibGetters.sol";
import "contracts/transmuter/Storage.sol";
import "contracts/utils/Constants.sol";
import "contracts/utils/Errors.sol" as Errors;

import { ITransmuter, Transmuter } from "../utils/Transmuter.sol";

contract TransmuterReentrantTest is Transmuter {
    using SafeERC20 for IERC20;

    IAccessControlManager public accessControlManager;
    IAgToken public agToken;

    IERC20 public eurA;
    AggregatorV3Interface public oracleA;
    IERC20 public eurB;
    AggregatorV3Interface public oracleB;
    IERC20 public eurY;
    AggregatorV3Interface public oracleY;

    address public config;

    uint256 internal _maxAmountWithoutDecimals = 10 ** 15;
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

    address[] internal _collaterals;
    AggregatorV3Interface[] internal _oracles;
    uint256[] internal _maxTokenAmount;
    ReentrantRedeemSwap contractReentrantRedeemSwap;
    ReentrantRedeemGetCollateralRatio contractReentrantRedeemGetCollateralRatio;

    function setUp() public {
        alice = vm.addr(1);
        bob = vm.addr(2);
        charlie = vm.addr(3);
        dylan = vm.addr(4);

        vm.label(governor, "Governor");
        vm.label(guardian, "Guardian");
        vm.label(angle, "ANGLE");
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
        vm.label(dylan, "Dylan");
        vm.label(sweeper, "Sweeper");

        // Register IERC1820Registry
        IERC1820Registry registry = IERC1820Registry(address(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24));
        // mock ERC1820Registry contract in foundry
        vm.etch(
            address(registry),
            bytes(
                hex"608060405234801561001057600080fd5b50600436106100a5576000357c010000000000000000000000000000000000000000000000000000000090048063a41e7d5111610078578063a41e7d51146101d4578063aabbb8ca1461020a578063b705676514610236578063f712f3e814610280576100a5565b806329965a1d146100aa5780633d584063146100e25780635df8122f1461012457806365ba36c114610152575b600080fd5b6100e0600480360360608110156100c057600080fd5b50600160a060020a038135811691602081013591604090910135166102b6565b005b610108600480360360208110156100f857600080fd5b5035600160a060020a0316610570565b60408051600160a060020a039092168252519081900360200190f35b6100e06004803603604081101561013a57600080fd5b50600160a060020a03813581169160200135166105bc565b6101c26004803603602081101561016857600080fd5b81019060208101813564010000000081111561018357600080fd5b82018360208201111561019557600080fd5b803590602001918460018302840111640100000000831117156101b757600080fd5b5090925090506106b3565b60408051918252519081900360200190f35b6100e0600480360360408110156101ea57600080fd5b508035600160a060020a03169060200135600160e060020a0319166106ee565b6101086004803603604081101561022057600080fd5b50600160a060020a038135169060200135610778565b61026c6004803603604081101561024c57600080fd5b508035600160a060020a03169060200135600160e060020a0319166107ef565b604080519115158252519081900360200190f35b61026c6004803603604081101561029657600080fd5b508035600160a060020a03169060200135600160e060020a0319166108aa565b6000600160a060020a038416156102cd57836102cf565b335b9050336102db82610570565b600160a060020a031614610339576040805160e560020a62461bcd02815260206004820152600f60248201527f4e6f7420746865206d616e616765720000000000000000000000000000000000604482015290519081900360640190fd5b6103428361092a565b15610397576040805160e560020a62461bcd02815260206004820152601a60248201527f4d757374206e6f7420626520616e204552433136352068617368000000000000604482015290519081900360640190fd5b600160a060020a038216158015906103b85750600160a060020a0382163314155b156104ff5760405160200180807f455243313832305f4143434550545f4d4147494300000000000000000000000081525060140190506040516020818303038152906040528051906020012082600160a060020a031663249cb3fa85846040518363ffffffff167c01000000000000000000000000000000000000000000000000000000000281526004018083815260200182600160a060020a0316600160a060020a031681526020019250505060206040518083038186803b15801561047e57600080fd5b505afa158015610492573d6000803e3d6000fd5b505050506040513d60208110156104a857600080fd5b5051146104ff576040805160e560020a62461bcd02815260206004820181905260248201527f446f6573206e6f7420696d706c656d656e742074686520696e74657266616365604482015290519081900360640190fd5b600160a060020a03818116600081815260208181526040808320888452909152808220805473ffffffffffffffffffffffffffffffffffffffff19169487169485179055518692917f93baa6efbd2244243bfee6ce4cfdd1d04fc4c0e9a786abd3a41313bd352db15391a450505050565b600160a060020a03818116600090815260016020526040812054909116151561059a5750806105b7565b50600160a060020a03808216600090815260016020526040902054165b919050565b336105c683610570565b600160a060020a031614610624576040805160e560020a62461bcd02815260206004820152600f60248201527f4e6f7420746865206d616e616765720000000000000000000000000000000000604482015290519081900360640190fd5b81600160a060020a031681600160a060020a0316146106435780610646565b60005b600160a060020a03838116600081815260016020526040808220805473ffffffffffffffffffffffffffffffffffffffff19169585169590951790945592519184169290917f605c2dbf762e5f7d60a546d42e7205dcb1b011ebc62a61736a57c9089d3a43509190a35050565b600082826040516020018083838082843780830192505050925050506040516020818303038152906040528051906020012090505b92915050565b6106f882826107ef565b610703576000610705565b815b600160a060020a03928316600081815260208181526040808320600160e060020a031996909616808452958252808320805473ffffffffffffffffffffffffffffffffffffffff19169590971694909417909555908152600284528181209281529190925220805460ff19166001179055565b600080600160a060020a038416156107905783610792565b335b905061079d8361092a565b156107c357826107ad82826108aa565b6107b85760006107ba565b815b925050506106e8565b600160a060020a0390811660009081526020818152604080832086845290915290205416905092915050565b6000808061081d857f01ffc9a70000000000000000000000000000000000000000000000000000000061094c565b909250905081158061082d575080155b1561083d576000925050506106e8565b61084f85600160e060020a031961094c565b909250905081158061086057508015155b15610870576000925050506106e8565b61087a858561094c565b909250905060018214801561088f5750806001145b1561089f576001925050506106e8565b506000949350505050565b600160a060020a0382166000908152600260209081526040808320600160e060020a03198516845290915281205460ff1615156108f2576108eb83836107ef565b90506106e8565b50600160a060020a03808316600081815260208181526040808320600160e060020a0319871684529091529020549091161492915050565b7bffffffffffffffffffffffffffffffffffffffffffffffffffffffff161590565b6040517f01ffc9a7000000000000000000000000000000000000000000000000000000008082526004820183905260009182919060208160248189617530fa90519096909550935050505056fea165627a7a72305820377f4a2d4301ede9949f163f319021a6e9c687c292a5e2b2c4734c126b524e6c0029"
            )
        );

        // Access Control
        accessControlManager = IAccessControlManager(address(new MockAccessControlManager()));
        MockAccessControlManager(address(accessControlManager)).toggleGovernor(governor);
        MockAccessControlManager(address(accessControlManager)).toggleGuardian(guardian);

        // agToken
        agToken = IAgToken(address(new MockTokenPermit("agEUR", "agEUR", 18)));

        // Collaterals
        eurA = IERC20(address(new MockERC777("EUR_A", "EUR_A", 18)));
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

        // set Fees to 0 on all collaterals
        uint64[] memory xFeeMint = new uint64[](1);
        xFeeMint[0] = uint64(0);
        uint64[] memory xFeeBurn = new uint64[](1);
        xFeeBurn[0] = uint64(BASE_9);
        int64[] memory yFee = new int64[](1);
        yFee[0] = 0;
        int64[] memory yFeeRedemption = new int64[](1);
        yFeeRedemption[0] = int64(int256(BASE_9));
        vm.startPrank(governor);
        transmuter.setFees(address(eurA), xFeeMint, yFee, true);
        transmuter.setFees(address(eurA), xFeeBurn, yFee, false);
        transmuter.setFees(address(eurB), xFeeMint, yFee, true);
        transmuter.setFees(address(eurB), xFeeBurn, yFee, false);
        transmuter.setFees(address(eurY), xFeeMint, yFee, true);
        transmuter.setFees(address(eurY), xFeeBurn, yFee, false);
        transmuter.setRedemptionCurveParams(xFeeMint, yFeeRedemption);
        vm.stopPrank();

        _collaterals.push(address(eurA));
        _collaterals.push(address(eurB));
        _collaterals.push(address(eurY));
        _oracles.push(oracleA);
        _oracles.push(oracleB);
        _oracles.push(oracleY);

        _maxTokenAmount.push(_maxAmountWithoutDecimals * 10 ** IERC20Metadata(_collaterals[0]).decimals());
        _maxTokenAmount.push(_maxAmountWithoutDecimals * 10 ** IERC20Metadata(_collaterals[1]).decimals());
        _maxTokenAmount.push(_maxAmountWithoutDecimals * 10 ** IERC20Metadata(_collaterals[2]).decimals());

        // deploy all the reentrant contracts
        contractReentrantRedeemGetCollateralRatio = new ReentrantRedeemGetCollateralRatio(
            ITransmuter(address(transmuter)),
            IERC1820Registry(address(registry))
        );
        contractReentrantRedeemGetCollateralRatio.setInterfaceImplementer();

        contractReentrantRedeemSwap = new ReentrantRedeemSwap(
            ITransmuter(address(transmuter)),
            IERC1820Registry(address(registry)),
            IERC20(address(agToken)),
            IERC20(address(eurB))
        );
        contractReentrantRedeemSwap.setInterfaceImplementer();
    }

    function testFuzz_ReentrantRedeemCollateralRatio(uint256[3] memory initialAmounts) public {
        // let's first load the reserves of the protocol
        (uint256 mintedStables, ) = _loadReserves(initialAmounts, 0);
        if (mintedStables == 0) return;

        vm.startPrank(alice);
        uint256 amountBurnt = agToken.balanceOf(alice);
        (, uint256[] memory quoteAmounts) = transmuter.quoteRedemptionCurve(amountBurnt);
        if (quoteAmounts[0] == 0) return;

        agToken.transfer(address(contractReentrantRedeemGetCollateralRatio), amountBurnt);
        vm.expectRevert(Errors.ReentrantCall.selector);
        contractReentrantRedeemGetCollateralRatio.testERC777Reentrancy(amountBurnt);
        vm.stopPrank();
    }

    function testFuzz_ReentrantRedeemSwap(uint256[3] memory initialAmounts) public {
        // let's first load the reserves of the protocol
        (uint256 mintedStables, ) = _loadReserves(initialAmounts, 0);
        if (mintedStables == 0) return;

        vm.startPrank(alice);
        uint256 amountBurnt = agToken.balanceOf(alice);
        (, uint256[] memory quoteAmounts) = transmuter.quoteRedemptionCurve(amountBurnt);
        if (quoteAmounts[0] == 0) return;

        agToken.transfer(address(contractReentrantRedeemSwap), amountBurnt);
        vm.expectRevert(Errors.ReentrantCall.selector);
        contractReentrantRedeemSwap.testERC777Reentrancy(amountBurnt);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         UTILS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _loadReserves(
        uint256[3] memory initialAmounts,
        uint256 transferProportion
    ) internal returns (uint256 mintedStables, uint256[] memory collateralMintedStables) {
        collateralMintedStables = new uint256[](_collaterals.length);

        vm.startPrank(alice);
        for (uint256 i; i < _collaterals.length; ++i) {
            initialAmounts[i] = bound(initialAmounts[i], 0, _maxTokenAmount[i]);
            deal(_collaterals[i], alice, initialAmounts[i]);
            IERC20(_collaterals[i]).approve(address(transmuter), initialAmounts[i]);

            collateralMintedStables[i] = transmuter.swapExactInput(
                initialAmounts[i],
                0,
                _collaterals[i],
                address(agToken),
                alice,
                block.timestamp * 2
            );
            mintedStables += collateralMintedStables[i];
        }

        // Send a proportion of these to another account user just to complexify the case
        transferProportion = bound(transferProportion, 0, BASE_9);
        agToken.transfer(bob, (mintedStables * transferProportion) / BASE_9);
        vm.stopPrank();
    }
}
