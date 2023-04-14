// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title ICurveModule
/// @author Angle Labs
/// @dev This interface only contains functions of the `IModule` contracts which need to be accessible to other
/// contracts of the protocol
interface ICurveModule {
    // ========================== Restricted Functions =============================

    /// @notice Pulls the gains made by the protocol on its strategies
    function pushSurplus(address to) external;

    /// @notice Claims earned rewards by the protocol
    /// @dev In some protocols like Aave, the AMO may be earning rewards, it thus needs a function
    /// to claim it
    function claimRewards() external;

    /// @notice Changes allowance for a contract
    /// @param tokens Addresses of the tokens for which approvals should be madee
    /// @param spenders Addresses to approve
    /// @param amounts Approval amounts for each address
    function changeAllowance(
        IERC20[] calldata tokens,
        address[] calldata spenders,
        uint256[] calldata amounts
    ) external;

    /// @notice Recovers any ERC20 token
    /// @dev Can be used for instance to withdraw stkAave or Aave tokens made by the protocol
    function recoverERC20(address tokenAddress, address to, uint256 amountToRecover) external;
}
