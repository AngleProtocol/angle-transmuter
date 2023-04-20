// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface CurveToken is IERC20 {
    function mint(address to, uint256 value) external returns (bool);

    function burnFrom(address to, uint256 value) external returns (bool);
}

contract StableSwap is ERC20 {
    // These constants must be set prior to compiling
    uint256 private constant N_COINS = 2;

    // fixed constants
    uint256 private constant FEE_DENOMINATOR = 10 ** 10;
    uint256 private constant PRECISION = 10 ** 18; // The precision to convert to
    uint256 private constant ADMIN_FEE = 5000000000;

    uint256 private constant MAX_ADMIN_FEE = 10 * 10 ** 9;
    uint256 private constant MAX_FEE = 5 * 10 ** 9;
    uint256 private constant MAX_A = 10 ** 6;
    uint256 private constant A_PRECISION = 100;
    uint256 private constant MAX_A_CHANGE = 10;

    uint256 private constant ADMIN_ACTIONS_DELAY = 3 * 86400;
    uint256 private constant MIN_RAMP_TIME = 86400;

    address[N_COINS] public coins;
    uint256[N_COINS] public balances;
    uint256 fee;

    uint256 initial_A;
    uint256 future_A;
    uint256 initial_A_time;
    uint256 future_A_time;

    uint256[N_COINS] public rate_multipliers;

    function initialize(
        string calldata _name,
        string calldata _symbol,
        address[4] calldata _coins,
        uint256[4] calldata _rate_multipliers,
        uint256 a_,
        uint256 _fee
    ) public {
        _name;
        _symbol;
        // check if fee was already set to prevent initializing contract twice
        require(fee == 0, "Fee is already set");

        for (uint256 i = 0; i < N_COINS; i++) {
            address coin = _coins[i];
            if (coin == address(0)) {
                break;
            }
            coins[i] = coin;
            rate_multipliers[i] = _rate_multipliers[i];
        }

        uint256 __A = a_ * A_PRECISION;
        initial_A = __A;
        future_A = __A;
        fee = _fee;
    }

    constructor() ERC20("test", "test") {}

    function get_balances() public view returns (uint256[N_COINS] memory) {
        return balances;
    }

    function _A() internal view returns (uint256) {
        uint256 t1 = future_A_time;
        uint256 A1 = future_A;

        if (block.timestamp < t1) {
            uint256 A0 = initial_A;
            uint256 t0 = initial_A_time;
            if (A1 > A0) {
                return A0 + ((A1 - A0) * (block.timestamp - t0)) / (t1 - t0);
            } else {
                return A0 - ((A0 - A1) * (block.timestamp - t0)) / (t1 - t0);
            }
        } else {
            return A1;
        }
    }

    function admin_fee() public pure returns (uint256) {
        return ADMIN_FEE;
    }

    function A() public view returns (uint256) {
        return _A() / A_PRECISION;
    }

    function A_precise() public view returns (uint256) {
        return _A();
    }

    function _xp_mem(
        uint256[N_COINS] memory _rates,
        uint256[N_COINS] memory _balances
    ) internal pure returns (uint256[N_COINS] memory) {
        uint256[N_COINS] memory result;
        for (uint256 i = 0; i < N_COINS; i++) {
            result[i] = (_rates[i] * _balances[i]) / PRECISION;
        }
        return result;
    }

    function get_D(uint256[N_COINS] memory _xp, uint256 _amp) internal pure returns (uint256) {
        uint256 S = 0;
        for (uint256 i = 0; i < N_COINS; i++) {
            S += _xp[i];
        }
        if (S == 0) {
            return 0;
        }

        uint256 D = S;
        uint256 Ann = _amp * N_COINS;
        for (uint256 i = 0; i < 255; i++) {
            uint256 D_P = (((D * D) / _xp[0]) * D) / _xp[1] / (N_COINS) ** 2;
            uint256 Dprev = D;
            D =
                (((Ann * S) / A_PRECISION + D_P * N_COINS) * D) /
                (((Ann - A_PRECISION) * D) / A_PRECISION + (N_COINS + 1) * D_P);
            if (D > Dprev) {
                if (D - Dprev <= 1) {
                    return D;
                }
            } else {
                if (Dprev - D <= 1) {
                    return D;
                }
            }
        }
        return 0;
        // Convergence typically occurs in 4 rounds or less, this should be unreachable!
        // If it does happen, the pool is broken and LPs can withdraw via `remove_liquidity`
    }

    function get_D_mem(
        uint256[N_COINS] memory _rates,
        uint256[N_COINS] memory _balances,
        uint256 _amp
    ) internal pure returns (uint256) {
        uint256[N_COINS] memory xp = _xp_mem(_rates, _balances);
        return get_D(xp, _amp);
    }

    /// @notice The current virtual price of the pool LP token
    /// @dev Useful for calculating profits
    /// @return LP token virtual price normalized to 1e18
    function get_virtual_price() public view returns (uint256) {
        uint256 amp = _A();
        uint256[2] memory xp = _xp_mem(rate_multipliers, balances);
        uint256 D = get_D(xp, amp);

        // D is in the units similar to DAI (e.g. converted to precision 1e18)
        // When balanced, D = n * x_u - total virtual value of the portfolio
        return (D * PRECISION) / totalSupply();
    }

    function addLiquidity(
        uint256[N_COINS] calldata _amounts,
        uint256 _minMintAmount,
        address _receiver
    ) public returns (uint256) {
        uint256 amp = _A();
        uint256[N_COINS] storage oldBalances = balances;
        uint256[N_COINS] memory rates = rate_multipliers;

        // Initial invariant
        uint256 D0 = get_D_mem(rates, oldBalances, amp);

        uint256 totalSupply = totalSupply();
        uint256[N_COINS] memory newBalances = oldBalances;
        for (uint256 i = 0; i < N_COINS; i++) {
            uint256 amount = _amounts[i];
            if (amount > 0) {
                IERC20(coins[i]).transferFrom(msg.sender, address(this), amount);
                newBalances[i] += amount;
            } else {
                require(totalSupply != 0, "Initial deposit requires all coins");
            }
        }

        // Invariant after change
        uint256 D1 = get_D_mem(rates, newBalances, amp);
        require(D1 > D0, "Invariant check failed");

        // We need to recalculate the invariant accounting for fees
        // to calculate fair user's share
        uint256[N_COINS] memory fees;
        uint256 mintAmount = 0;
        if (totalSupply > 0) {
            // Only account for fees if we are not the first to deposit
            uint256 baseFee = (fee * N_COINS) / (4 * (N_COINS - 1));
            for (uint256 i = 0; i < N_COINS; i++) {
                uint256 idealBalance = (D1 * oldBalances[i]) / D0;
                uint256 difference = (idealBalance > newBalances[i])
                    ? idealBalance - newBalances[i]
                    : newBalances[i] - idealBalance;
                fees[i] = (baseFee * difference) / FEE_DENOMINATOR;
                balances[i] = newBalances[i] - ((fees[i] * ADMIN_FEE) / FEE_DENOMINATOR);
                newBalances[i] -= fees[i];
            }
            uint256 D2 = get_D_mem(rates, newBalances, amp);
            mintAmount = (totalSupply * (D2 - D0)) / D0;
        } else {
            balances = newBalances;
            mintAmount = D1; // Take the dust if there was any
        }

        require(mintAmount >= _minMintAmount, "Slippage screwed you");

        // Mint pool tokens
        _mint(_receiver, mintAmount);

        return mintAmount;
    }

    function get_y(uint256 i, uint256 j, uint256 x, uint256[N_COINS] memory xp) public view returns (uint256) {
        assert(i != j);
        assert(j >= 0);
        assert(j < N_COINS);
        assert(i >= 0);
        assert(i < N_COINS);

        uint256 amp = _A();
        uint256 D = get_D(xp, amp);
        uint256 S_ = 0;
        uint256 _x = 0;
        uint256 y_prev = 0;
        uint256 c = D;
        uint256 Ann = amp * N_COINS;

        for (uint256 _i = 0; _i < N_COINS; _i++) {
            if (_i == i) {
                _x = x;
            } else if (_i != j) {
                _x = xp[_i];
            } else {
                continue;
            }
            S_ += _x;
            c = (c * D) / (_x * N_COINS);
        }

        c = (c * D * A_PRECISION) / (Ann * N_COINS);
        uint256 b = S_ + (D * A_PRECISION) / Ann;
        uint256 y = D;

        for (uint256 _i = 0; _i < 255; _i++) {
            y_prev = y;
            y = (y * y + c) / (2 * y + b - D);
            if (y > y_prev) {
                if (y - y_prev <= 1) {
                    return y;
                }
            } else {
                if (y_prev - y <= 1) {
                    return y;
                }
            }
        }
        return 0;
    }

    function get_dy(uint256 i, uint256 j, uint256 dx) public view returns (uint256) {
        uint256[N_COINS] memory rates = rate_multipliers;
        uint256[N_COINS] memory xp = _xp_mem(rates, balances);

        uint256 x = xp[i] + ((dx * rates[i]) / PRECISION);
        uint256 y = get_y(i, j, x, xp);
        uint256 dy = xp[j] - y - 1;
        uint256 auxFee = (fee * dy) / FEE_DENOMINATOR;

        return ((dy - auxFee) * PRECISION) / rates[j];
    }

    function exchange(uint256 i, uint256 j, uint256 _dx, uint256 _min_dy, address _receiver) public returns (uint256) {
        uint256[N_COINS] memory rates = rate_multipliers;
        uint256[N_COINS] memory old_balances = balances;
        uint256[N_COINS] memory xp = _xp_mem(rates, old_balances);

        uint256 x = xp[i] + (_dx * rates[i]) / PRECISION;
        uint256 y = get_y(i, j, x, xp);

        uint256 dy = xp[j] - y - 1;
        uint256 dy_fee = (dy * fee) / FEE_DENOMINATOR;

        dy = ((dy - dy_fee) * PRECISION) / rates[j];
        require(dy >= _min_dy, "Exchange resulted in fewer coins than expected");

        uint256 dy_admin_fee = (dy_fee * ADMIN_FEE) / FEE_DENOMINATOR;
        dy_admin_fee = (dy_admin_fee * PRECISION) / rates[j];

        balances[i] = old_balances[i] + _dx;
        balances[j] = old_balances[j] - dy - dy_admin_fee;

        (bool success, bytes memory response) = coins[i].call(
            abi.encodeWithSelector(
                bytes4(keccak256("transferFrom(address,address,uint256)")),
                msg.sender,
                address(this),
                _dx
            )
        );
        require(success && (response.length == 0 || abi.decode(response, (bool))), "Failed to transfer tokens");

        (success, response) = coins[j].call(
            abi.encodeWithSelector(bytes4(keccak256("transfer(address,uint256)")), _receiver, dy)
        );
        require(success && (response.length == 0 || abi.decode(response, (bool))), "Failed to transfer tokens");

        return dy;
    }

    function remove_liquidity(
        uint256 _burn_amount,
        uint256[N_COINS] memory _min_amounts,
        address _receiver
    ) public returns (uint256[N_COINS] memory) {
        uint256 total_supply = totalSupply();
        uint256[N_COINS] memory amounts;

        for (uint256 i = 0; i < N_COINS; i++) {
            uint256 old_balance = balances[i];
            uint256 value = (old_balance * _burn_amount) / total_supply;
            require(value >= _min_amounts[i], "Withdrawal resulted in fewer coins than expected");

            balances[i] = old_balance - value;
            amounts[i] = value;

            (bool success, bytes memory response) = coins[i].call(
                abi.encodeWithSelector(bytes4(keccak256("transfer(address,uint256)")), _receiver, value)
            );
            require(success && (response.length == 0 || abi.decode(response, (bool))), "Failed to transfer tokens");
        }

        _burn(msg.sender, _burn_amount);

        return amounts;
    }

    function removeLiquidityImbalance(
        uint256[N_COINS] memory _amounts,
        uint256 _max_burn_amount,
        address _receiver
    ) public returns (uint256) {
        require(_receiver != address(0), "Receiver cannot be zero address");

        uint256 amp = _A();
        uint256[N_COINS] memory rates = rate_multipliers;
        uint256[N_COINS] memory old_balances = balances;
        uint256 D0 = get_D_mem(rates, old_balances, amp);

        uint256[N_COINS] memory new_balances = old_balances;
        for (uint256 i = 0; i < N_COINS; i++) {
            uint256 amount = _amounts[i];
            if (amount != 0) {
                new_balances[i] = new_balances[i] - (amount);
                (bool success, ) = coins[i].call(
                    abi.encodeWithSignature("transfer(address,uint256)", _receiver, amount)
                );
                require(success, "Transfer failed");
            }
        }
        uint256 D1 = get_D_mem(rates, new_balances, amp);

        uint256[N_COINS] memory fees;
        uint256 base_fee = (fee * N_COINS) / (4 * (N_COINS - 1));
        for (uint256 i = 0; i < N_COINS; i++) {
            uint256 ideal_balance = (D1 * (old_balances[i])) / (D0);
            uint256 difference = 0;
            uint256 new_balance = new_balances[i];
            if (ideal_balance > new_balance) {
                difference = ideal_balance - (new_balance);
            } else {
                difference = new_balance - (ideal_balance);
            }
            fees[i] = (base_fee * (difference)) / (FEE_DENOMINATOR);
            balances[i] = new_balance - ((fees[i] * (ADMIN_FEE)) / (FEE_DENOMINATOR));
            new_balances[i] = new_balances[i] - (fees[i]);
        }
        uint256 D2 = get_D_mem(rates, new_balances, amp);

        uint256 total_supply = totalSupply();
        uint256 burn_amount = (((D0 - (D2)) * (total_supply)) / (D0)) + (1);
        require(burn_amount > 1, "zero tokens burned");
        require(burn_amount <= _max_burn_amount, "Slippage screwed you");

        _burn(msg.sender, burn_amount);

        return burn_amount;
    }

    function _calc_withdraw_one_coin(uint256 _burn_amount, uint256 i) internal view returns (uint256[2] memory) {
        // First, need to calculate
        // * Get current D
        // * Solve Eqn against y_i for D - _token_amount
        uint256 amp = _A();
        uint256[N_COINS] memory rates = rate_multipliers;
        uint256[N_COINS] memory xp = _xp_mem(rates, balances);
        uint256 D0 = get_D(xp, amp);

        uint256 total_supply = totalSupply();
        uint256 D1 = D0 - ((_burn_amount * (D0)) / (total_supply));
        uint256 new_y = get_y_D(amp, i, xp, D1);

        uint256 base_fee = (fee * (N_COINS)) / (4 * (N_COINS - 1));
        uint256[N_COINS] memory xp_reduced;

        for (uint256 j = 0; j < N_COINS; j++) {
            uint256 dx_expected = 0;
            uint256 xp_j = xp[j];
            if (j == i) {
                dx_expected = (xp_j * (D1)) / (D0) - (new_y);
            } else {
                dx_expected = xp_j - ((xp_j * (D1)) / (D0));
            }
            xp_reduced[j] = xp_j - ((base_fee * (dx_expected)) / (FEE_DENOMINATOR));
        }

        uint256 dy = xp_reduced[i] - (get_y_D(amp, i, xp_reduced, D1));
        uint256 dy_0 = ((xp[i] - (new_y)) * (PRECISION)) / (rates[i]); // w/o fees
        dy = ((dy - (1)) * (PRECISION)) / (rates[i]); // Withdraw less to account for rounding errors

        return [dy, dy_0 - (dy)];
    }

    /// @notice Calculate the amount received when withdrawing a single coin
    /// @param _burn_amount Amount of LP tokens to burn in the withdrawal
    /// @param i Index value of the coin to withdraw
    /// @return Amount of coin received
    function calc_withdraw_one_coin(uint256 _burn_amount, uint256 i) public view returns (uint256) {
        return _calc_withdraw_one_coin(_burn_amount, i)[0];
    }

    function get_y_D(
        uint256 aFactor,
        uint256 i,
        uint256[N_COINS] memory xp,
        uint256 D
    ) internal pure returns (uint256) {
        require(i >= 0, "i below zero");
        require(i < N_COINS, "i above N_COINS");

        uint256 S_ = 0;
        uint256 _x = 0;
        uint256 yPrev = 0;
        uint256 c = D;
        uint256 Ann = aFactor * N_COINS;

        for (uint256 _i = 0; _i < N_COINS; _i++) {
            if (_i != uint256(i)) {
                _x = xp[_i];
            } else {
                continue;
            }
            S_ += _x;
            c = (c * D) / (_x * N_COINS);
        }

        c = (c * D * A_PRECISION) / (Ann * N_COINS);
        uint256 b = S_ + (D * A_PRECISION) / Ann;
        uint256 y = D;

        for (uint256 _i = 0; _i < 255; _i++) {
            yPrev = y;
            y = (y * y + c) / (2 * y + b - D);

            if (y > yPrev) {
                if (y - yPrev <= 1) {
                    return y;
                }
            } else {
                if (yPrev - y <= 1) {
                    return y;
                }
            }
        }
        revert();
    }

    function removeLiquidityOneCoin(
        uint256 _burnAmount,
        uint256 i,
        uint256 _minReceived,
        address _receiver
    ) public returns (uint256) {
        uint256[2] memory dy = _calc_withdraw_one_coin(_burnAmount, i);
        require(dy[0] >= _minReceived, "Not enough coins removed");

        balances[i] -= (dy[0] + (dy[1] * ADMIN_FEE) / FEE_DENOMINATOR);
        _burn(msg.sender, _burnAmount);

        bytes memory data = abi.encodeWithSelector(IERC20(address(coins[i])).transfer.selector, _receiver, dy[0]);
        (, bytes memory response) = address(coins[i]).call(data);
        if (response.length > 0) {
            require(abi.decode(response, (bool)), "Transfer failed");
        }

        return dy[0];
    }

    // function priceForImbalance(
    //     uint256 imbalance,
    // ) public returns (uint256) {
    //     uint256[2] memory dy = _calc_withdraw_one_coin(_burnAmount, i);
    //     require(dy[0] >= _minReceived, "Not enough coins removed");

    //     balances[i] -= (dy[0] + (dy[1] * ADMIN_FEE) / FEE_DENOMINATOR);
    //     _burn(msg.sender, _burnAmount);

    //     bytes memory data = abi.encodeWithSelector(IERC20(address(coins[i])).transfer.selector, _receiver, dy[0]);
    //     (bool success, bytes memory response) = address(coins[i]).call(data);
    //     if (response.length > 0) {
    //         require(abi.decode(response, (bool)), "Transfer failed");
    //     }

    //     return dy[0];
    // }
}
