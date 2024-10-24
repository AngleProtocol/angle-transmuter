// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

import { SafeCast } from "oz/utils/math/SafeCast.sol";
import { IERC20 } from "oz/token/ERC20/IERC20.sol";
import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";

import { ITransmuter } from "interfaces/ITransmuter.sol";
import { IERC4626 } from "interfaces/external/IERC4626.sol";
import { AccessControl, IAccessControlManager } from "../utils/AccessControl.sol";

import "../utils/Constants.sol";
import "../utils/Errors.sol";

struct StableContracts {
    address transmuter;
    address savings;
}

/// @title ClearSwapper
/// @author Angle Labs, Inc.
/// @dev Helper contract for people to permissionlessly swap and deposit into Angle savings solution in one transaction
contract ClearSwapper is AccessControl {
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    mapping(address => StableContracts) public stableContracts;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    INITIALIZATION                                                  
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    constructor(address _accessControlManager) {
        accessControlManager = IAccessControlManager(_accessControlManager);
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address to,
        uint256 deadline,
        address stablecoin
    ) public returns (uint256 amountOut) {
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        StableContracts memory stableData = stableContracts[stablecoin];
        if (tokenOut == stableData.savings) {
            _changeAllowance(tokenIn, stableData.transmuter, amountIn);
            amountOut = ITransmuter(stableData.transmuter).swapExactInput(
                amountIn,
                0,
                tokenIn,
                stablecoin,
                address(this),
                deadline
            );
            _changeAllowance(stablecoin, stableData.savings, amountOut);
            amountOut = IERC4626(stableData.savings).deposit(amountOut, to);
        } else if (tokenIn == stableData.savings) {
            amountOut = IERC4626(stableData.savings).redeem(amountIn, address(this), address(this));
            amountOut = ITransmuter(stableData.transmuter).swapExactInput(
                amountOut,
                0,
                stablecoin,
                tokenOut,
                to,
                deadline
            );
        }
        if (amountOut < minAmountOut) revert TooSmallAmountOut();
    }

    function deposit(
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut,
        address to,
        uint256 deadline,
        address stablecoin
    ) external returns (uint256) {
        StableContracts memory stableData = stableContracts[stablecoin];
        return swap(tokenIn, stableData.savings, amountIn, minAmountOut, to, deadline, stablecoin);
    }

    function redeem(
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address to,
        uint256 deadline,
        address stablecoin
    ) external returns (uint256) {
        StableContracts memory stableData = stableContracts[stablecoin];
        return swap(stableData.savings, tokenOut, amountIn, minAmountOut, to, deadline, stablecoin);
    }

    function withdraw(
        address tokenOut,
        uint256 amountOut,
        uint256 maxAmountIn,
        address to,
        uint256 deadline,
        address stablecoin
    ) external returns (uint256) {
        StableContracts memory stableData = stableContracts[stablecoin];
        return swapExactOutput(stableData.savings, tokenOut, amountOut, maxAmountIn, to, deadline, stablecoin);
    }

    function mint(
        address tokenIn,
        uint256 amountOut,
        uint256 maxAmountIn,
        address to,
        uint256 deadline,
        address stablecoin
    ) external returns (uint256) {
        StableContracts memory stableData = stableContracts[stablecoin];
        return swapExactOutput(tokenIn, stableData.savings, amountOut, maxAmountIn, to, deadline, stablecoin);
    }

    function swapExactOutput(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 maxAmountIn,
        address to,
        uint256 deadline,
        address stablecoin
    ) public returns (uint256 amountIn) {
        amountIn = quoteOut(tokenIn, tokenOut, amountOut, stablecoin);
        if (amountIn > maxAmountIn) revert TooBigAmountIn();
        swap(tokenIn, tokenOut, amountIn, amountOut, to, deadline, stablecoin);
    }

    function quoteIn(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address stablecoin
    ) external view returns (uint256 amountOut) {
        StableContracts memory stableData = stableContracts[stablecoin];
        if (tokenOut == stableData.savings) {
            amountOut = ITransmuter(stableData.transmuter).quoteIn(amountIn, tokenIn, stablecoin);
            amountOut = IERC4626(stableData.savings).previewDeposit(amountOut);
        } else if (tokenIn == stableData.savings) {
            amountOut = IERC4626(stableData.savings).previewRedeem(amountIn);
            amountOut = ITransmuter(stableData.transmuter).quoteIn(amountOut, stablecoin, tokenOut);
        }
    }

    function quoteOut(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        address stablecoin
    ) external view returns (uint256 amountIn) {
        StableContracts memory stableData = stableContracts[stablecoin];
        if (tokenOut == stableData.savings) {
            amountIn = IERC4626(stableData.savings).previewMint(amountOut);
            amountIn = ITransmuter(stableData.transmuter).quoteOut(amountIn, tokenIn, stablecoin);
        } else if (tokenIn == stableData.savings) {
            amountIn = ITransmuter(stableData.transmuter).quoteOut(amountOut, stablecoin, tokenOut);
            amountIn = IERC4626(stableData.savings).previewWithdraw(amountIn);
        }
    }

    function previewDeposit(address tokenIn, uint256 amountIn, address stablecoin) external view returns (uint256) {
        StableContracts memory stableData = stableContracts[stablecoin];
        return quoteIn(tokenIn, stableData.savings, amountIn, stablecoin);
    }

    function previewWithdraw(address tokenOut, uint256 amountIn, address stablecoin) external view returns (uint256) {
        StableContracts memory stableData = stableContracts[stablecoin];
        return quoteIn(stableData.savings, tokenOut, amountIn, stablecoin);
    }

    function previewMint(address tokenIn, uint256 amountOut, address stablecoin) external view returns (uint256) {
        StableContracts memory stableData = stableContracts[stablecoin];
        return quoteOut(tokenIn, stableData.savings, amountOut, stablecoin);
    }

    function previewRedeem(address tokenOut, uint256 amountOut, address stablecoin) external view returns (uint256) {
        StableContracts memory stableData = stableContracts[stablecoin];
        return quoteOut(stableData.savings, tokenOut, amountOut, stablecoin);
    }

    function setStableContracts(address stablecoin, address transmuter, address savings) external onlyGuardian {
        StableContracts storage stableData = stableContracts[stablecoin];
        stableData.transmuter = transmuter;
        stableData.savings = savings;
    }

    function _changeAllowance(IERC20 token, address spender, uint256 amount) internal {
        uint256 currentAllowance = token.allowance(address(this), spender);
        // In case `currentAllowance < type(uint256).max / 2` and we want to increase it:
        // Do nothing (to handle tokens that need reapprovals to 0 and save gas)
        if (currentAllowance < amount && currentAllowance < type(uint256).max / 2) {
            token.safeIncreaseAllowance(spender, amount - currentAllowance);
        } else if (currentAllowance > amount) {
            token.safeDecreaseAllowance(spender, currentAllowance - amount);
        }
    }
}
