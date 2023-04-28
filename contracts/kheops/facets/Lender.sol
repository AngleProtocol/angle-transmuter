// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.12;

import { Storage as s } from "../libraries/Storage.sol";
import { AccessControl } from "../utils/AccessControl.sol";
import { Diamond } from "../libraries/Diamond.sol";
import "../libraries/LibRedeemer.sol";
import "../../utils/Constants.sol";
import "../../utils/Errors.sol";

import "../../interfaces/IAccessControlManager.sol";
import "../Storage.sol";

contract Lender is AccessControl {
    function borrow(uint256 amount) external returns (uint256) {
        KheopsStorage storage ks = s.kheopsStorage();
        Module storage module = ks.modules[msg.sender];
        if (module.unpaused == 0) revert NotModule();
        // Getting borrowing power from the module
        uint256 _normalizedStables = ks.normalizedStables;
        uint256 _normalizer = ks.normalizer;
        uint256 borrowingPower;
        if (module.normalizedStables * BASE_9 < module.maxExposure * _normalizedStables) {
            if (module.redeemable > 0) {
                borrowingPower =
                    ((module.maxExposure * _normalizedStables - module.normalizedStables * BASE_9) * _normalizer) /
                    ((BASE_9 - module.maxExposure) * BASE_27);
            } else
                borrowingPower =
                    (((module.maxExposure * _normalizedStables) / BASE_9 - module.normalizedStables) * _normalizer) /
                    BASE_27;
        }
        amount = amount > borrowingPower ? borrowingPower : amount;
        uint256 amountCorrected = (amount * BASE_27) / _normalizer;
        module.normalizedStables += amountCorrected;
        ks.normalizedStables += amountCorrected;
        IAgToken(ks.agToken).mint(msg.sender, amount);
        return amount;
    }

    function repay(uint256 amount) external {
        // TODO need to do something such that when the amount reported is greater than the reserves
        KheopsStorage storage ks = s.kheopsStorage();
        Module storage module = ks.modules[msg.sender];
        if (module.initialized == 0) revert NotModule();
        uint256 normalizer = ks.normalizer;
        uint256 amountCorrected = (amount * BASE_27) / normalizer;
        uint256 currentR = module.normalizedStables;
        IAgToken(ks.agToken).burnSelf(amount, msg.sender);
        if (amountCorrected > currentR) {
            module.normalizedStables = 0;
            ks.normalizedStables -= currentR;
            // Potential rounding issue
            LibRedeemer.updateNormalizer(amount - (currentR * normalizer) / BASE_27, false);
        } else {
            module.normalizedStables -= amountCorrected;
            ks.normalizedStables -= amountCorrected;
        }
    }

    /// @dev amount is an absolute amount (like not normalized) -> need to pay attention to this
    /// Why not normalising directly here? easier for Governance
    function adjustReserve(address collateral, uint256 amount, bool addOrRemove) external onlyGovernor {
        KheopsStorage storage ks = s.kheopsStorage();
        Collateral storage collatInfo = ks.collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        if (addOrRemove) {
            collatInfo.normalizedStables += amount;
            ks.normalizedStables += amount;
        } else {
            collatInfo.normalizedStables -= amount;
            ks.normalizedStables -= amount;
        }
    }
}
