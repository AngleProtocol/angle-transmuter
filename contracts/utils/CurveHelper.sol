// SPDX-License-Identifier: GPL-3.0

import { Constants as c } from "../utils/Constants.sol";

pragma solidity ^0.8.17;

//solhint-disable
contract CurveHelper {
    uint256 public constant N_COINS = 2;
    uint256 public constant A_PRECISION = 100;

    uint256 public initial_A;
    uint256 public future_A;
    uint256 public initial_A_time;
    uint256 public future_A_time;

    constructor() {}

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
        uint256 e = D;
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
            e = (e * D) / (_x * N_COINS);
        }

        e = (e * D * A_PRECISION) / (Ann * N_COINS);
        uint256 b = S_ + (D * A_PRECISION) / Ann;
        uint256 y = D;

        for (uint256 _i = 0; _i < 255; _i++) {
            y_prev = y;
            y = (y * y + e) / (2 * y + b - D);
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

    function get_dy(uint256 i, uint256 j, uint256 dx, uint256[N_COINS] memory balances) public view returns (uint256) {
        uint256 x = balances[i] + dx;
        uint256 y = get_y(i, j, x, balances);
        uint256 dy = balances[j] - y - 1;
        uint256 auxFee = (4000000 * dy) / 1e10;

        return (dy - auxFee);
    }

    /// @param imbalance Imbalance of token 0 in base 18
    /// @dev This will assume tokens have the same base
    function priceForImbalance(uint256 A, uint256 imbalance) external returns (uint256, uint256, uint256, uint256) {
        initial_A = A * A_PRECISION;
        future_A = A * A_PRECISION;

        // Set up liquidity
        uint256[N_COINS] memory balances;
        for (uint256 i = 0; i < N_COINS; i++) {
            balances[i] = 1e27;
        }

        // If swap 1 -> 0
        if (imbalance > 5e17) {
            uint256 dx = ((imbalance - 5e17) * 1e27) / 1e18;
            uint256 dy = get_dy(1, 0, ((imbalance - 5e17) * 1e27) / 1e18, balances);
            balances[0] += dy;
            balances[1] -= dx;
        } else {
            uint256 dx = ((5e17 - imbalance) * 1e27) / 1e18;
            uint256 dy = get_dy(0, 1, ((5e17 - imbalance) * 1e27) / 1e18, balances);
            balances[1] += dy;
            balances[0] -= dx;
        }

        return (
            balances[0],
            balances[1],
            (balances[0] * 1e18) / (balances[0] + balances[1]),
            get_dy(1, 0, 1e18, balances)
        );
    }
}
