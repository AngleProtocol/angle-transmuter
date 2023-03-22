// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/IAgToken.sol";
import "../interfaces/ICurveModule.sol";
import "../interfaces/IMinter.sol";

import "../utils/AccessControl.sol";

/// @title MinterStorage
/// @author Angle Labs
/// @dev Inspired from https://github.com/FraxFinance/frax-solidity/blob/master/src/hardhat/contracts/Frax/FraxAMOMinter.sol
contract MinterStorage is Initializable, AccessControl {
    using SafeERC20 for IERC20;

    /// @notice Array of all supported contracts
    address[] public moduleList;
    /// @notice Maps an address to whether it is a module
    mapping(address => uint256) public isModule;
    /// @notice Maps a module to whether an address can call the `sendTo`/`receiveFrom` functions associated to it
    mapping(address => mapping(address => uint256)) public isTrustedForModule;
    /// @notice Maps each module to the list of tokens it currently supports
    mapping(address => IERC20[]) public tokens;
    /// @notice Max amount borrowable by each `(module,token)` pair
    mapping(address => mapping(IERC20 => uint256)) public borrowCaps;
    /// @notice module debt to the Minter for a given token
    mapping(address => mapping(IERC20 => uint256)) public debts;

    uint256[43] private __gap;

    // =================================== EVENTS ==================================

    event AccessControlManagerUpdated(IAccessControlManager indexed _accessControlManager);
    event BorrowCapUpdated(address indexed module, IERC20 indexed token, uint256 borrowCap);
    event MinterUpdated(address indexed _minter);
    event ModuleAdded(address indexed module);
    event ModuleRemoved(address indexed module);
    event Recovered(address indexed token, address indexed to, uint256 amountToRecover);
    event RightOnTokenAdded(address indexed module, IERC20 indexed token);
    event RightOnTokenRemoved(address indexed module, IERC20 indexed token);
}
