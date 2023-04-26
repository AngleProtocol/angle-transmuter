// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.12;

import { IDiamondCut } from "./IDiamondCut.sol";
import { IDiamondLoupe } from "./IDiamondLoupe.sol";

interface IKheops is IDiamondCut, IDiamondLoupe {}
