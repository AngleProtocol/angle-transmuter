// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.12;

import { IDiamondCut } from "./IDiamondCut.sol";
import { IDiamondLoupe } from "./IDiamondLoupe.sol";
import { IGetters } from "./IGetters.sol";
import { IRedeemer } from "./IRedeemer.sol";
import { ISetters } from "./ISetters.sol";
import { ISwapper } from "./ISwapper.sol";

/// @title IKheops
/// @author Angle Labs, Inc.
interface IKheops is IDiamondCut, IDiamondLoupe, IGetters, IRedeemer, ISetters, ISwapper {

}
