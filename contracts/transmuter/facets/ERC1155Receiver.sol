// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { IERC1155Receiver, IERC165 } from "oz/token/ERC1155/IERC1155Receiver.sol";

/// @title ERC1155Receiver
/// @author Angle Labs, Inc.
contract ERC1155Receiver is IERC1155Receiver {
    /// @inheritdoc IERC1155Receiver
    /// @dev The returned value should be:
    /// `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)")) = 0xf23a6e61`
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
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
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    /// @inheritdoc IERC165
    /// @dev On purpose, this function does not override all the interfaces defined for the Transmuter contract
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
