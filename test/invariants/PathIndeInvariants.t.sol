// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import { IERC20 } from "oz/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "oz/token/ERC20/extensions/IERC20Metadata.sol";
import "oz/utils/Strings.sol";
import { AggregatorV3Interface } from "interfaces/external/chainlink/AggregatorV3Interface.sol";
import { MockAccessControlManager } from "mock/MockAccessControlManager.sol";

import "contracts/utils/Constants.sol";
import { CollateralSetup, Fixture, ITransmuter, Test } from "../Fixture.sol";
import { TraderWithSplit } from "./actors/TraderWithSplit.t.sol";
import { ArbitragerWithSplit } from "./actors/ArbitragerWithSplit.t.sol";
import { Governance } from "./actors/Governance.t.sol";

//solhint-disable
import { console } from "forge-std/console.sol";

contract PathIndeInvariants is Fixture {
    uint256 internal constant _NUM_TRADER = 2;
    uint256 internal constant _NUM_ARB = 2;

    ITransmuter transmuterSplit;

    TraderWithSplit internal _traderHandler;
    ArbitragerWithSplit internal _arbitragerHandler;
    Governance internal _governanceHandler;

    address[] internal _collaterals;
    AggregatorV3Interface[] internal _oracles;
    uint8[] internal _decimals;

    function setUp() public virtual override {
        super.setUp();

        // Deploy another transmuter to check the independant path property
        config = address(new Test());
        transmuterSplit = deployReplicaTransmuter(
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

        {
            // set redemption fees
            uint64[] memory xFeeRedemption = new uint64[](4);
            xFeeRedemption[0] = uint64(0);
            xFeeRedemption[1] = uint64(1e9 / 2);
            xFeeRedemption[2] = uint64((1e9 * 3) / 4);
            xFeeRedemption[3] = uint64(1e9);
            int64[] memory yFeeRedemption = new int64[](4);
            yFeeRedemption[0] = int64(int256(1e9));
            yFeeRedemption[1] = int64(int256(1e9));
            yFeeRedemption[2] = int64(int256((1e9 * 9) / 10));
            yFeeRedemption[3] = int64(int256(1e9));
            vm.startPrank(governor);
            transmuter.setRedemptionCurveParams(xFeeRedemption, yFeeRedemption);
            transmuterSplit.setRedemptionCurveParams(xFeeRedemption, yFeeRedemption);
            vm.stopPrank();
        }

        _collaterals.push(address(eurA));
        _collaterals.push(address(eurB));
        _collaterals.push(address(eurY));
        _decimals.push(IERC20Metadata(address(eurA)).decimals());
        _decimals.push(IERC20Metadata(address(eurB)).decimals());
        _decimals.push(IERC20Metadata(address(eurY)).decimals());
        _oracles.push(oracleA);
        _oracles.push(oracleB);
        _oracles.push(oracleY);

        _traderHandler = new TraderWithSplit(transmuter, transmuterSplit, _collaterals, _oracles, _NUM_TRADER);
        _arbitragerHandler = new ArbitragerWithSplit(transmuter, transmuterSplit, _collaterals, _oracles, _NUM_ARB);
        _governanceHandler = new Governance(transmuter, transmuterSplit, _collaterals, _oracles);
        MockAccessControlManager(address(accessControlManager)).toggleGovernor(_governanceHandler.actors(0));

        // Label newly created addresses
        vm.label(address(transmuterSplit), "TransmuterSplit");
        for (uint256 i; i < _NUM_ARB; i++)
            vm.label(_arbitragerHandler.actors(i), string.concat("Arbi ", Strings.toString(i)));
        for (uint256 i; i < _NUM_TRADER; i++)
            vm.label(_traderHandler.actors(i), string.concat("Trader ", Strings.toString(i)));

        targetContract(address(_traderHandler));
        targetContract(address(_arbitragerHandler));
        targetContract(address(_governanceHandler));

        {
            bytes4[] memory selectors = new bytes4[](1);
            selectors[0] = TraderWithSplit.swap.selector;
            targetSelector(FuzzSelector({ addr: address(_traderHandler), selectors: selectors }));
        }

        {
            bytes4[] memory selectors = new bytes4[](2);
            selectors[0] = ArbitragerWithSplit.swap.selector;
            selectors[1] = ArbitragerWithSplit.redeem.selector;
            targetSelector(FuzzSelector({ addr: address(_arbitragerHandler), selectors: selectors }));
        }

        {
            bytes4[] memory selectors = new bytes4[](4);
            selectors[0] = Governance.updateOracle.selector;
            selectors[1] = Governance.updateRedemptionFees.selector;
            selectors[2] = Governance.updateBurnFees.selector;
            selectors[3] = Governance.updateMintFees.selector;
            targetSelector(FuzzSelector({ addr: address(_governanceHandler), selectors: selectors }));
        }
    }

    function systemState() public view {
        console.log("");
        console.log("SYSTEM STATE");
        console.log("");
        console.log("Calls summary:");
        console.log("-------------------");
        console.log("Trader:swap", _traderHandler.calls("swap"));
        console.log("Arbitrager:swap", _arbitragerHandler.calls("swap"));
        console.log("Arbitrager:redeem", _arbitragerHandler.calls("redeem"));
        console.log("oracle", _governanceHandler.calls("oracle"));
        console.log("Mint fees", _governanceHandler.calls("feeMint"));
        console.log("Burn fees", _governanceHandler.calls("feeBurn"));
        console.log("Redeem fees", _governanceHandler.calls("feeRedeem"));
        console.log("Increase time", _governanceHandler.calls("timestamp"));
        console.log("-------------------");
        console.log("");

        (uint256 issuedA, uint256 issued) = transmuter.getIssuedByCollateral(address(eurA));
        (uint256 issuedB, ) = transmuter.getIssuedByCollateral(address(eurB));
        (uint256 issuedY, ) = transmuter.getIssuedByCollateral(address(eurY));
        console.log("Issued A: ", issuedA);
        console.log("Issued B: ", issuedB);
        console.log("Issued Y: ", issuedY);
        console.log("Issued Total: ", issued);
    }

    function invariant_Supply() public {
        uint256 stablecoinIssued = transmuter.getTotalIssued();
        uint256 stablecoinIssuedSplit = transmuterSplit.getTotalIssued();

        uint256 balance = agToken.balanceOf(sweeper);
        uint256 traderActors = _traderHandler.nbrActor();
        uint256 arbitrageActors = _arbitragerHandler.nbrActor();
        for (uint256 i = 0; i < traderActors; i++) balance += agToken.balanceOf(_traderHandler.actors(i));
        for (uint256 i = 0; i < arbitrageActors; i++) balance += agToken.balanceOf(_arbitragerHandler.actors(i));

        assertApproxEqAbs(stablecoinIssued + stablecoinIssuedSplit, balance, BASE_12);
    }

    function invariant_CollateralRatio() public {
        uint256 storedCollatRatio = _governanceHandler.collateralRatio();
        (uint64 collateralRatio, ) = transmuter.getCollateralRatio();
        if (storedCollatRatio <= BASE_9)
            assertGe(uint256(collateralRatio), storedCollatRatio);
            // if we have a collateral ratio above 100% and without fees, then a mint will decrease the collateral ratio
            // as it will become (a+c)/(b+c) with a>b
            // With fees it is less predictable, but in all cases the collateral ratio should not drop below over collateralise = 100%
        else assertGe(uint256(collateralRatio), BASE_9);

        _governanceHandler.updateCollateralRatio(collateralRatio);
    }

    function invariant_RedeemCollateralRatio() public {
        uint256 storedCollatRatio = _governanceHandler.collateralRatio();
        (uint64 collateralRatio, ) = transmuter.getCollateralRatio();
        if (storedCollatRatio <= BASE_9) assertGe(collateralRatio, storedCollatRatio);
        else assertGe(collateralRatio, BASE_9);

        _governanceHandler.updateCollateralRatio(collateralRatio);
    }

    function invariant_PathIndependenceTotalSupply() public {
        uint256 stablecoinIssued = transmuter.getTotalIssued();
        uint256 stablecoinIssuedSplit = transmuterSplit.getTotalIssued();
        assertApproxEqRelDecimal(stablecoinIssued, stablecoinIssuedSplit, _MAX_PERCENTAGE_DEVIATION * 100, 18);
    }

    function invariant_PathIndependenceSubSupply() public {
        for (uint256 i; i < _collaterals.length; i++) {
            (uint256 issuedPerCollat, ) = transmuter.getIssuedByCollateral(_collaterals[i]);
            (uint256 issuedPerCollatSplit, ) = transmuterSplit.getIssuedByCollateral(_collaterals[i]);
            assertApproxEqRelDecimal(issuedPerCollat, issuedPerCollatSplit, _MAX_PERCENTAGE_DEVIATION * 100, 18);
        }
    }

    function invariant_PathIndependenceBalanceCollaterals() public {
        for (uint256 i; i < _collaterals.length; i++) {
            uint256 balance = IERC20(_collaterals[i]).balanceOf(address(transmuter));
            uint256 balanceSplit = IERC20(_collaterals[i]).balanceOf(address(transmuterSplit));
            assertApproxEqRelDecimal(balance, balanceSplit, _MAX_PERCENTAGE_DEVIATION * 100, 18);
        }
    }

    function invariant_PathIndependenceCollateralRatio() public {
        (uint256 collateralRatio, ) = transmuter.getCollateralRatio();
        (uint256 collateralRatioSplit, ) = transmuterSplit.getCollateralRatio();
        assertApproxEqRelDecimal(collateralRatio, collateralRatioSplit, _MAX_PERCENTAGE_DEVIATION * 100, 18);
    }

    function invariantSystemState() public view {
        systemState();
    }
}
