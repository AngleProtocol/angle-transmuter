// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "../mock/MockTokenPermit.sol";
import "../Fixture.sol";
import "../utils/FunctionUtils.sol";
import "contracts/utils/Errors.sol" as Errors;
import "contracts/savings/Savings.sol";
import { UD60x18, ud, pow, powu, unwrap } from "prb/math/UD60x18.sol";

import { stdError } from "forge-std/Test.sol";

contract SavingsTest is Fixture, FunctionUtils {
    using SafeERC20 for IERC20;

    uint256 internal constant _initDeposit = 1e12;
    uint256 internal constant _minAmount = 10 ** 10;
    uint256 internal constant _maxAmount = 10 ** (18 + 15);
    // Annually this represent a 2250% APY
    uint256 internal constant _maxRate = 10 ** (27 - 7);
    // Annually this represent a 0.0003% APY
    uint256 internal constant _minRate = 10 ** (27 - 13);
    uint256 internal constant _maxElapseTime = 20 days;
    uint256 internal constant _nbrActor = 10;
    Savings internal _saving;
    Savings internal _savingImplementation;
    string internal _name;
    string internal _symbol;
    address[] public actors;

    function setUp() public override {
        super.setUp();

        _savingImplementation = new Savings();
        bytes memory data;
        _saving = Savings(deployUpgradeable(address(_savingImplementation), data));
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
            _name,
            _symbol,
            BASE_18 / _initDeposit
        );
        vm.stopPrank();
    }

    function test_Initialization() public {
        assertEq(address(_saving.accessControlManager()), address(accessControlManager));
        assertEq(_saving.asset(), address(agToken));
        assertEq(_saving.name(), _name);
        assertEq(_saving.symbol(), _symbol);
        assertEq(_saving.totalAssets(), _initDeposit);
        assertEq(_saving.totalSupply(), _initDeposit);
        assertEq(agToken.balanceOf(address(_saving)), _initDeposit);
        assertEq(_saving.balanceOf(address(governor)), 0);
        assertEq(_saving.balanceOf(address(_saving)), _initDeposit);
    }

    function test_Initialize() public {
        // To have the test written at least once somewhere
        assert(accessControlManager.isGovernor(governor));
        assert(accessControlManager.isGovernorOrGuardian(guardian));
        assert(accessControlManager.isGovernorOrGuardian(governor));
        bytes memory data;
        Savings savingsContract = Savings(deployUpgradeable(address(_savingImplementation), data));
        Savings savingsContract2 = Savings(deployUpgradeable(address(_savingImplementation), data));

        vm.startPrank(governor);
        agToken.addMinter(address(savingsContract));
        deal(address(agToken), governor, _initDeposit * 10);
        agToken.approve(address(savingsContract), _initDeposit);
        agToken.approve(address(savingsContract2), _initDeposit);

        savingsContract.initialize(
            accessControlManager,
            IERC20MetadataUpgradeable(address(agToken)),
            _name,
            _symbol,
            BASE_18 / _initDeposit
        );

        vm.expectRevert();
        savingsContract.initialize(
            accessControlManager,
            IERC20MetadataUpgradeable(address(agToken)),
            _name,
            _symbol,
            BASE_18 / _initDeposit
        );

        vm.expectRevert(Errors.ZeroAddress.selector);
        savingsContract2.initialize(
            IAccessControlManager(address(0)),
            IERC20MetadataUpgradeable(address(agToken)),
            _name,
            _symbol,
            BASE_18 / _initDeposit
        );

        vm.stopPrank();

        assertEq(address(savingsContract.accessControlManager()), address(accessControlManager));
        assertEq(savingsContract.asset(), address(agToken));
        assertEq(savingsContract.name(), _name);
        assertEq(savingsContract.symbol(), _symbol);
        assertEq(savingsContract.totalAssets(), _initDeposit);
        assertEq(savingsContract.totalSupply(), _initDeposit);
        assertEq(agToken.balanceOf(address(savingsContract)), _initDeposit);
        assertEq(savingsContract.balanceOf(address(governor)), 0);
        assertEq(savingsContract.balanceOf(address(savingsContract)), _initDeposit);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         PAUSE                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function test_Pause() public {
        _deposit(BASE_18, alice, alice, 0);

        vm.prank(governor);
        _saving.togglePause();

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

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         APRS                                                       
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_SetRate(uint256 rate) public {
        // we need to decrease to a smaller maxRate = 37% otherwise the approximation is way off
        // even currently we can not achieve a 0.1% precision
        rate = bound(rate, _minRate, _maxRate / 10);
        vm.prank(governor);
        _saving.setRate(uint208(rate));

        assertEq(_saving.rate(), rate);
        uint256 estimatedAPR = (BASE_18 * unwrap(powu(ud(BASE_18 + rate / BASE_9), 365 days))) /
            unwrap(powu(ud(BASE_18), 365 days)) -
            BASE_18;

        _assertApproxEqRelDecimalWithTolerance(
            _saving.estimatedAPR(),
            estimatedAPR,
            estimatedAPR,
            _MAX_PERCENTAGE_DEVIATION * 5000,
            18
        );
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        DEPOSIT                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_DepositSimple(uint256 amount, uint256 indexReceiver) public {
        amount = bound(amount, 0, _maxAmount);

        address receiver;
        uint256 shares;

        {
            uint256 supposedShares = _saving.previewDeposit(amount);
            (shares, receiver) = _deposit(amount, alice, address(0), indexReceiver);
            assertEq(shares, supposedShares);
        }

        assertEq(shares, amount);
        assertEq(_saving.totalAssets(), _initDeposit + amount);
        assertEq(_saving.totalSupply(), _initDeposit + shares);
        assertEq(agToken.balanceOf(address(_saving)), _initDeposit + amount);
        assertEq(_saving.balanceOf(address(alice)), 0);
        assertEq(_saving.balanceOf(receiver), shares);
    }

    function testFuzz_DepositSingleRate(
        uint256[2] memory amounts,
        uint256 rate,
        uint256 indexReceiver,
        uint256[2] memory elapseTimestamps
    ) public {
        for (uint256 i; i < amounts.length; i++) amounts[i] = bound(amounts[i], 0, _maxAmount);
        rate = bound(rate, _minRate, _maxRate);
        // shorten the time otherwise the DL diverge too much from the actual formula (1+rate)**seconds
        elapseTimestamps[0] = bound(elapseTimestamps[0], 0, _maxElapseTime);
        elapseTimestamps[1] = bound(elapseTimestamps[1], 0, _maxElapseTime);

        _deposit(amounts[0], sweeper, sweeper, 0);

        vm.prank(governor);
        _saving.setRate(uint208(rate));

        // first time elapse
        skip(elapseTimestamps[0]);
        uint256 compoundAssets = ((amounts[0] + _initDeposit) *
            unwrap(powu(ud(BASE_18 + rate / BASE_9), elapseTimestamps[0]))) /
            unwrap(powu(ud(BASE_18), elapseTimestamps[0]));
        {
            uint256 shares = _saving.balanceOf(sweeper);
            _assertApproxEqRelDecimalWithTolerance(
                _saving.totalAssets(),
                compoundAssets,
                compoundAssets,
                _MAX_PERCENTAGE_DEVIATION * 100,
                18
            );
            assertEq(shares, amounts[0]);
            assertApproxEqAbs(
                _saving.convertToAssets(shares),
                (_saving.totalAssets() * shares) / ((shares + _initDeposit)),
                1 wei
            );
            assertApproxEqAbs(
                _saving.previewRedeem(shares),
                (_saving.totalAssets() * shares) / ((shares + _initDeposit)),
                1 wei
            );
        }

        address receiver;
        uint256 returnShares;
        {
            uint256 prevShares = _saving.totalSupply();
            uint256 balanceAsset = _saving.totalAssets();
            uint256 supposedShares = _saving.previewDeposit(amounts[1]);
            (returnShares, receiver) = _deposit(amounts[1], alice, address(0), indexReceiver);
            uint256 expectedShares = (amounts[1] * prevShares) / balanceAsset;
            assertEq(returnShares, expectedShares);
            assertEq(supposedShares, returnShares);
        }

        // second time elapse
        skip(elapseTimestamps[1]);

        {
            uint256 newCompoundAssets = ((compoundAssets + amounts[1]) *
                unwrap(powu(ud(BASE_18 + rate / BASE_9), elapseTimestamps[1]))) /
                unwrap(powu(ud(BASE_18), elapseTimestamps[1]));
            uint256 shares = _saving.balanceOf(receiver);
            assertEq(shares, returnShares);

            _assertApproxEqRelDecimalWithTolerance(
                _saving.totalAssets(),
                newCompoundAssets,
                newCompoundAssets,
                _MAX_PERCENTAGE_DEVIATION * 100,
                18
            );
            _assertApproxEqRelDecimalWithTolerance(
                _saving.computeUpdatedAssets(compoundAssets + amounts[1], elapseTimestamps[1]),
                newCompoundAssets,
                newCompoundAssets,
                _MAX_PERCENTAGE_DEVIATION * 100,
                18
            );
            assertApproxEqAbs(
                _saving.convertToAssets(shares),
                (_saving.totalAssets() * shares) / _saving.totalSupply(),
                1 wei
            );
            assertApproxEqAbs(
                _saving.previewRedeem(shares),
                (_saving.totalAssets() * shares) / _saving.totalSupply(),
                1 wei
            );
        }
    }

    function testFuzz_DepositMultiRate(
        uint256[3] memory amounts,
        uint256[2] memory rates,
        uint256 indexReceiver,
        uint256[3] memory elapseTimestamps
    ) public {
        for (uint256 i; i < amounts.length; i++) amounts[i] = bound(amounts[i], 0, _maxAmount);
        // shorten the time otherwise the DL diverge too much from the actual formula (1+rate)**seconds
        for (uint256 i; i < elapseTimestamps.length; i++)
            elapseTimestamps[i] = bound(elapseTimestamps[i], 0, _maxElapseTime);
        for (uint256 i; i < rates.length; i++) rates[i] = bound(rates[i], _minRate, _maxRate);

        _deposit(amounts[0], sweeper, sweeper, 0);

        vm.prank(governor);
        _saving.setRate(uint208(rates[0]));

        // first time elapse
        skip(elapseTimestamps[0]);
        _deposit(amounts[1], sweeper, sweeper, 0);

        vm.prank(governor);
        _saving.setRate(uint208(rates[1]));

        uint256 prevTotalAssets = _saving.totalAssets();

        // second time elapse
        skip(elapseTimestamps[1]);

        address receiver;
        uint256 returnShares;
        {
            uint256 prevShares = _saving.totalSupply();
            uint256 newCompoundAssets = (prevTotalAssets *
                unwrap(powu(ud(BASE_18 + rates[1] / BASE_9), elapseTimestamps[1]))) /
                unwrap(powu(ud(BASE_18), elapseTimestamps[1]));
            uint256 balanceAsset = _saving.totalAssets();
            _assertApproxEqRelDecimalWithTolerance(
                balanceAsset,
                newCompoundAssets,
                newCompoundAssets,
                _MAX_PERCENTAGE_DEVIATION * 100,
                18
            );
            uint256 supposedShares = _saving.previewDeposit(amounts[2]);
            (returnShares, receiver) = _deposit(amounts[2], alice, address(0), indexReceiver);
            uint256 shares = _saving.balanceOf(receiver);
            uint256 expectedShares = (amounts[2] * prevShares) / balanceAsset;
            assertEq(shares, returnShares);
            assertEq(returnShares, expectedShares);
            assertEq(supposedShares, returnShares);
        }
        // third time elapse
        skip(elapseTimestamps[2]);

        {
            uint256 newCompoundAssets = (prevTotalAssets *
                unwrap(powu(ud(BASE_18 + rates[1] / BASE_9), elapseTimestamps[1]))) /
                unwrap(powu(ud(BASE_18), elapseTimestamps[1]));
            newCompoundAssets =
                ((newCompoundAssets + amounts[2]) *
                    unwrap(powu(ud(BASE_18 + rates[1] / BASE_9), elapseTimestamps[2]))) /
                unwrap(powu(ud(BASE_18), elapseTimestamps[2]));

            _assertApproxEqRelDecimalWithTolerance(
                _saving.totalAssets(),
                newCompoundAssets,
                newCompoundAssets,
                _MAX_PERCENTAGE_DEVIATION * 100,
                18
            );
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         MINT                                                       
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_MintSimple(uint256 shares, uint256 indexReceiver) public {
        shares = bound(shares, 0, _maxAmount);

        uint256 amount;
        address receiver;
        (amount, shares, receiver) = _mint(shares, shares, alice, address(0), indexReceiver);

        assertEq(amount, shares);
        assertEq(_saving.totalAssets(), _initDeposit + amount);
        assertEq(_saving.totalSupply(), _initDeposit + shares);
        assertEq(agToken.balanceOf(address(_saving)), _initDeposit + amount);
        assertEq(_saving.balanceOf(address(alice)), 0);
        assertEq(_saving.balanceOf(receiver), shares);
    }

    function testFuzz_MintNonNullRate(
        uint256[2] memory shares,
        uint256 rate,
        uint256 indexReceiver,
        uint256[2] memory elapseTimestamps
    ) public {
        for (uint256 i; i < shares.length; i++) shares[i] = bound(shares[i], 0, _maxAmount);
        rate = bound(rate, _minRate, _maxRate);
        // shorten the time otherwise the DL diverge too much from the actual formula (1+rate)**seconds
        elapseTimestamps[0] = bound(elapseTimestamps[0], 0, _maxElapseTime);
        elapseTimestamps[1] = bound(elapseTimestamps[1], 0, _maxElapseTime);

        _deposit(shares[0], sweeper, sweeper, 0);

        vm.prank(governor);
        _saving.setRate(uint208(rate));

        // first time elapse
        skip(elapseTimestamps[0]);
        uint256 compoundAssets = ((shares[0] + _initDeposit) *
            unwrap(powu(ud(BASE_18 + rate / BASE_9), elapseTimestamps[0]))) /
            unwrap(powu(ud(BASE_18), elapseTimestamps[0]));

        address receiver;
        uint256 returnAmount;
        {
            uint256 prevShares = _saving.totalSupply();
            uint256 balanceAsset = _saving.totalAssets();
            uint256 supposedAmount = _saving.previewMint(shares[1]);
            (returnAmount, , receiver) = _mint(shares[1], supposedAmount, alice, address(0), indexReceiver);
            uint256 expectedAmount = (shares[1] * balanceAsset) / prevShares;
            assertEq(shares[1], _saving.balanceOf(receiver));
            assertApproxEqAbs(returnAmount, expectedAmount, 1 wei);
            assertEq(returnAmount, supposedAmount);
        }

        // second time elapse
        skip(elapseTimestamps[1]);

        {
            uint256 increasedRate = (BASE_18 * unwrap(powu(ud(BASE_18 + rate / BASE_9), elapseTimestamps[1]))) /
                unwrap(powu(ud(BASE_18), elapseTimestamps[1]));
            uint256 newCompoundAssets = (((compoundAssets + returnAmount) * increasedRate) / BASE_18);

            _assertApproxEqRelDecimalWithTolerance(
                _saving.totalAssets(),
                newCompoundAssets,
                newCompoundAssets,
                _MAX_PERCENTAGE_DEVIATION * 100,
                18
            );
            _assertApproxEqRelDecimalWithTolerance(
                _saving.computeUpdatedAssets(compoundAssets + returnAmount, elapseTimestamps[1]),
                newCompoundAssets,
                newCompoundAssets,
                _MAX_PERCENTAGE_DEVIATION * 100,
                18
            );
            if (_minAmount < (shares[1] * BASE_18) / increasedRate) {
                _assertApproxEqRelDecimalWithTolerance(
                    _saving.convertToShares(returnAmount),
                    (shares[1] * BASE_18) / increasedRate,
                    (shares[1] * BASE_18) / increasedRate,
                    _MAX_PERCENTAGE_DEVIATION * 100,
                    18
                );
                _assertApproxEqRelDecimalWithTolerance(
                    _saving.previewWithdraw(returnAmount),
                    (shares[1] * BASE_18) / increasedRate,
                    (shares[1] * BASE_18) / increasedRate,
                    _MAX_PERCENTAGE_DEVIATION * 100,
                    18
                );
            }
        }
    }

    function testFuzz_MintMultiRate(
        uint256[3] memory shares,
        uint256[2] memory rates,
        uint256 indexReceiver,
        uint256[3] memory elapseTimestamps
    ) public {
        for (uint256 i; i < shares.length; i++) shares[i] = bound(shares[i], 0, _maxAmount);
        // shorten the time otherwise the DL diverge too much from the actual formula (1+rate)**seconds
        for (uint256 i; i < elapseTimestamps.length; i++)
            elapseTimestamps[i] = bound(elapseTimestamps[i], 0, _maxElapseTime);
        for (uint256 i; i < rates.length; i++) rates[i] = bound(rates[i], _minRate, _maxRate);

        _deposit(shares[0], sweeper, sweeper, 0);

        vm.prank(governor);
        _saving.setRate(uint208(rates[0]));

        // first time elapse
        skip(elapseTimestamps[0]);
        _deposit(shares[1], sweeper, sweeper, 0);

        vm.prank(governor);
        _saving.setRate(uint208(rates[1]));

        uint256 prevTotalAssets = _saving.totalAssets();

        // second time elapse
        skip(elapseTimestamps[1]);

        address receiver;
        uint256 returnAmount;
        {
            uint256 prevShares = _saving.totalSupply();
            uint256 balanceAsset = _saving.totalAssets();
            uint256 supposedAmount = _saving.previewMint(shares[2]);
            (returnAmount, , receiver) = _mint(shares[2], supposedAmount, alice, address(0), indexReceiver);
            assertEq(agToken.balanceOf(alice), 0);
            uint256 expectedAmount = (shares[2] * balanceAsset) / prevShares;
            assertEq(shares[2], _saving.balanceOf(receiver));
            assertApproxEqAbs(returnAmount, expectedAmount, 1 wei);
            assertEq(returnAmount, supposedAmount);
        }
        // third time elapse
        skip(elapseTimestamps[2]);

        uint256 newCompoundAssets = (prevTotalAssets *
            unwrap(powu(ud(BASE_18 + rates[1] / BASE_9), elapseTimestamps[1]))) /
            unwrap(powu(ud(BASE_18), elapseTimestamps[1]));
        newCompoundAssets =
            ((newCompoundAssets + returnAmount) * unwrap(powu(ud(BASE_18 + rates[1] / BASE_9), elapseTimestamps[2]))) /
            unwrap(powu(ud(BASE_18), elapseTimestamps[2]));

        uint256 withdrawableAmount = (returnAmount *
            unwrap(powu(ud(BASE_18 + rates[1] / BASE_9), elapseTimestamps[2]))) /
            unwrap(powu(ud(BASE_18), elapseTimestamps[2]));

        if (withdrawableAmount > _minAmount) {
            _assertApproxEqRelDecimalWithTolerance(
                _saving.previewRedeem(_saving.balanceOf(receiver)),
                withdrawableAmount,
                withdrawableAmount,
                _MAX_PERCENTAGE_DEVIATION * 100,
                18
            );

            _assertApproxEqRelDecimalWithTolerance(
                _saving.totalAssets(),
                newCompoundAssets,
                newCompoundAssets,
                _MAX_PERCENTAGE_DEVIATION * 100,
                18
            );
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        REDEEM                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_RedeemSuccess(
        uint256[2] memory amounts,
        uint256 propWithdraw,
        uint256 rate,
        uint256 indexReceiver,
        uint256[2] memory elapseTimestamps
    ) public {
        for (uint256 i; i < amounts.length; i++) amounts[i] = bound(amounts[i], 0, _maxAmount);
        // shorten the time otherwise the DL diverge too much from the actual formula (1+rate)**seconds
        for (uint256 i; i < elapseTimestamps.length; i++)
            elapseTimestamps[i] = bound(elapseTimestamps[i], 0, _maxElapseTime);
        rate = bound(rate, _minRate, _maxRate);
        propWithdraw = bound(propWithdraw, 0, BASE_9);
        address receiver = actors[bound(indexReceiver, 0, _nbrActor - 1)];

        _deposit(amounts[0], sweeper, sweeper, 0);

        vm.prank(governor);
        _saving.setRate(uint208(rate));

        // first time elapse
        skip(elapseTimestamps[0]);
        _deposit(amounts[1], alice, alice, 0);

        // second time elapse
        skip(elapseTimestamps[1]);

        uint256 withdrawableAmount = (amounts[1] * unwrap(powu(ud(BASE_18 + rate / BASE_9), elapseTimestamps[1]))) /
            unwrap(powu(ud(BASE_18), elapseTimestamps[1]));

        if (withdrawableAmount > _minAmount) {
            _assertApproxEqRelDecimalWithTolerance(
                _saving.previewRedeem(_saving.balanceOf(alice)),
                withdrawableAmount,
                withdrawableAmount,
                _MAX_PERCENTAGE_DEVIATION * 100,
                18
            );

            {
                address[] memory tokens = new address[](1);
                tokens[0] = address(agToken);
                _sweepBalances(alice, tokens);
                _sweepBalances(receiver, tokens);
            }

            uint256 shares = _saving.balanceOf(alice);
            uint256 sharesToRedeem = (shares * propWithdraw) / BASE_9;
            uint256 amount;
            {
                uint256 previewAmount = _saving.previewRedeem(sharesToRedeem);
                vm.prank(alice);
                amount = _saving.redeem(sharesToRedeem, receiver, alice);
                assertEq(previewAmount, amount);
            }
            _assertApproxEqRelDecimalWithTolerance(
                amount,
                (withdrawableAmount * propWithdraw) / BASE_9,
                amount,
                _MAX_PERCENTAGE_DEVIATION * 100,
                18
            );
            assertEq(agToken.balanceOf(receiver), amount);
            assertEq(agToken.balanceOf(alice), 0);
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       WITHDRAW                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_MaxWithdrawSuccess(
        uint256[2] memory amounts,
        uint256 rate,
        uint256 indexReceiver,
        uint256[2] memory elapseTimestamps
    ) public {
        for (uint256 i; i < amounts.length; i++) amounts[i] = bound(amounts[i], 0, _maxAmount);
        // shorten the time otherwise the DL diverge too much from the actual formula (1+rate)**seconds
        for (uint256 i; i < elapseTimestamps.length; i++)
            elapseTimestamps[i] = bound(elapseTimestamps[i], 0, _maxElapseTime);
        rate = bound(rate, _minRate, _maxRate);
        address receiver = actors[bound(indexReceiver, 0, _nbrActor - 1)];

        _deposit(amounts[0], sweeper, sweeper, 0);

        vm.prank(governor);
        _saving.setRate(uint208(rate));

        // first time elapse
        skip(elapseTimestamps[0]);
        _deposit(amounts[1], alice, alice, 0);

        // second time elapse
        skip(elapseTimestamps[1]);

        uint256 shares = _saving.balanceOf(alice);
        uint256 withdrawableAmount = _saving.maxWithdraw(alice);

        _assertApproxEqRelDecimalWithTolerance(
            _saving.previewWithdraw(withdrawableAmount),
            shares,
            shares,
            _MAX_PERCENTAGE_DEVIATION * 100,
            18
        );

        vm.startPrank(alice);
        vm.expectRevert(bytes("ERC20: burn amount exceeds balance"));
        _saving.withdraw(withdrawableAmount + 1, receiver, alice);
        uint256 sharesBurnt = _saving.withdraw(withdrawableAmount, receiver, alice);
        vm.stopPrank();

        assertEq(sharesBurnt, shares);
        assertEq(agToken.balanceOf(receiver), withdrawableAmount);
        assertEq(agToken.balanceOf(alice), 0);
        assertEq(_saving.balanceOf(alice), 0);
    }

    function testFuzz_WithdrawSuccess(
        uint256[2] memory amounts,
        uint256 propWithdraw,
        uint256 rate,
        uint256 indexReceiver,
        uint256[2] memory elapseTimestamps
    ) public {
        for (uint256 i; i < amounts.length; i++) amounts[i] = bound(amounts[i], 0, _maxAmount);
        // shorten the time otherwise the DL diverge too much from the actual formula (1+rate)**seconds
        for (uint256 i; i < elapseTimestamps.length; i++)
            elapseTimestamps[i] = bound(elapseTimestamps[i], 0, _maxElapseTime);
        rate = bound(rate, _minRate, _maxRate);
        propWithdraw = bound(propWithdraw, 0, BASE_9);
        address receiver = actors[bound(indexReceiver, 0, _nbrActor - 1)];

        _deposit(amounts[0], sweeper, sweeper, 0);

        vm.prank(governor);
        _saving.setRate(uint208(rate));

        // first time elapse
        skip(elapseTimestamps[0]);
        _deposit(amounts[1], alice, alice, 0);

        // second time elapse
        skip(elapseTimestamps[1]);

        uint256 withdrawableAmount = (amounts[1] * unwrap(powu(ud(BASE_18 + rate / BASE_9), elapseTimestamps[1]))) /
            unwrap(powu(ud(BASE_18), elapseTimestamps[1]));

        if (withdrawableAmount > _minAmount) {
            uint256 shares = _saving.balanceOf(alice);

            _assertApproxEqRelDecimalWithTolerance(
                _saving.maxWithdraw(alice),
                withdrawableAmount,
                withdrawableAmount,
                _MAX_PERCENTAGE_DEVIATION * 100,
                18
            );

            withdrawableAmount = _saving.maxWithdraw(alice);

            _assertApproxEqRelDecimalWithTolerance(
                _saving.previewWithdraw(withdrawableAmount),
                shares,
                shares,
                _MAX_PERCENTAGE_DEVIATION * 100,
                18
            );

            {
                address[] memory tokens = new address[](1);
                tokens[0] = address(agToken);
                _sweepBalances(alice, tokens);
                _sweepBalances(receiver, tokens);
            }

            uint256 amountToRedeem = (withdrawableAmount * propWithdraw) / BASE_9;
            vm.startPrank(alice);
            uint256 sharesBurnt = _saving.withdraw(amountToRedeem, receiver, alice);
            vm.stopPrank();

            _assertApproxEqRelDecimalWithTolerance(
                sharesBurnt,
                (shares * propWithdraw) / BASE_9,
                sharesBurnt,
                _MAX_PERCENTAGE_DEVIATION * 100,
                18
            );
            assertEq(agToken.balanceOf(receiver), amountToRedeem);
            assertEq(agToken.balanceOf(alice), 0);
            assertEq(_saving.balanceOf(alice), shares - sharesBurnt);
            _assertApproxEqRelDecimalWithTolerance(
                _saving.convertToAssets(_saving.balanceOf(alice)),
                withdrawableAmount - amountToRedeem,
                withdrawableAmount - amountToRedeem,
                _MAX_PERCENTAGE_DEVIATION * 100,
                18
            );
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         UTILS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

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
