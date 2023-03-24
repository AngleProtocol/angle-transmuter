// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "./MinterStorage.sol";

/// @title Minter
/// @author Angle Labs, Inc.
/// @notice Minter contract that rules several minting modules for Angle Protocol stablecoins
contract Minter is IMinter, MinterStorage {
    using SafeERC20 for IERC20;

    /// @inheritdoc IMinter
    function initialize(IAccessControlManager accessControlManager_) public initializer {
        if (address(accessControlManager_) == address(0)) revert ZeroAddress();
        accessControlManager = accessControlManager_;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    // ================================== MODIFIER =================================

    /// @notice Checks whether `module` is actually a module
    modifier onlyModule(address module) {
        if (isModule[module] != 1) revert NotModule();
        _;
    }

    // =============================== VIEW FUNCTIONS ==============================

    /// @inheritdoc IMinter
    function modules() external view returns (address[] memory) {
        return moduleList;
    }

    function checkModule(address module) external view returns (bool) {
        return isModule[module] >= 1;
    }

    /// @inheritdoc IMinter
    function debt(IERC20 token) external view returns (uint256) {
        return moduleTokenData[msg.sender][token].debt;
    }

    /// @inheritdoc IMinter
    function debt(address module, IERC20 token) external view returns (uint256) {
        return moduleTokenData[module][token].debt;
    }

    /// @inheritdoc IMinter
    function currentUsage(address module, IERC20 token) external view returns (uint256) {
        return usage[module][token][block.timestamp / (1 days)];
    }

    // ========================== PERMISSIONLESS FUNCTIONS =========================

    /// @inheritdoc IMinter
    function repayDebtFor(address[] memory moduleList, IERC20[] memory tokens, uint256[] memory amounts) external {
        uint256 tokensLength = tokens.length;
        if (tokensLength != moduleList.length || tokensLength != amounts.length || tokensLength == 0)
            revert IncompatibleLengths();

        for (uint256 i; i < tokensLength; ++i) {
            // Tokens are not burned here
            tokens[i].safeTransferFrom(msg.sender, address(this), amounts[i]);
            // Keep track of the changed debt
            moduleTokenData[moduleList[i]][tokens[i]].debt -= amounts[i];
            emit DebtModified(moduleList[i], tokens[i], amounts[i], false);
        }
    }

    // =========================== ONLY MODULE FUNCTIONS ===========================

    /// @inheritdoc IMinter
    function borrow(
        IERC20[] memory tokens,
        bool[] memory isStablecoin,
        uint256[] memory amounts
    ) external onlyModule(msg.sender) {
        uint256 tokensLength = tokens.length;
        if (tokensLength != isStablecoin.length || tokensLength != amounts.length || tokensLength == 0)
            revert IncompatibleLengths();

        for (uint256 i; i < tokensLength; ++i) {
            uint256 amount = _increaseModuleTokenDebt(msg.sender, tokens[i], amounts[i]);
            if (amount > 0) {
                // Minting the token to the module if it's a stablecoin otherwise simply transferring collateral to it
                if (isStablecoin[i]) IAgToken(address(tokens[i])).mint(address(msg.sender), amount);
                else tokens[i].transfer(address(msg.sender), amount);
            }
        }
    }

    /// @inheritdoc IMinter
    function repay(
        IERC20[] memory tokens,
        bool[] memory isStablecoin,
        uint256[] memory amounts,
        address[] memory to
    ) external onlyModule(msg.sender) {
        uint256 tokensLength = tokens.length;
        if (
            tokensLength != isStablecoin.length ||
            tokensLength != amounts.length ||
            tokensLength != to.length ||
            tokensLength == 0
        ) revert IncompatibleLengths();

        for (uint256 i; i < tokensLength; ++i) {
            uint256 currentDebt = moduleTokenData[msg.sender][tokens[i]].debt;
            amounts[i] = amounts[i] > currentDebt ? currentDebt : amounts[i];
            // Burn the token from the module if it's a stablecoin or simply transfer it to this contract
            if (isStablecoin[i]) IAgToken(address(tokens[i])).burnSelf(amounts[i], address(msg.sender));
            else {
                to[i] = to[i] == address(0) ? address(this) : to[i];
                tokens[i].safeTransferFrom(address(msg.sender), to[i], amounts[i]);
            }
            // Keep track of the changed debt
            moduleTokenData[msg.sender][tokens[i]].debt = currentDebt - amounts[i];
            emit DebtModified(msg.sender, tokens[i], amounts[i], false);
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
    function remove(address module) public onlyGovernor onlyModule(module) {
        if (tokens[module].length > 0) revert SupportedTokensNotRemoved();
        // Removing the whitelisting first
        delete isModule[module];

        // Deletion from `moduleList`
        address[] memory list = moduleList;
        uint256 amoListLength = list.length;
        for (uint256 i; i < amoListLength - 1; ++i) {
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
    function transferDebt(
        address moduleFrom,
        address moduleTo,
        IERC20 token,
        uint256 amount
    ) external onlyGovernor onlyModule(moduleFrom) onlyModule(moduleTo) {
        amount = _increaseModuleTokenDebt(moduleTo, token, amount);
        moduleTokenData[moduleFrom][token].debt -= amount;
        emit DebtModified(moduleFrom, token, amount, false);
    }

    /// @inheritdoc IMinter
    function setBorrowCap(address module, IERC20 token, uint256 borrowCap) public onlyGovernor onlyModule(module) {
        if (address(token) == address(0)) revert ZeroAddress();
        ModuleTokenData storage params = moduleTokenData[module][token];
        uint256 oldBorrowCap = params.borrowCap;
        if (oldBorrowCap == borrowCap) revert InvalidParam();

        if (oldBorrowCap == 0) {
            tokens[module].push(token);
            emit RightOnTokenAdded(module, token);
        } else {
            if (params.debt > borrowCap) revert TokenDebtNotRepaid();
            if (borrowCap == 0) {
                // Deletion from `tokens[module]` array
                IERC20[] memory list = tokens[module];
                uint256 moduleTokensLength = list.length;
                for (uint256 i; i < moduleTokensLength - 1; ++i) {
                    if (list[i] == token) {
                        tokens[module][i] = tokens[module][moduleTokensLength - 1];
                        break;
                    }
                }
                tokens[module].pop();
                emit RightOnTokenRemoved(module, token);
            }
        }
        params.borrowCap = borrowCap;
        emit BorrowCapUpdated(module, token, borrowCap);
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

    /// @inheritdoc IMinter
    function setDailyBorrowCap(
        address module,
        IERC20 token,
        uint256 dailyBorrowCap
    ) external onlyGuardian onlyModule(module) {
        moduleTokenData[module][token].dailyBorrowCap = dailyBorrowCap;
        emit DailyBorrowCapUpdated(module, token, dailyBorrowCap);
    }

    // ============================= INTERNAL FUNCTION =============================

    /// @notice Increases the debt of `module` for `token` by `amount` after performing all the necessary checks on
    /// the amount with respect to the caps
    function _increaseModuleTokenDebt(address module, IERC20 token, uint256 amount) internal returns (uint256) {
        ModuleTokenData memory params = moduleTokenData[module][token];
        if (params.debt + amount > params.borrowCap) {
            amount = params.borrowCap > params.debt ? params.borrowCap - params.debt : 0;
        }
        uint256 day = block.timestamp / (1 days);
        uint256 dailyUsage = usage[module][token][day];
        if (dailyUsage + amount > params.dailyBorrowCap) {
            amount = params.dailyBorrowCap > dailyUsage ? params.dailyBorrowCap - dailyUsage : 0;
        }
        moduleTokenData[module][token].debt = params.debt + amount;
        usage[module][token][day] = dailyUsage + amount;
        emit DebtModified(module, token, amount, true);
        return amount;
    }
}
