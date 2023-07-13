// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import { ITransmuter, Transmuter } from "../utils/Transmuter.sol";
import { IERC20 } from "oz/interfaces/IERC20.sol";
import { IERC1820Registry } from "oz/utils/introspection/IERC1820Registry.sol";

contract ReentrantRedeemGetCollateralRatio {
    bytes32 private constant _TOKENS_SENDER_INTERFACE_HASH = keccak256("ERC777TokensSender");
    bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");

    ITransmuter transmuter;
    IERC1820Registry registry;

    constructor(ITransmuter _transmuter, IERC1820Registry _registry) {
        transmuter = _transmuter;
        registry = _registry;
    }

    function testERC777Reentrancy(uint256 redeemAmount) public {
        uint256[] memory minAmountOuts;
        (, uint256[] memory quoteAmounts) = transmuter.quoteRedemptionCurve(redeemAmount);
        minAmountOuts = new uint256[](quoteAmounts.length);
        transmuter.redeem(redeemAmount, address(this), block.timestamp * 2, minAmountOuts);
    }

    function setInterfaceImplementer() public {
        // tokensReceived Hook
        // The token contract MUST call the tokensReceived hook of the recipient if the recipient registers an ERC777TokensRecipient implementation via ERC-1820.
        registry.setInterfaceImplementer(address(this), _TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
    }

    function tokensReceived(address, address from, address, uint256, bytes calldata, bytes calldata) external view {
        // reenter here
        if (from != address(0)) {
            // It should revert here
            transmuter.getCollateralRatio();
        }
    }

    receive() external payable {}
}

contract ReentrantRedeemSwap {
    bytes32 private constant _TOKENS_SENDER_INTERFACE_HASH = keccak256("ERC777TokensSender");
    bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");

    ITransmuter transmuter;
    IERC1820Registry registry;
    IERC20 agToken;
    IERC20 collateral;

    constructor(ITransmuter _transmuter, IERC1820Registry _registry, IERC20 _agToken, IERC20 _collateral) {
        transmuter = _transmuter;
        registry = _registry;
        agToken = _agToken;
        collateral = _collateral;
    }

    function testERC777Reentrancy(uint256 redeemAmount) public {
        uint256[] memory minAmountOuts;
        (, uint256[] memory quoteAmounts) = transmuter.quoteRedemptionCurve(redeemAmount);
        minAmountOuts = new uint256[](quoteAmounts.length);
        transmuter.redeem(redeemAmount, address(this), block.timestamp * 2, minAmountOuts);
    }

    function setInterfaceImplementer() public {
        // tokensReceived Hook
        // The token contract MUST call the tokensReceived hook of the recipient if the recipient registers an ERC777TokensRecipient implementation via ERC-1820.
        registry.setInterfaceImplementer(address(this), _TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
    }

    function tokensReceived(address, address from, address, uint256, bytes calldata, bytes calldata) external {
        // reenter here
        if (from != address(0)) {
            // It should revert here
            transmuter.swapExactInput(
                1e18,
                0,
                address(collateral),
                address(agToken),
                address(this),
                block.timestamp * 2
            );
        }
    }

    receive() external payable {}
}
