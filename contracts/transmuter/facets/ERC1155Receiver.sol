// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { IERC1155Receiver } from "oz/contracts/token/ERC1155/IERC1155Receiver.sol";

/// @title ERC1155Receiver
/// @author Angle Labs, Inc.
contract ERC1155Receiver is IERC1155Receiver {
    /// @inheritdoc IERC1155Receiver
    /// @dev The returned value should be:
    /// `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)")) = 0xf23a6e61`
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC1155ReceiverUpgradeable.onERC1155Received.selector;
    }

    /// @inheritdoc IERC1155Receiver
    /// @dev The returned value should be:
    /// `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)")) = 0xbc197c81`
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC1155ReceiverUpgradeable.onERC1155BatchReceived.selector;
    }
}
