// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";
import "oz/utils/math/Math.sol";
import { IERC20Metadata } from "../mock/MockTokenPermit.sol";
import "../Fixture.sol";
import "../utils/FunctionUtils.sol";
import { ITransmuter } from "contracts/interfaces/ITransmuter.sol";
import "contracts/utils/Errors.sol" as Errors;
import "contracts/savings/SavingsVest.sol";
import { UD60x18, ud, pow, powu, unwrap } from "prb/math/UD60x18.sol";

import { stdError } from "forge-std/Test.sol";

contract SavingsVestTest is Fixture, FunctionUtils {
    using Math for uint256;
    using SafeERC20 for IERC20;

    uint256 internal constant _initDeposit = 1e12;
    uint256 internal constant _firstDeposit = BASE_8 * 1e4;
    uint256 internal constant _minAmount = 10 ** 10;
    uint256 internal constant _maxAmountWithoutDecimals = 10 ** 15;
    uint256 internal constant _maxAmount = 10 ** (18 + 15);
    uint256 internal constant _minOracleValue = 10 ** 3; // 10**(-5)
    uint256 internal constant _maxElapseTime = 20 days;
    uint256 internal constant _nbrActor = 10;
    address internal constant _surplusManager = dylan;
    SavingsVest internal _saving;
    SavingsVest internal _savingImplementation;
    string internal _name;
    string internal _symbol;
    address[] public actors;

    address[] internal _collaterals;
    AggregatorV3Interface[] internal _oracles;
    uint256[] internal _maxTokenAmount;

    function setUp() public override {
        super.setUp();

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

        _savingImplementation = new SavingsVest();
        bytes memory data;
        _saving = SavingsVest(deployUpgradeable(address(_savingImplementation), data));
        _name = "savingAgEUR";
        _symbol = "SAGEUR";

        for (uint256 i; i < _nbrActor; ++i) {
            address actor = address(uint160(uint256(keccak256(abi.encodePacked("actor", i)))));
            actors.push(actor);
        }

        vm.startPrank(governor);
        agToken.addMinter(address(_saving));
        deal(address(agToken), governor, _initDeposit);
        agToken.approve(address(_saving), _initDeposit);
        _saving.initialize(
            accessControlManager,
            IERC20MetadataUpgradeable(address(agToken)),
            ITransmuter(address(transmuter)),
            _name,
            _symbol,
            BASE_18 / _initDeposit
        );

        _saving.setSurplusManager(_surplusManager);
        transmuter.toggleTrusted(address(_saving), 0);
        vm.stopPrank();

        _deposit(_firstDeposit, alice, alice, 0);
    }

    function testInitialisation() public {
        assertEq(address(_saving.accessControlManager()), address(accessControlManager));
        assertEq(address(_saving.transmuter()), address(transmuter));
        assertEq(_saving.asset(), address(agToken));
        assertEq(_saving.name(), _name);
        assertEq(_saving.symbol(), _symbol);
        assertEq(_saving.totalAssets(), _firstDeposit + _initDeposit);
        assertEq(_saving.totalSupply(), _firstDeposit + _initDeposit);
        assertEq(agToken.balanceOf(address(_saving)), _firstDeposit + _initDeposit);
        assertEq(_saving.balanceOf(address(governor)), 0);
        assertEq(_saving.balanceOf(address(_saving)), _initDeposit);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        SETTERS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testRevertSetters() public {
        bytes32 what = "PA";

        vm.startPrank(governor);
        vm.expectRevert(Errors.InvalidParam.selector);
        _saving.setParams(what, 0);

        vm.expectRevert(Errors.InvalidParam.selector);
        _saving.setParams(what, uint64(BASE_9 + 1));
        vm.stopPrank();

        what = "P";
        vm.startPrank(alice);
        vm.expectRevert(Errors.NotGovernorOrGuardian.selector);
        _saving.setParams(what, 1);
        vm.stopPrank();
    }

    function testSetPause(uint64 paused) public {
        // Cautious if you try to set pause to something greater than
        // type(uint8).max, the cast may get you to a value not expected
        // if paused % 2**8 then it will not pause the protocol
        paused = uint64(bound(paused, 1, type(uint8).max));
        bytes32 what = "P";

        vm.prank(governor);
        _saving.setParams(what, paused);

        vm.startPrank(alice);
        vm.expectRevert(Errors.Paused.selector);
        _saving.deposit(BASE_18, alice);

        vm.expectRevert(Errors.Paused.selector);
        _saving.mint(BASE_18, alice);

        vm.expectRevert(Errors.Paused.selector);
        _saving.redeem(BASE_18, alice, alice);

        vm.expectRevert(Errors.Paused.selector);
        _saving.withdraw(BASE_18, alice, alice);

        vm.stopPrank();
    }

    function testSetVestingPeriod(uint64 vestingPeriod) public {
        // 365 days < 2**32
        vestingPeriod = uint64(bound(vestingPeriod, 1, 365 days));

        bytes32 what = "VP";
        vm.prank(governor);
        _saving.setParams(what, vestingPeriod);
        assertEq(_saving.vestingPeriod(), vestingPeriod);
    }

    function testSetProtocolSafetyFee(uint64 protocolSafetyFee) public {
        protocolSafetyFee = uint64(bound(protocolSafetyFee, 0, BASE_9));

        bytes32 what = "PF";
        vm.prank(governor);
        _saving.setParams(what, protocolSafetyFee);
        assertEq(_saving.protocolSafetyFee(), protocolSafetyFee);
    }

    function testSetUpdateDelay(uint64 updateDelay) public {
        // 365 days < 2**32
        updateDelay = uint64(bound(updateDelay, 0, 365 days));

        bytes32 what = "UD";
        vm.prank(governor);
        _saving.setParams(what, updateDelay);
        assertEq(_saving.updateDelay(), updateDelay);
    }

    function testSetSurplusManager(address surplusManager) public {
        vm.prank(governor);
        _saving.setSurplusManager(surplusManager);
        assertEq(_saving.surplusManager(), surplusManager);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        ACCRUE                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testAccrueRevertWrongCaller(uint256[3] memory initialAmounts) public {
        // no fuzzing as it shouldn't impact the result
        bytes32 what = "UD";
        vm.prank(governor);
        _saving.setParams(what, 1 days);

        // let's first load the reserves of the protocol
        (uint256 mintedStables, ) = _loadReserves(initialAmounts, 0);

        // collateral ratio = 100%
        if (mintedStables == 0) return;

        vm.startPrank(alice);
        vm.expectRevert(Errors.NotAllowed.selector);
        _saving.accrue();
        vm.stopPrank();
    }

    function testAccrueAtPegLastUpdate(uint256[3] memory initialAmounts, uint256 elapseTimestamps) public {
        elapseTimestamps = bound(elapseTimestamps, 0, _maxElapseTime);

        // no fuzzing as it shouldn't impact the result
        bytes32 what = "UD";
        vm.prank(governor);
        _saving.setParams(what, 1 days);

        // let's first load the reserves of the protocol
        (uint256 mintedStables, ) = _loadReserves(initialAmounts, 0);

        // collateral ratio = 100%
        if (mintedStables == 0) return;

        vm.startPrank(governor);
        _saving.accrue();
        skip(elapseTimestamps);
        _updateTimestampOracles();
        if (_saving.lastUpdate() > 0 && elapseTimestamps < 1 days) vm.expectRevert(Errors.NotAllowed.selector);
        _saving.accrue();
        vm.stopPrank();
    }

    function testAccrueAllAtPeg(uint256[3] memory initialAmounts, uint256 transferProportion) public {
        // no fuzzing as it shouldn't impact the result
        bytes32 what = "UD";
        vm.prank(governor);
        _saving.setParams(what, 1 days);

        // let's first load the reserves of the protocol
        (uint256 mintedStables, ) = _loadReserves(initialAmounts, transferProportion);

        // collateral ratio = 100%
        if (mintedStables == 0) return;

        // works because lastUpdate is not initialized
        vm.prank(governor);
        uint256 minted = _saving.accrue();

        assertEq(minted, 0);
        assertEq(_saving.vestingProfit(), 0);
        assertEq(_saving.lastUpdate(), 0);
        assertEq(agToken.balanceOf(address(_saving)), _initDeposit + _firstDeposit);
        assertEq(agToken.balanceOf(_surplusManager), 0);
    }

    function testAccrueGlobalAtPeg(
        uint256[3] memory initialAmounts,
        uint256 transferProportion,
        uint256[2] memory latestOracleValue
    ) public {
        // let's first load the reserves of the protocol
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(
            initialAmounts,
            transferProportion
        );

        // change oracle value but such that total collateralisation is still == 1
        for (uint256 i; i < latestOracleValue.length; ++i) {
            latestOracleValue[i] = bound(latestOracleValue[i], _minOracleValue, BASE_18);
            MockChainlinkOracle(address(_oracles[i])).setLatestAnswer(int256(latestOracleValue[i]));
        }
        uint256 collateralisation;
        for (uint256 i; i < latestOracleValue.length; ++i) {
            collateralisation += (latestOracleValue[i] * collateralMintedStables[i]) / BASE_8;
        }

        // compensate as much as possible last oracle value to make collateralRatio == 1
        // it can be impossible if one of the other oracle value is already high enough to
        // make the system over collateralised by itself or if there wasn't any minted via the last collateral
        if (mintedStables > collateralisation && collateralMintedStables[2] > 0) {
            MockChainlinkOracle(address(_oracles[2])).setLatestAnswer(
                int256(((mintedStables - collateralisation) * BASE_8) / collateralMintedStables[2])
            );

            if (mintedStables == 0) return;

            // works because lastUpdate is not initialized
            vm.prank(governor);
            uint256 minted = _saving.accrue();

            assertEq(minted, 0);
            assertEq(_saving.vestingProfit(), 0);
            assertEq(_saving.lastUpdate(), 0);
            assertEq(agToken.balanceOf(address(_saving)), _initDeposit + _firstDeposit);
            assertEq(agToken.balanceOf(_surplusManager), 0);
        }
    }

    function testAccrueRandomCollatRatioSimple(
        uint256[3] memory initialAmounts,
        uint64 protocolSafetyFee,
        uint256[3] memory latestOracleValue
    ) public {
        protocolSafetyFee = uint64(bound(protocolSafetyFee, 0, BASE_9));

        bytes32 what = "PF";
        vm.prank(governor);
        _saving.setParams(what, protocolSafetyFee);

        // let's first load the reserves of the protocol
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(initialAmounts, 0);
        if (mintedStables == 0) return;

        uint64 collatRatio = _updateOraclesWithAsserts(latestOracleValue, mintedStables, collateralMintedStables);
        vm.prank(governor);
        uint256 minted = _saving.accrue();

        if (collatRatio > BASE_9 + BASE_6) {
            // updateNormalizer will overflow so diregard this case
            // note: this can only happen if the number of unit of stable is of order 10**20
            // so safe to disregard
            if (minted + mintedStables > (uint256(type(uint128).max) * 999) / 1000) return;

            uint256 expectedMint = (collatRatio * mintedStables) / BASE_9 - mintedStables;
            uint256 shareProtocol = (protocolSafetyFee * expectedMint) / BASE_9;

            assertEq(minted, expectedMint);
            assertEq(_saving.vestingProfit(), minted - shareProtocol);
            assertEq(_saving.lastUpdate(), block.timestamp);
            assertEq(agToken.balanceOf(address(_saving)), _initDeposit + _firstDeposit + minted - shareProtocol);
            assertEq(agToken.balanceOf(_surplusManager), shareProtocol);

            // check that kheops accounting was updated
            {
                (uint64 newCollatRatio, uint256 newStablecoinsIssued) = transmuter.getCollateralRatio();
                assertApproxEqAbs(newCollatRatio, BASE_9, 1 wei);
                // There can be an approx here because of the normalizer
                _assertApproxEqRelDecimalWithTolerance(
                    newStablecoinsIssued,
                    mintedStables + minted,
                    newStablecoinsIssued,
                    _MAX_PERCENTAGE_DEVIATION,
                    18
                );
            }
            uint256 stablecoinsIssued;
            for (uint256 i; i < _collaterals.length; ++i) {
                uint256 stablecoinsFromCollateral;
                (stablecoinsFromCollateral, stablecoinsIssued) = transmuter.getIssuedByCollateral(_collaterals[i]);

                if (stablecoinsFromCollateral >= _minAmount)
                    _assertApproxEqRelDecimalWithTolerance(
                        stablecoinsFromCollateral,
                        collateralMintedStables[i].mulDiv(mintedStables + minted, mintedStables),
                        stablecoinsFromCollateral,
                        _MAX_PERCENTAGE_DEVIATION,
                        18
                    );
            }
            _assertApproxEqRelDecimalWithTolerance(
                stablecoinsIssued,
                mintedStables + minted,
                stablecoinsIssued,
                _MAX_PERCENTAGE_DEVIATION,
                18
            );
        } else {
            // under collat and at par identical case
            // we can't decrease profit when undercollat as there is none
            assertEq(minted, 0);
            assertEq(_saving.vestingProfit(), 0);
            assertEq(_saving.lastUpdate(), 0);
            assertEq(agToken.balanceOf(address(_saving)), _initDeposit + _firstDeposit);
            assertEq(agToken.balanceOf(_surplusManager), 0);

            // check that kheops accounting was updated
            {
                (uint64 newCollatRatio, uint256 newStablecoinsIssued) = transmuter.getCollateralRatio();
                assertEq(newCollatRatio, collatRatio);
                assertEq(newStablecoinsIssued, mintedStables);
            }
            uint256 stablecoinsIssued;
            for (uint256 i; i < _collaterals.length; ++i) {
                uint256 stablecoinsFromCollateral;
                (stablecoinsFromCollateral, stablecoinsIssued) = transmuter.getIssuedByCollateral(_collaterals[i]);
                assertEq(stablecoinsFromCollateral, collateralMintedStables[i]);
            }
            assertEq(stablecoinsIssued, mintedStables);
        }
    }

    function testAccrueRandomCollatRatioRevertUpdateDelay(
        uint256[3] memory initialAmounts,
        uint256 elapseTimestamps,
        uint32 updateDelay,
        uint256[3] memory latestOracleValue
    ) public {
        elapseTimestamps = bound(elapseTimestamps, 0, _maxElapseTime);
        updateDelay = uint32(bound(updateDelay, 0, _maxElapseTime));

        bytes32 what = "UD";
        vm.prank(governor);
        _saving.setParams(what, updateDelay);

        // let's first load the reserves of the protocol
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(initialAmounts, 0);
        if (mintedStables == 0) return;

        uint64 collatRatio = _updateOraclesWithAsserts(latestOracleValue, mintedStables, collateralMintedStables);
        vm.prank(governor);
        uint256 minted = _saving.accrue();
        // This would be the case if the number of unit of stable is of order 10**20 making the normalisedStables (global) overflow
        if (minted + mintedStables > (uint256(type(uint128).max) * 999) / 1000) return;

        if (collatRatio > BASE_9 + BASE_6) {
            skip(elapseTimestamps);
            _updateTimestampOracles();
            if (elapseTimestamps < updateDelay) vm.expectRevert(Errors.NotAllowed.selector);
            _saving.accrue();
            vm.stopPrank();
        }
    }

    function testAccrueRandomNegativeColatRatio(
        uint256[3] memory initialAmounts,
        uint64 protocolSafetyFee,
        uint64 vestingPeriod,
        uint256[3] memory increaseOracleValue,
        uint256[3] memory latestOracleValue,
        uint256 elapseTimestamps
    ) public {
        protocolSafetyFee = uint64(bound(protocolSafetyFee, 0, BASE_9));
        elapseTimestamps = bound(elapseTimestamps, 0, _maxElapseTime);
        vestingPeriod = uint64(bound(vestingPeriod, 1, 365 days));

        {
            bytes32 what = "VP";
            vm.prank(governor);
            _saving.setParams(what, vestingPeriod);

            what = "PF";
            vm.prank(governor);
            _saving.setParams(what, protocolSafetyFee);
        }

        // let's first load the reserves of the protocol
        (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(initialAmounts, 0);
        if (mintedStables == 0) return;

        _updateIncreaseOracles(increaseOracleValue);
        (uint64 collatRatio, ) = transmuter.getCollateralRatio();

        vm.prank(governor);
        uint256 minted = _saving.accrue();
        // Do checks only if it didn't overflow
        if (minted + mintedStables > (uint256(type(uint128).max) * 999) / 1000) return;

        uint256 netMinted = minted - (protocolSafetyFee * minted) / BASE_9;
        // Do checks only if the there has been a profit
        if (collatRatio > BASE_9 + BASE_6) {
            skip(elapseTimestamps);
            collatRatio = _updateOracles(latestOracleValue);

            uint256 prevLockedProfit = vestingPeriod > elapseTimestamps
                ? netMinted - (netMinted * elapseTimestamps) / vestingPeriod
                : 0;
            uint256 prevTotalAssets = _saving.totalAssets();
            assertEq(_saving.lockedProfit(), prevLockedProfit);
            for (uint256 i; i < collateralMintedStables.length; i++) {
                (uint256 stablecoinsFromCollateral, uint256 stablecoinsIssued) = transmuter.getIssuedByCollateral(
                    _collaterals[i]
                );
                collateralMintedStables[i] = stablecoinsFromCollateral;
                mintedStables = stablecoinsIssued;
            }

            vm.prank(governor);
            minted = _saving.accrue();

            if (collatRatio > BASE_9 + BASE_6) {
                if (minted + mintedStables > (uint256(type(uint128).max) * 999) / 1000 || minted < _minAmount) return;
                {
                    uint256 expectedMint = (collatRatio * mintedStables) / BASE_9 - mintedStables;
                    _assertApproxEqRelDecimalWithTolerance(minted, expectedMint, minted, _MAX_PERCENTAGE_DEVIATION, 18);
                }
                netMinted = minted - (protocolSafetyFee * minted) / BASE_9;
                _assertApproxEqRelDecimalWithTolerance(
                    _saving.vestingProfit(),
                    prevLockedProfit + netMinted,
                    prevLockedProfit + netMinted,
                    _MAX_PERCENTAGE_DEVIATION,
                    18
                );
                assertEq(_saving.lastUpdate(), block.timestamp);
                _assertApproxEqRelDecimalWithTolerance(
                    agToken.balanceOf(address(_saving)),
                    prevTotalAssets + prevLockedProfit + netMinted,
                    prevTotalAssets + prevLockedProfit + netMinted,
                    _MAX_PERCENTAGE_DEVIATION,
                    18
                );
                // check that kheops accounting was updated
                {
                    (uint64 newCollatRatio, uint256 newStablecoinsIssued) = transmuter.getCollateralRatio();
                    assertApproxEqAbs(newCollatRatio, BASE_9, 1 wei);
                    // There can be an approx here because of the normalizer
                    _assertApproxEqRelDecimalWithTolerance(
                        newStablecoinsIssued,
                        mintedStables + minted,
                        newStablecoinsIssued,
                        _MAX_PERCENTAGE_DEVIATION,
                        18
                    );
                }
            } else if (collatRatio < BASE_9 - BASE_6) {
                uint256 expectedBurn = mintedStables - (collatRatio * mintedStables) / BASE_9;
                if (expectedBurn > prevLockedProfit) {
                    assertEq(_saving.vestingProfit(), 0);
                    assertEq(_saving.lastUpdate(), netMinted > 0 ? block.timestamp - elapseTimestamps : 0);
                    assertEq(agToken.balanceOf(address(_saving)), prevTotalAssets);
                    {
                        (uint64 newCollatRatio, uint256 newStablecoinsIssued) = transmuter.getCollateralRatio();
                        assertLe(collatRatio, newCollatRatio);
                        _assertApproxEqRelDecimalWithTolerance(
                            newStablecoinsIssued,
                            mintedStables - prevLockedProfit,
                            newStablecoinsIssued,
                            _MAX_PERCENTAGE_DEVIATION,
                            18
                        );
                    }
                    uint256 stablecoinsIssued;
                    for (uint256 i; i < _collaterals.length; ++i) {
                        uint256 stablecoinsFromCollateral;
                        (stablecoinsFromCollateral, stablecoinsIssued) = transmuter.getIssuedByCollateral(
                            _collaterals[i]
                        );
                        assertLe(stablecoinsFromCollateral, collateralMintedStables[i]);
                    }
                    assertLe(stablecoinsIssued, mintedStables);
                } else {
                    assertApproxEqAbs(_saving.vestingProfit(), prevLockedProfit - expectedBurn, 10 wei);
                    assertEq(_saving.lastUpdate(), block.timestamp);
                    assertApproxEqAbs(
                        agToken.balanceOf(address(_saving)),
                        prevTotalAssets + prevLockedProfit - expectedBurn,
                        10 wei
                    );

                    {
                        (uint64 newCollatRatio, uint256 newStablecoinsIssued) = transmuter.getCollateralRatio();
                        // Otherwise the approximation of the needed burn can be too inacurate
                        // collatRatio will stay lower though as getCollateralRatio is always rounding up
                        // leading to a smaller amount being burnt in the `accrue` function
                        if (collatRatio > BASE_6) assertApproxEqAbs(newCollatRatio, BASE_9, 1e5);
                        _assertApproxEqRelDecimalWithTolerance(
                            newStablecoinsIssued,
                            mintedStables - expectedBurn,
                            newStablecoinsIssued,
                            _MAX_PERCENTAGE_DEVIATION,
                            18
                        );
                    }
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                          MINT / DEPOSIT / REDEEM / WITHDRAW                                        
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    // From now we consider that lockedProfit and accrue function are working as intended and we only test the process
    // of minting, depositing, redeeming and withdrawing and checking that it returns the correct amount of tokens considering the
    // distributed profit.

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

    function _updateOraclesWithAsserts(
        uint256[3] memory latestOracleValue,
        uint256 mintedStables,
        uint256[] memory collateralMintedStables
    ) internal returns (uint64 collatRatio) {
        for (uint256 i; i < latestOracleValue.length; ++i) {
            latestOracleValue[i] = bound(latestOracleValue[i], _minOracleValue, BASE_18);
            MockChainlinkOracle(address(_oracles[i])).setLatestAnswer(int256(latestOracleValue[i]));
        }

        uint256 collateralisation;
        for (uint256 i; i < latestOracleValue.length; ++i) {
            collateralisation += (latestOracleValue[i] * collateralMintedStables[i]) / BASE_8;
        }
        uint256 computedCollatRatio;
        if (mintedStables > 0) computedCollatRatio = uint64((collateralisation * BASE_9) / mintedStables);
        else computedCollatRatio = type(uint64).max;

        // check collateral ratio first
        uint256 stablecoinsIssued;
        (collatRatio, stablecoinsIssued) = transmuter.getCollateralRatio();
        if (mintedStables > 0) assertApproxEqAbs(collatRatio, computedCollatRatio, 1 wei);
        else assertEq(collatRatio, type(uint64).max);
        assertEq(stablecoinsIssued, mintedStables);
    }

    function _updateOracles(uint256[3] memory latestOracleValue) internal returns (uint64 collatRatio) {
        for (uint256 i; i < latestOracleValue.length; ++i) {
            latestOracleValue[i] = bound(latestOracleValue[i], _minOracleValue, BASE_18);
            MockChainlinkOracle(address(_oracles[i])).setLatestAnswer(int256(latestOracleValue[i]));
        }
        (collatRatio, ) = transmuter.getCollateralRatio();
    }

    function _updateIncreaseOracles(uint256[3] memory latestOracleValue) internal {
        for (uint256 i; i < _oracles.length; i++) {
            (, int256 value, , , ) = _oracles[i].latestRoundData();
            latestOracleValue[i] = bound(latestOracleValue[i], uint256(value), BASE_18);
            MockChainlinkOracle(address(_oracles[i])).setLatestAnswer(int256(latestOracleValue[i]));
        }
    }

    function _updateTimestampOracles() internal {
        for (uint256 i; i < _oracles.length; i++) {
            (, int256 value, , , ) = _oracles[i].latestRoundData();
            MockChainlinkOracle(address(_oracles[i])).setLatestAnswer(value);
        }
    }

    function _deposit(
        uint256 amount,
        address owner,
        address receiver,
        uint256 indexReceiver
    ) internal returns (uint256, address) {
        if (receiver == address(0)) receiver = actors[bound(indexReceiver, 0, _nbrActor - 1)];

        deal(address(agToken), owner, amount);
        vm.startPrank(owner);
        agToken.approve(address(_saving), amount);
        uint256 shares = _saving.deposit(amount, receiver);
        vm.stopPrank();

        return (shares, receiver);
    }

    function _mint(
        uint256 shares,
        uint256 estimatedAmount,
        address owner,
        address receiver,
        uint256 indexReceiver
    ) internal returns (uint256, uint256, address) {
        if (receiver == address(0)) receiver = actors[bound(indexReceiver, 0, _nbrActor - 1)];

        deal(address(agToken), owner, estimatedAmount);
        vm.startPrank(owner);
        agToken.approve(address(_saving), estimatedAmount);
        uint256 amount = _saving.mint(shares, receiver);
        vm.stopPrank();
        return (amount, shares, receiver);
    }

    function _sweepBalances(address owner, address[] memory tokens) internal {
        vm.startPrank(owner);
        for (uint256 i; i < tokens.length; ++i) {
            IERC20(tokens[i]).transfer(sweeper, IERC20(tokens[i]).balanceOf(owner));
        }
        vm.stopPrank();
    }
}
