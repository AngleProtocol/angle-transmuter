// SPDX-License-Identifier: GPL-3.0

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IAccessControlManager.sol";
import "../interfaces/IKheops.sol";

import "../utils/AccessControl.sol";
import { Constants as c } from "../utils/Constants.sol";
import "../utils/Errors.sol";

pragma solidity ^0.8.17;

contract RewardHandler is AccessControl {
    using SafeERC20 for IERC20;
    IERC20[] public protectedTokens;

    IKheops public kheops;

    mapping(address => uint256) public isTrusted;

    event Recovered(address tokenAddress, address to, uint256 amountToRecover);
    event TrustedToggled(address indexed who, bool trusted);

    /// @notice Checks whether the `msg.sender` is trusted
    modifier onlyTrusted() {
        if (isTrusted[msg.sender] != 1 || accessControlManager.isGovernorOrGuardian(msg.sender)) revert NotTrusted();
        _;
    }

    constructor(address _accessControlManager, address[] memory _protectedTokens, address _kheops) {
        if (_accessControlManager == address(0) || _kheops == address(0)) revert ZeroAddress();
        kheops = IKheops(_kheops);
        accessControlManager = IAccessControlManager(_accessControlManager);
        uint256 protectedTokensLength = _protectedTokens.length;
        for (uint256 i; i < protectedTokensLength; ++i) {
            if (_protectedTokens[i] == address(0)) revert ZeroAddress();
            protectedTokens.push(IERC20(_protectedTokens[i]));
        }
    }

    function toggleTrusted(address trusted) external onlyGovernor {
        if (trusted == address(0)) revert ZeroAddress();
        uint256 newValue = 1 - isTrusted[trusted];
        isTrusted[trusted] = newValue;
        emit TrustedToggled(trusted, newValue == 1);
    }

    function addProtectedToken(address protectedToken) external onlyGovernor {
        // Safety interface check
        IERC20(protectedToken).balanceOf(address(this));
        protectedTokens.push(IERC20(protectedToken));
    }

    function removeProtectedToken(address protectedToken) external onlyGovernor {
        IERC20[] memory list = protectedTokens;
        uint256 listLength = list.length;
        for (uint256 i; i < listLength - 1; ++i) {
            if (list[i] == IERC20(protectedToken)) {
                protectedTokens[i] = protectedTokens[listLength - 1];
                break;
            }
        }
        protectedTokens.pop();
    }

    function sellRewards(
        uint256 minAmountOut,
        bytes memory payload,
        address tokenToRecover,
        address to,
        uint256 amount
    ) external onlyTrusted {
        IERC20[] memory list = protectedTokens;
        uint256 listLength = list.length;
        uint256[] memory balances = new uint256[](listLength);
        for (uint256 i; i < listLength; ++i) {
            balances[i] = list[i].balanceOf(address(this));
        }
        //solhint-disable-next-line
        (bool success, bytes memory result) = ONE_INCH_ROUTER.call(payload);
        if (!success) _revertBytes(result);
        uint256 amountOut = abi.decode(result, (uint256));
        if (amountOut < minAmountOut) revert TooSmallAmountOut();
        bool hasIncreased;
        for (uint256 i; i < listLength; ++i) {
            uint256 newBalance = list[i].balanceOf(address(this));
            if (newBalance < balances[i]) revert InvalidSwap();
            else if (newBalance > balances[i]) hasIncreased = true;
        }
        if (!hasIncreased) revert InvalidSwap();
        _recover(tokenToRecover, to, amount);
    }

    /// @dev This function is `onlyTrusted` rather than `onlyGovernor` because rewards selling already
    /// happens through an `onlyTrusted` function
    function recoverERC20(address[] memory tokens, address[] memory to, uint256[] memory amounts) external onlyTrusted {
        uint256 tokensLength = tokens.length;
        if (tokensLength != to.length || tokensLength != amounts.length || tokensLength == 0)
            revert IncompatibleLengths();
        for (uint256 i; i < tokensLength; ++i) {
            _recover(tokens[i], to[i], amounts[i]);
        }
    }

    function _recover(address token, address toAddress, uint256 amount) internal {
        IKheops _kheops = kheops;
        if (toAddress != address(_kheops) || !_kheops.isModule(toAddress)) revert InvalidToAddress();
        IERC20(token).safeTransfer(toAddress, amount);
        emit Recovered(token, toAddress, amount);
    }

    /// @notice Processes 1Inch revert messages
    function _revertBytes(bytes memory errMsg) internal pure {
        if (errMsg.length > 0) {
            //solhint-disable-next-line
            assembly {
                revert(add(32, errMsg), mload(errMsg))
            }
        }
        revert OneInchSwapFailed();
    }
}
