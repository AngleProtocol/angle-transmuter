// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import "interfaces/external/chainlink/AggregatorV3Interface.sol";

import "../libraries/LibOracle.sol";
import { LibSetters as Setters } from "../libraries/LibSetters.sol";
import { LibStorage as s } from "../libraries/LibStorage.sol";

import "../../utils/Constants.sol";
import "../Storage.sol";

struct CollateralSetupProd {
    address token;
    bytes oracleConfig;
    uint64[] xMintFee;
    int64[] yMintFee;
    uint64[] xBurnFee;
    int64[] yBurnFee;
}

/// @dev This contract is used only once to initialize the diamond proxy.
contract Production {
    function initialize(
        IAccessControlManager _accessControlManager,
        address _agToken,
        CollateralSetupProd[] calldata collaterals,
        uint64[] memory xRedeemFee,
        int64[] memory yRedeemFee
    ) external {
        Setters.setAccessControlManager(_accessControlManager);

        TransmuterStorage storage ks = s.transmuterStorage();
        ks.normalizer = uint128(BASE_27);
        ks.agToken = IAgToken(_agToken);

        // Setup each collaterals
        for (uint256 i; i < collaterals.length; i++) {
            CollateralSetupProd calldata collateral = collaterals[i];
            Setters.addCollateral(collateral.token);
            Setters.setOracle(collateral.token, collateral.oracleConfig);
            //Mint fees
            Setters.setFees(collateral.token, collateral.xMintFee, collateral.yMintFee, true);
            Setters.togglePause(collateral.token, ActionType.Mint);
            //Burn fees
            Setters.setFees(collateral.token, collateral.xBurnFee, collateral.yBurnFee, false);
            Setters.togglePause(collateral.token, ActionType.Burn);
        }
    }
}
