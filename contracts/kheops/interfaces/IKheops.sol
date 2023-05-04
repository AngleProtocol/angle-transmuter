// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import { IDiamondCut } from "./IDiamondCut.sol";
import { IDiamondLoupe } from "./IDiamondLoupe.sol";
import { IGetters } from "./IGetters.sol";
import { IRedeemer } from "./IRedeemer.sol";
import { ISwapper } from "./ISwapper.sol";
import { ISetters } from "./ISetters.sol";

interface IKheops is IDiamondCut, IDiamondLoupe, IGetters, IRedeemer, ISwapper, ISetters {}
