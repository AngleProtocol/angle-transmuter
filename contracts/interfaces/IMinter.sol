// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IAccessControlManager.sol";

/// @title notice
/// @author Angle Labs
/// @notice Interface for the `Minter` contracts
/// @dev This interface only contains functions of the `Minter` contract which need to be accessible
/// by other contracts of the protocol
interface IMinter {
    /// @notice Initializes the `accessControlManager` contract and the access control
    /// @param accessControlManager_ Address of the associated `AccessControlManager` contract needed for checks on roles
    function initialize(IAccessControlManager accessControlManager_) external;

    // =============================== VIEW FUNCTIONS ==============================

    /// @notice Returns the list of all AMOs supported by this contract
    function modules() external view returns (address[] memory);

    /// @notice View function returning current token debt for the `msg.sender`
    /// @dev Only modules are expected to call this function
    function debt(IERC20 token) external view returns (uint256);

    /// @notice View function returning current token debt for a module
    function debt(address module, IERC20 token) external view returns (uint256);

    /// @notice Checks whether an address is approved for `msg.sender` where `msg.sender`
    /// is expected to be a module
    function isTrusted(address admin) external view returns (bool);

    // ========================== PERMISSIONLESS FUNCTIONS =========================

    /// @notice Lets someone reimburse the debt of an AMO on behalf of this AMO
    /// @param tokens Addresses of tokens for which debt should be reduced
    /// @param amounts Amounts of debt reduction to perform
    /// @dev Caller should have approved the `Minter` contract and have enough tokens in balance
    /// @dev We typically expect this function to be called by governance to balance gains and losses
    /// between AMOs
    function repayDebtFor(address[] memory moduleList, IERC20[] memory tokens, uint256[] memory amounts) external;

    // =========================== ONLY MODULE FUNCTIONS ===========================

    /// @notice Borrow tokens from the minter to invest them
    /// @param tokens Addresses of tokens we want to mint/transfer to the AMO
    /// @param isStablecoin Boolean array giving the info whether we should mint or transfer the tokens
    /// @param amounts Amounts of tokens to be minted/transferred to the AMO
    /// @dev Only a module can call this function
    /// @dev This function will mint if it is called for an agToken
    function borrow(IERC20[] memory tokens, bool[] memory isStablecoin, uint256[] memory amounts) external;

    /// @notice Repay a debt to the minter
    /// @param tokens Addresses of each tokens we want to burn/transfer from the AMO
    /// @param isStablecoin Boolean array giving the info on whether we should burn or transfer the tokens
    /// @param amounts Amounts of each tokens we want to burn/transfer from the amo
    function repay(
        IERC20[] memory tokens,
        bool[] memory isStablecoin,
        uint256[] memory amounts,
        address[] memory to
    ) external;

    // ============================= GOVERNOR FUNCTIONS ============================

    /// @notice Adds a module
    function add(address module) external;

    /// @notice Removes a module
    /// @dev To be successfully removed the address should no longer be associated to a token
    function remove(address module) external;

    /// @notice Sets the borrow cap for a `token` and `module`
    function setBorrowCap(address module, IERC20 token, uint256 borrowCap) external;

    /// @notice Changes the Minter contract and propagates this change to all underlying modules
    /// @param minter Address of the new `Minter` contract
    function setMinter(address minter) external;

    /// @notice Sets a new `accessControlManager` contract
    /// @dev This function should typically be called on all treasury contracts after the `setCore`
    /// function has been called on the `AccessControlManager` contract
    /// @dev One sanity check that can be performed here is to verify whether at least the governor
    /// calling the contract is still a governor in the new core
    function setAccessControlManager(IAccessControlManager _accessControlManager) external;

    /// @notice Recovers any ERC20 token
    /// @dev Can be used to withdraw bridge tokens for them to be de-bridged on mainnet
    function recoverERC20(address tokenAddress, address to, uint256 amountToRecover) external;
}
