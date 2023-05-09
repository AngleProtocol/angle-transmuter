// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import "../Storage.sol";
import { Diamond } from "./Diamond.sol";
import { LibStorage as s } from "./LibStorage.sol";

library LibRewardHandler {
    using SafeERC20 for IERC20;

    event RewardsSoldFor(address indexed tokenObtained, uint256 balanceUpdate);

    function sellRewards(uint256 minAmountOut, bytes memory payload) internal returns (uint256 amountOut) {
        KheopsStorage storage ks = s.kheopsStorage();
        if (!Diamond.isGovernor(msg.sender) && ks.isSellerTrusted[msg.sender] == 0) revert NotTrusted();

        address[] memory list = ks.collateralList;
        uint256 listLength = list.length;
        uint256[] memory balances = new uint256[](listLength);
        for (uint256 i; i < listLength; ++i) {
            balances[i] = IERC20(list[i]).balanceOf(address(this));
        }
        //solhint-disable-next-line
        (bool success, bytes memory result) = ONE_INCH_ROUTER.call(payload);
        if (!success) revertBytes(result);
        amountOut = abi.decode(result, (uint256));
        if (amountOut < minAmountOut) revert TooSmallAmountOut();
        bool hasIncreased;
        for (uint256 i; i < listLength; ++i) {
            uint256 newBalance = IERC20(list[i]).balanceOf(address(this));
            if (newBalance < balances[i]) revert InvalidSwap();
            else if (newBalance > balances[i]) {
                hasIncreased = true;
                emit RewardsSoldFor(list[i], newBalance - balances[i]);
            }
        }
        if (!hasIncreased) revert InvalidSwap();
    }

    /// @notice Processes 1Inch revert messages
    function revertBytes(bytes memory errMsg) internal pure {
        if (errMsg.length > 0) {
            //solhint-disable-next-line
            assembly {
                revert(add(32, errMsg), mload(errMsg))
            }
        }
        revert OneInchSwapFailed();
    }
}
