// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { LibStorage as s } from "./LibStorage.sol";

/// @title LibDiamondEtherscan
/// @notice Allow to verify a diamond proxy on Etherscan
/// @dev Forked from https://github.com/zdenham/diamond-etherscan/blob/main/contracts/libraries/LibDiamondEtherscan.sol
library LibDiamondEtherscan {
    event Upgraded(address indexed implementation);

    /// @notice Internal version of `setDummyImplementation`
    function setDummyImplementation(address implementationAddress) internal {
        s.implementationStorage().implementation = implementationAddress;
        emit Upgraded(implementationAddress);
    }

    /// @notice Internal version of `implementation`
    function dummyImplementation() internal view returns (address) {
        return s.implementationStorage().implementation;
    }
}
