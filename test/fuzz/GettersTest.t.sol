// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";
import "oz/utils/Strings.sol";
import { IERC20Metadata } from "../mock/MockTokenPermit.sol";
import "../Fixture.sol";
import "../utils/FunctionUtils.sol";
import "contracts/utils/Errors.sol";
import { stdError } from "forge-std/Test.sol";

import { Collateral } from "contracts/transmuter/Storage.sol";

contract GettersTest is Fixture, FunctionUtils {
    using SafeERC20 for IERC20;

    int64 internal _minRedeemFee = 0;
    int64 internal _minMintFee = -int64(int256(BASE_9 / 2));
    int64 internal _minBurnFee = -int64(int256(BASE_9 / 2));
    int64 internal _maxRedeemFee = int64(int256(BASE_9));
    int64 internal _maxMintFee = int64(int256(BASE_12));
    int64 internal _maxBurnFee = int64(int256((BASE_9 * 999) / 1000));

    address[] internal _collaterals;
    AggregatorV3Interface[] internal _oracles;
    uint256[] internal _maxTokenAmount;

    function setUp() public override {
        super.setUp();

        _collaterals.push(address(eurA));
        _collaterals.push(address(eurB));
        _collaterals.push(address(eurY));
        _oracles.push(oracleA);
        _oracles.push(oracleB);
        _oracles.push(oracleY);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       RAW CALLS                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function test_GetRawCalls() public {
        IAccessControlManager accessControlManagerTransmuter = transmuter.accessControlManager();
        IAgToken agTokenTransmuter = transmuter.agToken();
        assertEq(address(agToken), address(agTokenTransmuter));
        assertEq(address(accessControlManager), address(accessControlManagerTransmuter));
    }

    function test_AccessControl() public {
        IAccessControlManager accessControlManagerTransmuter = transmuter.accessControlManager();
        assertEq(true, accessControlManagerTransmuter.isGovernor(governor));
        assertEq(false, accessControlManagerTransmuter.isGovernor(guardian));
        assertEq(false, accessControlManagerTransmuter.isGovernor(alice));
        assertEq(true, accessControlManagerTransmuter.isGovernorOrGuardian(governor));
        assertEq(true, accessControlManagerTransmuter.isGovernorOrGuardian(guardian));
        assertEq(false, accessControlManagerTransmuter.isGovernorOrGuardian(alice));
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                   GETCOLLATERALLIST                                                
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_GetCollateralList(uint256 addCollateral) public {
        addCollateral = bound(addCollateral, 0, 43);
        vm.startPrank(governor);
        for (uint256 i; i < addCollateral; i++) {
            address eurCollat = address(
                new MockTokenPermit(
                    string.concat("EUR_", Strings.toString(i)),
                    string.concat("EUR_", Strings.toString(i)),
                    18
                )
            );
            transmuter.addCollateral(eurCollat);
            _collaterals.push(eurCollat);
        }
        vm.stopPrank();
        address[] memory collateralList = transmuter.getCollateralList();
        assertEq(_collaterals, collateralList);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                   GETCOLLATERALINFO                                                
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_GetCollateralInfo(
        uint256 fromToken,
        uint64[10] memory xFeeMintUnbounded,
        int64[10] memory yFeeMintUnbounded
    ) public {
        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        _setBurnFeesForNegativeMintFees();
        (uint64[] memory xFeeMint, int64[] memory yFeeMint) = _randomMintFees(
            _collaterals[fromToken],
            xFeeMintUnbounded,
            yFeeMintUnbounded
        );
        Collateral memory collat = transmuter.getCollateralInfo(_collaterals[fromToken]);
        _assertArrayUint64(xFeeMint, collat.xFeeMint);
        _assertArrayInt64(yFeeMint, collat.yFeeMint);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                 GETCOLLATERALMINTFEES                                              
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_GetCollateralMintFees(
        uint256 fromToken,
        uint64[10] memory xFeeMintUnbounded,
        int64[10] memory yFeeMintUnbounded
    ) public {
        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        _setBurnFeesForNegativeMintFees();
        (uint64[] memory xFeeMint, int64[] memory yFeeMint) = _randomMintFees(
            _collaterals[fromToken],
            xFeeMintUnbounded,
            yFeeMintUnbounded
        );
        (uint64[] memory xRealFeeMint, int64[] memory yRealFeeMint) = transmuter.getCollateralMintFees(
            _collaterals[fromToken]
        );
        _assertArrayUint64(xFeeMint, xRealFeeMint);
        _assertArrayInt64(yFeeMint, yRealFeeMint);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                 GETCOLLATERALBURNFEES                                              
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_GetCollateralBurnFees(
        uint256 fromToken,
        uint64[10] memory xFeeBurnUnbounded,
        int64[10] memory yFeeBurnUnbounded
    ) public {
        fromToken = bound(fromToken, 0, _collaterals.length - 1);
        _setMintFeesForNegativeBurnFees();
        (uint64[] memory xFeeBurn, int64[] memory yFeeBurn) = _randomBurnFees(
            _collaterals[fromToken],
            xFeeBurnUnbounded,
            yFeeBurnUnbounded
        );
        (uint64[] memory xRealFeeBurn, int64[] memory yRealFeeBurn) = transmuter.getCollateralBurnFees(
            _collaterals[fromToken]
        );
        _assertArrayUint64(xFeeBurn, xRealFeeBurn);
        _assertArrayInt64(yFeeBurn, yRealFeeBurn);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                   GETREDEMPTIONFEES                                                
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_GetRedemptionFees(
        uint64[10] memory xFeeRedemptionUnbounded,
        int64[10] memory yFeeRedemptionUnbounded
    ) public {
        (uint64[] memory xFeeRedemption, int64[] memory yFeeRedemption) = _randomRedemptionFees(
            xFeeRedemptionUnbounded,
            yFeeRedemptionUnbounded
        );
        (uint64[] memory xRealFeeRedemption, int64[] memory yRealFeeRedemption) = transmuter.getRedemptionFees();
        _assertArrayUint64(xFeeRedemption, xRealFeeRedemption);
        _assertArrayInt64(yFeeRedemption, yRealFeeRedemption);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        ASSERTS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _assertArrayUint64(uint64[] memory a, uint64[] memory b) internal {
        if (keccak256(abi.encode(a)) != keccak256(abi.encode(b))) {
            fail();
        }
    }

    function _assertArrayInt64(int64[] memory a, int64[] memory b) internal {
        if (keccak256(abi.encode(a)) != keccak256(abi.encode(b))) {
            fail();
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         UTILS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _setMintFeesForNegativeBurnFees() internal {
        // set mint Fees to be consistent with the min fee on Burn
        uint64[] memory xFee = new uint64[](1);
        xFee[0] = uint64(0);
        int64[] memory yFee = new int64[](1);
        yFee[0] = -_minMintFee;
        vm.startPrank(governor);
        transmuter.setFees(address(eurA), xFee, yFee, true);
        transmuter.setFees(address(eurB), xFee, yFee, true);
        transmuter.setFees(address(eurY), xFee, yFee, true);
        vm.stopPrank();
    }

    function _setBurnFeesForNegativeMintFees() internal {
        // set mint Fees to be consistent with the min fee on Burn
        uint64[] memory xFee = new uint64[](1);
        xFee[0] = uint64(BASE_9);
        int64[] memory yFee = new int64[](1);
        yFee[0] = -_minBurnFee;
        vm.startPrank(governor);
        transmuter.setFees(address(eurA), xFee, yFee, false);
        transmuter.setFees(address(eurB), xFee, yFee, false);
        transmuter.setFees(address(eurY), xFee, yFee, false);
        vm.stopPrank();
    }

    function _randomRedemptionFees(
        uint64[10] memory xFeeRedeemUnbounded,
        int64[10] memory yFeeRedeemUnbounded
    ) internal returns (uint64[] memory xFeeRedeem, int64[] memory yFeeRedeem) {
        (xFeeRedeem, yFeeRedeem) = _generateCurves(
            xFeeRedeemUnbounded,
            yFeeRedeemUnbounded,
            true,
            false,
            _minRedeemFee,
            _maxRedeemFee
        );
        vm.prank(governor);
        transmuter.setRedemptionCurveParams(xFeeRedeem, yFeeRedeem);
    }

    function _randomBurnFees(
        address collateral,
        uint64[10] memory xFeeBurnUnbounded,
        int64[10] memory yFeeBurnUnbounded
    ) internal returns (uint64[] memory xFeeBurn, int64[] memory yFeeBurn) {
        (xFeeBurn, yFeeBurn) = _generateCurves(
            xFeeBurnUnbounded,
            yFeeBurnUnbounded,
            false,
            false,
            _minBurnFee,
            _maxBurnFee
        );
        vm.prank(governor);
        transmuter.setFees(collateral, xFeeBurn, yFeeBurn, false);
    }

    function _randomMintFees(
        address collateral,
        uint64[10] memory xFeeMintUnbounded,
        int64[10] memory yFeeMintUnbounded
    ) internal returns (uint64[] memory xFeeMint, int64[] memory yFeeMint) {
        (xFeeMint, yFeeMint) = _generateCurves(
            xFeeMintUnbounded,
            yFeeMintUnbounded,
            true,
            true,
            _minMintFee,
            _maxMintFee
        );
        vm.prank(governor);
        transmuter.setFees(collateral, xFeeMint, yFeeMint, true);
    }
}
