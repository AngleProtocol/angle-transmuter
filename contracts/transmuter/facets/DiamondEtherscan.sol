// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { IDiamondEtherscan } from "interfaces/IDiamondEtherscan.sol";

import { LibDiamondEtherscan } from "../libraries/LibDiamondEtherscan.sol";
import { AccessControlModifiers } from "./AccessControlModifiers.sol";

/// @title DiamondEtherscan
/// @author Forked from:
/// https://github.com/zdenham/diamond-etherscan/blob/main/contracts/libraries/LibDiamondEtherscan.sol
contract DiamondEtherscan is IDiamondEtherscan, AccessControlModifiers {
    /// @inheritdoc IDiamondEtherscan
    function setDummyImplementation(address _implementation) external onlyGuardian {
        LibDiamondEtherscan.setDummyImplementation(_implementation);
    }

    /// @inheritdoc IDiamondEtherscan
    function implementation() external view returns (address) {
        return LibDiamondEtherscan.dummyImplementation();
    }
}
