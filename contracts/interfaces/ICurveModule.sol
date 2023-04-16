// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IModule
/// @author Angle Labs
/// @dev This interface only contains functions of the `IModule` contracts which need to be accessible to other
/// contracts of the protocol
interface ICurveModule {
    /// @notice Initializes the contract with proper access control
    function initialize(address accessControlManager_, address minter_, address agToken_, address basePool_) external;

    // ================================ Views ======================================

    /// @notice Helper function to access the current net balance for a particular token
    /// @return Actualised value owned by the contract
    function balance() external view returns (uint256);

    /// @notice Helper function to access the current debt owed to the AMOMinter
    function debt() external view returns (uint256);

    /// @notice Gets the current value in `agToken` of the assets managed by the AMO corresponding to `agToken`,
    /// excluding the loose balance of `agToken`
    function getNavOfInvestedAssets() external view returns (uint256);

    // ========================== Restricted Functions =============================

    /// @notice Pulls the gains made by the protocol on its strategies
    /// @param token Address of the token to getch gain for
    /// @param to Address to which tokens should be sent
    /// @dev This function cannot transfer more than the gains made by the protocol
    function pushSurplus(IERC20 token, address to) external;

    /// @notice Claims earned rewards by the protocol
    /// @dev In some protocols like Aave, the AMO may be earning rewards, it thus needs a function
    /// to claim it
    function claimRewards() external;

    /// @notice Swaps earned tokens through `1Inch`
    /// @param minAmountOut Minimum amount of `want` to receive for the swap to happen
    /// @param payload Bytes needed for 1Inch API
    /// @dev This function can for instance be used to sell the stkAAVE rewards accumulated by an AMO
    function sellRewards(uint256 minAmountOut, bytes memory payload) external;

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

    // ========================== Only AMOMinter Functions =========================

    /// @notice Changes the reference to the `Minter` contract
    /// @param minter_ Address of the new `Minter`
    /// @dev All checks are performed in the parent contract
    function setMinter(address minter_) external;

    /// @notice Lets the AMO contract acknowledge support for a new token
    /// @param token Token to add support for
    function setToken(IERC20 token) external;

    /// @notice Changes the fact that `trusted` is allowed to operate `module`
    /// @dev Changed via the `Minter`
    function toggleTrusted(address trusted) external;

    /// @notice Removes support for a token
    /// @param token Token to remove support for
    function removeToken(IERC20 token) external;
}
