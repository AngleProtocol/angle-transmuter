// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import "interfaces/external/chainlink/AggregatorV3Interface.sol";

import { LibDiamondEtherscan } from "../libraries/LibDiamondEtherscan.sol";
import "../libraries/LibOracle.sol";
import { LibSetters } from "../libraries/LibSetters.sol";
import { LibStorage as s } from "../libraries/LibStorage.sol";

import { DummyDiamondImplementation } from "../../../scripts/generated/DummyDiamondImplementation.sol";

import "../../utils/Constants.sol";
import "../Storage.sol" as Storage;

struct CollateralSetupProd {
    address token;
    bytes oracleConfig;
    uint64[] xMintFee;
    int64[] yMintFee;
    uint64[] xBurnFee;
    int64[] yBurnFee;
}
