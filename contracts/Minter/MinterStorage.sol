// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/IAgToken.sol";
import "../interfaces/IMinter.sol";

import "../utils/AccessControl.sol";

/// @title MinterStorage
/// @author Angle Labs, Inc.
/// @notice Parameters, variables and events for the `Minter` contract
contract MinterStorage is Initializable, AccessControl {
    using SafeERC20 for IERC20;

    struct ModuleTokenData {
        // Amount of token owed to the minted
        uint256 debt;
        // Max amount of `token` borrowable by the module
        uint256 borrowCap;
        // Max amount that can be borrowed in a day
        // It's technically possible to borrow 2x `dailyBorrowCap` in 24 hours by borrowing before
        // the end of a day and right after the start of a new day
        uint256 dailyBorrowCap;
    }

    /// @notice Array of all supported modules
    address[] public moduleList;
    /// @notice Maps an address to whether it is a module
    mapping(address => uint256) public isModule;
    /// @notice Maps each module to the list of tokens it currently supports
    mapping(address => IERC20[]) public tokens;
    /// @notice Maps `(module,token)` pairs to their associated data and parameters
    mapping(address => mapping(IERC20 => ModuleTokenData)) public moduleTokenData;
    /// @notice Maps `(module,token)` pairs to their associated daily borrow amounts
    mapping(address => mapping(IERC20 => mapping(uint256 => uint256))) public usage;

    uint256[43] private __gap;

    // =================================== EVENTS ==================================

    event AccessControlManagerUpdated(IAccessControlManager indexed _accessControlManager);
    event BorrowCapUpdated(address indexed module, IERC20 indexed token, uint256 borrowCap);
    event DailyBorrowCapUpdated(address indexed module, IERC20 indexed token, uint256 dailyBorrowCap);
    event DebtModified(address indexed module, IERC20 indexed token, uint256 amount, bool increase);
    event MinterUpdated(address indexed _minter);
    event ModuleAdded(address indexed module);
    event ModuleRemoved(address indexed module);
    event Recovered(address indexed token, address indexed to, uint256 amountToRecover);
    event RightOnTokenAdded(address indexed module, IERC20 indexed token);
    event RightOnTokenRemoved(address indexed module, IERC20 indexed token);
}
