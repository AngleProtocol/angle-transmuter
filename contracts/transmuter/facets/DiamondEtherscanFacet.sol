// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { LibDiamond } from "../libraries/LibDiamond.sol";
import { LibDiamondEtherscan } from "../libraries/LibDiamondEtherscan.sol";
import { AccessControlModifiers } from "./AccessControlModifiers.sol";

contract DiamondEtherscanFacet is AccessControlModifiers {
    function setDummyImplementation(address _implementation) external onlyGovernor {
        LibDiamondEtherscan.setDummyImplementation(_implementation);
    }

    function implementation() external view returns (address) {
        return LibDiamondEtherscan.dummyImplementation();
    }
}
