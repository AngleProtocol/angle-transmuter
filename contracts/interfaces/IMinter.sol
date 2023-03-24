// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IAccessControlManager.sol";

/// @title notice
/// @author Angle Labs
/// @notice Interface for the `Minter` contract
interface IMinter {
    /// @notice Initializes the `accessControlManager` contract and the access control
    /// @param accessControlManager_ Address of the associated `AccessControlManager` contract needed for checks on roles
    function initialize(IAccessControlManager accessControlManager_) external;

    // =============================== VIEW FUNCTIONS ==============================

    /// @notice Returns whether an address is a module or no
    function checkModule(address module) external view returns (bool);

    /// @notice Returns the list of all modules supported by this contract
    function modules() external view returns (address[] memory);

    /// @notice View function returning current token debt for the `msg.sender`
    /// @dev Only modules are expected to call this function
    function debt(IERC20 token) external view returns (uint256);

    /// @notice View function returning current token debt for a module
    function debt(address module, IERC20 token) external view returns (uint256);

    /// @notice Returns the amount of `token` borrowed during the current day by `module`
    function currentUsage(address module, IERC20 token) external view returns (uint256);

    // ========================== PERMISSIONLESS FUNCTIONS =========================

    /// @notice Lets someone reimburse the debt of a module on behalf of this module
    /// @param tokens Addresses of tokens for which debt should be reduced
    /// @param amounts Amounts of debt reduction to perform
    /// @dev Caller should have approved the `Minter` contract and have enough tokens in balance
    /// @dev We typically expect this function to be called by governance to balance gains and losses
    /// between modules
    function repayDebtFor(address[] memory moduleList, IERC20[] memory tokens, uint256[] memory amounts) external;

    // =========================== ONLY MODULE FUNCTIONS ===========================

    /// @notice Borrow tokens from the minter to invest them
    /// @param tokens Addresses of tokens to mint or transfer to the module
    /// @param isStablecoin Boolean array giving the info whether tokens should be minted or transferred
    /// @param amounts Amounts of tokens to mint/transfer to the module
    function borrow(IERC20[] memory tokens, bool[] memory isStablecoin, uint256[] memory amounts) external;

    /// @notice Repay a debt to the minter
    /// @param tokens Addresses of each tokens to burn or transfer from the module
    /// @param isStablecoin Boolean array giving the info on whether tokens should be burnt or transferred
    /// @param amounts Amounts of each tokens to burn/transfer from the module
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

    /// @notice Transfers `amount` of `token` debt from `moduleFrom` to `moduleTo`
    function transferDebt(address moduleFrom, address moduleTo, IERC20 token, uint256 amount) external;

    /// @notice Sets the borrow cap for a `token` and `module`
    function setBorrowCap(address module, IERC20 token, uint256 borrowCap) external;

    /// @notice Sets a new `accessControlManager` contract
    function setAccessControlManager(IAccessControlManager _accessControlManager) external;

    /// @notice Recovers any ERC20 token
    function recoverERC20(address tokenAddress, address to, uint256 amountToRecover) external;

    /// @notice Sets the daily borrow cap for a `token` and `module`
    function setDailyBorrowCap(address module, IERC20 token, uint256 dailyBorrowCap) external;
}
