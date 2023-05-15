// SPDX-License-Identifier: BUSL-1.1

pragma solidity >=0.5.0;

import { IDiamondCut } from "./IDiamondCut.sol";
import { IDiamondLoupe } from "./IDiamondLoupe.sol";
import { IGetters } from "./IGetters.sol";
import { IRedeemer } from "./IRedeemer.sol";
import { IRewardHandler } from "./IRewardHandler.sol";
import { ISetters } from "./ISetters.sol";
import { ISwapper } from "./ISwapper.sol";

/// @title IKheops
/// @author Angle Labs, Inc.
interface IKheops is IDiamondCut, IDiamondLoupe, IGetters, IRedeemer, IRewardHandler, ISetters, ISwapper {

}
