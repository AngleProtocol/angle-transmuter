// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/IAgToken.sol";
import "../interfaces/IMinter.sol";

import "../utils/AccessControl.sol";

import "./KheopsStorage.sol";

/// @title Kheops
/// @author Angle Labs, Inc.
contract Kheops is KheopsStorage {
    using SafeERC20 for IERC20;

    function swapExact(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external returns (uint amountOut) {
        return _swap(amountIn, amountOutMin, tokenIn, tokenOut, to, deadline, true);
    }

    function swapForExact(
        uint amountOut,
        uint amountInMax,
        address tokenIn,
        address tokenOut,
        address to,
        uint deadline
    ) external returns (uint amountIn) {
        return _swap(amountOut, amountInMax, tokenIn, tokenOut, to, deadline, false);
    }

    function _swap(
        uint256 amount,
        uint256 slippage,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline,
        bool exactIn
    ) internal returns (uint256 otherAmount) {
        (bool mint, Collateral memory collatInfo) = _getMintBurn(tokenIn, tokenOut);
        uint256 amountIn;
        uint256 amountOut;
        if (exactIn) {
            otherAmount = mint ? _quoteMintExact(collatInfo, amount) : _quoteBurnExact(collatInfo, amount);
            if (otherAmount < slippage) revert TooSmallAmountOut();
            (amountIn, amountOut) = (amount, otherAmount);
        } else {
            otherAmount = mint ? _quoteMintForExact(collatInfo, amount) : _quoteBurnForExact(collatInfo, amount);
            if (otherAmount > slippage) revert TooBigAmountIn();
            (amountIn, amountOut) = (otherAmount, amount);
        }
        if (block.timestamp < deadline) revert TooLate();
        if (mint) {
            address toProtocol = collatInfo.manager != address(0) ? collatInfo.manager : address(this);
            collaterals[IERC20(tokenOut)].r += amountOut;
            reserves += amountOut;
            IERC20(tokenIn).safeTransferFrom(msg.sender, toProtocol, amountIn);
            IAgToken(tokenOut).mint(to, amountOut);
        } else {
            collaterals[IERC20(tokenOut)].r -= amountOut;
            reserves -= amountOut;
            IAgToken(tokenIn).burnSelf(amountIn, msg.sender);
            if (collatInfo.manager != address(0)) {
                IManager(collatInfo.manager).pull(amountOut);
            }
            IERC20(tokenOut).safeTransfer(to, amountOut);
        }
    }

    function redeem(
        uint256 amount,
        address receiver,
        uint deadline,
        uint256[] memory minAmountOuts
    ) external returns (address[] memory tokens, uint256[] memory amounts) {}

    function redeemWithForfeit(
        uint256 amount,
        address receiver,
        uint deadline,
        uint256[] memory minAmountOuts,
        address[] memory forfeitTokens
    ) external returns (address[] memory tokens, uint256[] memory amounts) {}

    function _quoteMintExact(Collateral memory collatInfo, uint256 amountIn) internal view returns (uint256 amountOut) {
        uint256 oracleValue = _BASE_18;
        if (collatInfo.oracle != address(0)) oracleValue = IOracle(collatInfo.oracle).readMint();
        uint256 amountInCorrected;
        if (collatInfo.decimals > 18) {
            amountInCorrected = amountIn / 10 ** (collatInfo.decimals - 18);
        } else if (collatInfo.decimals < 18) {
            amountInCorrected = amountIn * 10 ** (18 - collatInfo.decimals);
        }
        // TODO adjust here if negative fees because it does not work well -> we underestimate exposure normally
        uint64 exposure = uint64((collatInfo.r * _BASE_9 + ((amountInCorrected * oracleValue) / _BASE_9) / reserves));
        int64 fees = _piecewiseLinear(exposure, collatInfo.xFeeMint, collatInfo.yFeeBurn);
        if (fees >= 0) amountOut = (oracleValue * (_BASE_9 - uint256(int256(fees))) * amountInCorrected) / _BASE_9;
        else amountOut = (oracleValue * (_BASE_9 + uint256(int256(-fees))) * amountInCorrected) / _BASE_9;
    }

    function _quoteMintForExact(
        Collateral memory collatInfo,
        uint256 amountOut
    ) internal view returns (uint256 amountIn) {
        uint256 oracleValue = _BASE_18;
        if (collatInfo.oracle != address(0)) oracleValue = IOracle(collatInfo.oracle).readMint();
        uint64 exposure = uint64(((collatInfo.r + amountOut) * _BASE_9) / reserves);
        int64 fees = _piecewiseLinear(exposure, collatInfo.xFeeMint, collatInfo.yFeeBurn);
        if (fees >= 0) amountIn = (amountOut * _BASE_27) / ((_BASE_9 - uint256(int256(fees))) * oracleValue);
        else amountIn = (amountOut * _BASE_27) / ((_BASE_9 + uint256(int256(-fees))) * oracleValue);
        if (collatInfo.decimals > 18) {
            amountIn = amountIn * 10 ** (collatInfo.decimals - 18);
        } else if (collatInfo.decimals < 18) {
            amountIn = amountIn / 10 ** (18 - collatInfo.decimals);
        }
    }

    function _getBurnOracle() internal view returns (uint256 oracleValue) {
        oracleValue = _BASE_18;
        // TODO check whether an oracleList could be smart -> with just list of addresses or stuff
        address[] memory list = collateralList;
        uint256 length = list.length;
        for (uint256 i; i < length; ++i) {
            address oracle = collaterals[IERC20(list[i])].oracle;
            if (oracle != address(0)) {
                uint256 value = IOracle(oracle).readBurn();
                if (value < oracleValue) oracleValue = value;
            }
        }
    }

    function _quoteBurnExact(Collateral memory collatInfo, uint256 amountIn) internal view returns (uint256 amountOut) {
        uint256 oracleValue = _getBurnOracle();
        uint64 exposure = uint64(((collatInfo.r - amountIn) * _BASE_9) / reserves);
        int64 fees = _piecewiseLinear(exposure, collatInfo.xFeeBurn, collatInfo.yFeeBurn);
        if (fees >= 0) amountOut = (oracleValue * (_BASE_9 - uint256(int256(fees))) * amountIn) / _BASE_9;
        else amountOut = (oracleValue * (_BASE_9 + uint256(int256(-fees))) * amountIn) / _BASE_9;
        if (collatInfo.decimals > 18) {
            amountOut = amountOut * 10 ** (collatInfo.decimals - 18);
        } else if (collatInfo.decimals < 18) {
            amountOut = amountOut / 10 ** (18 - collatInfo.decimals);
        }
    }

    function _quoteBurnForExact(
        Collateral memory collatInfo,
        uint256 amountOut
    ) internal view returns (uint256 amountIn) {
        uint256 oracleValue = _getBurnOracle();
        uint256 amountOutCorrected;
        if (collatInfo.decimals > 18) {
            amountOutCorrected = amountOut / 10 ** (collatInfo.decimals - 18);
        } else if (collatInfo.decimals < 18) {
            amountOutCorrected = amountOut * 10 ** (18 - collatInfo.decimals);
        }
        uint64 exposure = uint64((collatInfo.r * _BASE_9 - (amountOutCorrected * _BASE_27) / oracleValue) / reserves);
        int64 fees = _piecewiseLinear(exposure, collatInfo.xFeeBurn, collatInfo.yFeeBurn);
        if (fees >= 0) amountIn = (amountOut * _BASE_27) / ((_BASE_9 - uint256(int256(fees))) * oracleValue);
        else amountIn = (amountOut * _BASE_27) / ((_BASE_9 + uint256(int256(-fees))) * oracleValue);
    }

    function quoteIn(uint256 amountIn, address tokenIn, address tokenOut) external view returns (uint256) {
        (bool mint, Collateral memory collatInfo) = _getMintBurn(tokenIn, tokenOut);
        if (mint) return _quoteMintExact(collatInfo, amountIn);
        else return _quoteBurnExact(collatInfo, amountIn);
    }

    function quoteOut(uint256 amountOut, address tokenIn, address tokenOut) external view returns (uint256) {
        (bool mint, Collateral memory collatInfo) = _getMintBurn(tokenIn, tokenOut);
        if (mint) return _quoteMintForExact(collatInfo, amountOut);
        else return _quoteBurnForExact(collatInfo, amountOut);
    }

    function quoteRedemptionCurve(
        uint256 amountBurnt
    ) external view returns (address[] memory tokens, uint256[] memory amounts) {}

    function _getMintBurn(
        address tokenIn,
        address tokenOut
    ) internal view returns (bool mint, Collateral memory collatInfo) {
        address _agToken = address(agToken);
        if (tokenIn == _agToken) {
            collatInfo = collaterals[IERC20(tokenOut)];
            if (collatInfo.unpaused == 0) revert InvalidTokens();
            mint = false;
        } else if (tokenOut == _agToken) {
            collatInfo = collaterals[IERC20(tokenOut)];
            if (collatInfo.unpaused == 0) revert InvalidTokens();
            mint = true;
        } else revert InvalidTokens();
    }

    /**
     * TODO:
     * add setters
     * function to recover surplus
     * function to acknowledge surplus and do some bookkeeping at the oracle level
     * improve exposure computation when there are fees
     */
}
