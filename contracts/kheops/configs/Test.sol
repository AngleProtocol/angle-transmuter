// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.0;

import { Storage as s } from "../libraries/Storage.sol";
import { Setters } from "../libraries/Setters.sol";
import { Oracle } from "../libraries/Oracle.sol";
import "../../utils/Constants.sol";

import "../Storage.sol";

/// @dev This contract is used only once to initialize the diamond proxy.
contract Test {
    function initialize(
        IAccessControlManager _accessControlManager,
        address _agToken,
        address collateral,
        address oracle
    ) external {
        Setters.setAccessControlManager(_accessControlManager);

        KheopsStorage storage ks = s.kheopsStorage();
        ks.accumulator = BASE_27;
        ks.agToken = IAgToken(_agToken);

        Setters.addCollateral(collateral);
        Oracle.setOracle(collateral, OracleType.CHAINLINK_SIMPLE, abi.encode(1 hours, oracle));
    }
}
