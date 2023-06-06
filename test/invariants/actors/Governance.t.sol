// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import "contracts/utils/Constants.sol";
import { BaseActor, ITransmuter, AggregatorV3Interface, IERC20, IERC20Metadata } from "./BaseActor.t.sol";
import { MockChainlinkOracle } from "mock/MockChainlinkOracle.sol";
import "../../utils/FunctionUtils.sol";

import { console } from "forge-std/console.sol";

contract Governance is BaseActor, FunctionUtils {
    constructor(
        ITransmuter transmuter,
        address[] memory collaterals,
        AggregatorV3Interface[] memory oracles
    ) BaseActor(1, "Trader", transmuter, collaterals, oracles) {}

    // Random oracle change of at most 1%
    function updateOracle(uint256 collatNumber, int256 change) public useActor(0) countCall("oracle") {
        collatNumber = bound(collatNumber, 0, 2);
        change = bound(change, int256((99 * BASE_18) / 100), int256((101 * BASE_18) / 100)); // +/- 1%

        (, int256 answer, , , ) = _oracles[collatNumber].latestRoundData();
        answer = (answer * change) / int256(BASE_18);
        MockChainlinkOracle(address(_oracles[collatNumber])).setLatestAnswer(answer);
    }

    function updateRedemptionFees(
        uint64[10] memory xFee,
        int64[10] memory yFee
    ) public useActor(0) countCall("feeRedeem") {
        (uint64[] memory xFeeRedeem, int64[] memory yFeeRedeem) = _generateCurves(
            xFee,
            yFee,
            true,
            false,
            0,
            int256(BASE_9)
        );
        _transmuter.setRedemptionCurveParams(xFeeRedeem, yFeeRedeem);
    }

    function updateBurnFees(
        uint256 collatNumber,
        uint64[10] memory xFee,
        int64[10] memory yFee
    ) public useActor(0) countCall("feeBurn") {
        collatNumber = bound(collatNumber, 0, 2);

        int256 minBurnFee = int256(BASE_9);
        for (uint256 i; i < _collaterals.length; i++) {
            (, int64[] memory yFeeMint) = _transmuter.getCollateralMintFees(_collaterals[i]);
            if (yFeeMint[0] < minBurnFee) minBurnFee = yFeeMint[0];
        }
        (uint64[] memory xFeeBurn, int64[] memory yFeeBurn) = _generateCurves(
            xFee,
            yFee,
            true,
            true,
            -minBurnFee,
            int256(MAX_BURN_FEE)
        );
        _transmuter.setFees(_collaterals[collatNumber], xFeeBurn, yFeeBurn, true);
    }

    function updateMintFees(
        uint256 collatNumber,
        uint64[10] memory xFee,
        int64[10] memory yFee
    ) public useActor(0) countCall("feeMint") {
        collatNumber = bound(collatNumber, 0, 2);
        int256 minMintFee = int256(BASE_9);
        for (uint256 i; i < _collaterals.length; i++) {
            (, int64[] memory yFeeBurn) = _transmuter.getCollateralBurnFees(_collaterals[i]);
            if (yFeeBurn[0] < minMintFee) minMintFee = yFeeBurn[0];
        }
        (uint64[] memory xFeeMint, int64[] memory yFeeMint) = _generateCurves(
            xFee,
            yFee,
            true,
            true,
            -minMintFee,
            int256(BASE_12)
        );
        _transmuter.setFees(_collaterals[collatNumber], xFeeMint, yFeeMint, true);
    }
}
