// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.5.0;

/// @title IRedeemer
/// @author Angle Labs, Inc.
interface IRedeemer {
    /// @notice Redeems `amount` of stablecoins from the system
    /// @param receiver Address which should be receiving the output tokens
    /// @param deadline Timestamp before which the redemption should have occured
    /// @param minAmountOuts Minimum amount of each token given back in the redemption to obtain
    /// @return tokens List of tokens returned
    /// @return amounts Amount given for each token in the `tokens` array
    function redeem(
        uint256 amount,
        address receiver,
        uint256 deadline,
        uint256[] memory minAmountOuts
    ) external returns (address[] memory tokens, uint256[] memory amounts);

    /// @notice Same as the redeem function above with the additional feature to specify a list of `forfeitTokens` for
    /// which the Transmuter system will not try to do a transfer to `receiver`.
    function redeemWithForfeit(
        uint256 amount,
        address receiver,
        uint256 deadline,
        uint256[] memory minAmountOuts,
        address[] memory forfeitTokens
    ) external returns (address[] memory tokens, uint256[] memory amounts);

    /// @notice Simulate the exact output that a redemption of `amount` of stablecoins would give at a given block
    /// @return tokens List of tokens that would be given
    /// @return amounts Amount that would be obtained for each token in the `tokens` array
    function quoteRedemptionCurve(
        uint256 amount
    ) external view returns (address[] memory tokens, uint256[] memory amounts);

    /// @notice Updates the normalizer variable by `amount`
    function updateNormalizer(uint256 amount, bool increase) external returns (uint256);
}
