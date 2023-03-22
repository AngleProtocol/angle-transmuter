// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "./MinterStorage.sol";

/// @title Minter
/// @author Angle Labs
/// @dev Inspired from https://github.com/FraxFinance/frax-solidity/blob/master/src/hardhat/contracts/Frax/FraxAMOMinter.sol
contract Minter is IMinter, MinterStorage {
    using SafeERC20 for IERC20;

    /// @inheritdoc IMinter
    function initialize(IAccessControlManager accessControlManager_) public initializer {
        if (address(accessControlManager_) == address(0)) revert ZeroAddress();
        accessControlManager = accessControlManager_;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    // =============================== VIEW FUNCTIONS ==============================

    /// @inheritdoc IMinter
    function modules() external view returns (address[] memory) {
        return moduleList;
    }

    /// @inheritdoc IMinter
    function debt(IERC20 token) external view returns (uint256) {
        return debts[msg.sender][token];
    }

    /// @inheritdoc IMinter
    function debt(address module, IERC20 token) external view returns (uint256) {
        return debts[module][token];
    }

    /// @inheritdoc IMinter
    function isTrusted(address admin) external view returns (bool) {
        return isTrustedForModule[msg.sender][admin] == 1 || accessControlManager.isGovernorOrGuardian(msg.sender);
    }

    // ========================== PERMISSIONLESS FUNCTIONS =========================

    /// @inheritdoc IMinter
    function repayDebtFor(address[] memory moduleList, IERC20[] memory tokens, uint256[] memory amounts) external {
        if (tokens.length != moduleList.length || tokens.length != amounts.length || tokens.length == 0)
            revert IncompatibleLengths();

        for (uint256 i = 0; i < tokens.length; i++) {
            // @dev tokens are not burned here
            tokens[i].safeTransferFrom(msg.sender, address(this), amounts[i]);
            // Keep track of the changed debt
            debts[moduleList[i]][tokens[i]] -= amounts[i];
        }
    }

    // =========================== ONLY MODULE FUNCTIONS ===========================

    /// @inheritdoc IMinter
    function borrow(IERC20[] memory tokens, bool[] memory isStablecoin, uint256[] memory amounts) external {
        if (isModule[msg.sender] != 1) revert NotTrusted();
        if (tokens.length != isStablecoin.length || tokens.length != amounts.length || tokens.length == 0)
            revert IncompatibleLengths();

        for (uint256 i = 0; i < tokens.length; i++) {
            // Keeping track of the changed debt and making sure you aren't lending more than the borrow cap
            if (debts[msg.sender][tokens[i]] + amounts[i] > borrowCaps[msg.sender][tokens[i]])
                revert BorrowCapReached();
            debts[msg.sender][tokens[i]] += amounts[i];
            // Minting the token to the module or simply transferring collateral to it
            if (isStablecoin[i]) IAgToken(address(tokens[i])).mint(address(msg.sender), amounts[i]);
            else tokens[i].transfer(address(msg.sender), amounts[i]);
        }
    }

    /// @inheritdoc IMinter
    function repay(
        IERC20[] memory tokens,
        bool[] memory isStablecoin,
        uint256[] memory amounts,
        address[] memory to
    ) external {
        if (isModule[msg.sender] != 1) revert NotTrusted();
        if (
            tokens.length != isStablecoin.length ||
            tokens.length != amounts.length ||
            tokens.length != to.length ||
            tokens.length == 0
        ) revert IncompatibleLengths();

        for (uint256 i = 0; i < tokens.length; i++) {
            // Burn the agToken from the AMO or simply transfer it to this address
            if (isStablecoin[i])
                IAgToken(address(tokens[i])).burnSelf(amounts[i], address(msg.sender));
                // Transfer the collateral to the AMO
            else tokens[i].safeTransferFrom(address(msg.sender), to[i], amounts[i]);
            // Keep track of the changed debt
            debts[msg.sender][tokens[i]] -= amounts[i];
        }
    }

    // ============================= GOVERNOR FUNCTIONS ============================

    /// @inheritdoc IMinter
    function add(address module) public onlyGovernor {
        if (address(module) == address(0)) revert ZeroAddress();
        if (isModule[module] == 1) revert AlreadyAdded();
        isModule[module] = 1;
        moduleList.push(module);
        emit ModuleAdded(module);
    }

    /// @inheritdoc IMinter
    function remove(address module) public onlyGovernor {
        if (address(module) == address(0)) revert ZeroAddress();
        if (isModule[module] != 1) revert NonExistent();
        if (tokens[module].length > 0) revert SupportedTokensNotRemoved();
        // Removing the whitelisting first
        delete isModule[module];

        // Deletion from `moduleList`
        address[] memory list = moduleList;
        uint256 amoListLength = list.length;
        for (uint256 i = 0; i < amoListLength - 1; i++) {
            if (list[i] == module) {
                // Replace the `amo` to remove with the last of the list
                moduleList[i] = moduleList[amoListLength - 1];
                break;
            }
        }
        // Remove last element in array
        moduleList.pop();

        emit ModuleRemoved(module);
    }

    /// @inheritdoc IMinter
    function setBorrowCap(address module, IERC20 token, uint256 borrowCap) public onlyGovernor {
        if (address(token) == address(0) || module == address(0)) revert ZeroAddress();

        uint256 oldBorrowCap = borrowCaps[module][token];
        if (oldBorrowCap == borrowCap) revert InvalidParam();

        if (borrowCaps[module][token] == 0) {
            if (isModule[module] != 1) add(module);
            tokens[module].push(token);
            borrowCaps[module][token] = borrowCap;
            ICurveModule(module).setToken(token);
            emit RightOnTokenAdded(module, token);
        } else {
            if (debts[module][token] > borrowCap) revert TokenDebtNotRepaid();
            if (borrowCap == 0) {
                // Resetting borrow cap
                delete borrowCaps[module][token];

                // Deletion from `amoTokens[amo]` loop
                IERC20[] memory list = tokens[module];
                uint256 amoTokensLength = list.length;
                for (uint256 i = 0; i < amoTokensLength - 1; i++) {
                    if (list[i] == token) {
                        // Replace the `amo` to remove with the last of the list
                        tokens[module][i] = tokens[module][amoTokensLength - 1];
                        break;
                    }
                }
                // Removing the last element in an array
                tokens[module].pop();
                ICurveModule(module).removeToken(token);

                emit RightOnTokenRemoved(module, token);
            } else {
                borrowCaps[module][token] = borrowCap;
            }
        }
        emit BorrowCapUpdated(module, token, borrowCap);
    }

    /// @inheritdoc IMinter
    function setMinter(address minter) external onlyGovernor {
        if (minter == address(0)) revert ZeroAddress();
        address[] memory list = moduleList;
        uint256 length = list.length;
        for (uint256 i = 0; i < length; i++) {
            ICurveModule(list[i]).setMinter(minter);
        }
        emit MinterUpdated(minter);
    }

    /// @inheritdoc IMinter
    function setAccessControlManager(IAccessControlManager _accessControlManager) external onlyGovernor {
        if (!_accessControlManager.isGovernor(msg.sender)) revert NotGovernor();
        accessControlManager = IAccessControlManager(_accessControlManager);
        emit AccessControlManagerUpdated(_accessControlManager);
    }

    /// @inheritdoc IMinter
    function recoverERC20(address tokenAddress, address to, uint256 amountToRecover) external onlyGovernor {
        IERC20(tokenAddress).safeTransfer(to, amountToRecover);
        emit Recovered(tokenAddress, to, amountToRecover);
    }
}
