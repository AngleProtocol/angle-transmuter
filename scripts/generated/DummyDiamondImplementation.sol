// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * This is a generated dummy diamond implementation for compatibility with
 * etherscan. For full contract implementation, check out the diamond on louper:
 * https://louper.dev/diamond/0xFF091a4FDBcddce68805183dfFdeA47cDbb9fEAC?network=xdai
 */

contract DummyDiamondImplementation {
    struct Tuple6871229 {
        address facetAddress;
        uint8 action;
        bytes4[] functionSelectors;
    }

    struct Tuple1236461 {
        address facetAddress;
        bytes4[] functionSelectors;
    }

    struct Tuple3550792 {
        uint8 isManaged;
        uint8 isMintLive;
        uint8 isBurnLive;
        uint8 decimals;
        uint8 onlyWhitelisted;
        uint216 normalizedStables;
        uint64[] xFeeMint;
        int64[] yFeeMint;
        uint64[] xFeeBurn;
        int64[] yFeeBurn;
        bytes oracleConfig;
        bytes whitelistData;
        Tuple5479340 managerData;
    }

    struct Tuple5479340 {
        address[] subCollaterals;
        bytes config;
    }

    function diamondCut(Tuple6871229[] memory _diamondCut, address _init, bytes memory _calldata) external {}

    function implementation() external view returns (address) {}

    function setDummyImplementation(address _implementation) external {}

    function facetAddress(bytes4 _functionSelector) external view returns (address facetAddress_) {}

    function facetAddresses() external view returns (address[] memory facetAddresses_) {}

    function facetFunctionSelectors(address _facet) external view returns (bytes4[] memory _facetFunctionSelectors) {}

    function facets() external view returns (Tuple1236461[] memory facets_) {}

    function accessControlManager() external view returns (address) {}

    function agToken() external view returns (address) {}

    function getCollateralBurnFees(
        address collateral
    ) external view returns (uint64[] memory xFeeBurn, int64[] memory yFeeBurn) {}

    function getCollateralDecimals(address collateral) external view returns (uint8) {}

    function getCollateralInfo(address collateral) external view returns (Tuple3550792 memory) {}

    function getCollateralList() external view returns (address[] memory) {}

    function getCollateralMintFees(
        address collateral
    ) external view returns (uint64[] memory xFeeMint, int64[] memory yFeeMint) {}

    function getCollateralRatio() external view returns (uint64 collatRatio, uint256 stablecoinsIssued) {}

    function getCollateralWhitelistData(address collateral) external view returns (bytes memory) {}

    function getIssuedByCollateral(
        address collateral
    ) external view returns (uint256 stablecoinsFromCollateral, uint256 stablecoinsIssued) {}

    function getManagerData(address collateral) external view returns (bool, address[] memory, bytes memory) {}

    function getOracle(
        address collateral
    ) external view returns (uint8 oracleType, uint8 targetType, bytes memory oracleData, bytes memory targetData) {}

    function getOracleValues(
        address collateral
    ) external view returns (uint256 mint, uint256 burn, uint256 ratio, uint256 minRatio, uint256 redemption) {}

    function getRedemptionFees()
        external
        view
        returns (uint64[] memory xRedemptionCurve, int64[] memory yRedemptionCurve)
    {}

    function getTotalIssued() external view returns (uint256) {}

    function isPaused(address collateral, uint8 action) external view returns (bool) {}

    function isTrusted(address sender) external view returns (bool) {}

    function isTrustedSeller(address sender) external view returns (bool) {}

    function isValidSelector(bytes4 selector) external view returns (bool) {}

    function isWhitelistedCollateral(address collateral) external view returns (bool) {}

    function isWhitelistedForCollateral(address collateral, address sender) external returns (bool) {}

    function isWhitelistedForType(uint8 whitelistType, address sender) external view returns (bool) {}

    function sellRewards(uint256 minAmountOut, bytes memory payload) external returns (uint256 amountOut) {}

    function addCollateral(address collateral) external {}

    function adjustStablecoins(address collateral, uint128 amount, bool increase) external {}

    function changeAllowance(address token, address spender, uint256 amount) external {}

    function recoverERC20(address collateral, address token, address to, uint256 amount) external {}

    function revokeCollateral(address collateral) external {}

    function setAccessControlManager(address _newAccessControlManager) external {}

    function setCollateralManager(address collateral, Tuple5479340 memory managerData) external {}

    function setOracle(address collateral, bytes memory oracleConfig) external {}

    function setWhitelistStatus(address collateral, uint8 whitelistStatus, bytes memory whitelistData) external {}

    function toggleTrusted(address sender, uint8 t) external {}

    function setFees(address collateral, uint64[] memory xFee, int64[] memory yFee, bool mint) external {}

    function setRedemptionCurveParams(uint64[] memory xFee, int64[] memory yFee) external {}

    function togglePause(address collateral, uint8 pausedType) external {}

    function toggleWhitelist(uint8 whitelistType, address who) external {}

    function quoteIn(uint256 amountIn, address tokenIn, address tokenOut) external view returns (uint256 amountOut) {}

    function quoteOut(uint256 amountOut, address tokenIn, address tokenOut) external view returns (uint256 amountIn) {}

    function swapExactInput(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut) {}

    function swapExactInputWithPermit(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        address to,
        uint256 deadline,
        bytes memory permitData
    ) external returns (uint256 amountOut) {}

    function swapExactOutput(
        uint256 amountOut,
        uint256 amountInMax,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external returns (uint256 amountIn) {}

    function swapExactOutputWithPermit(
        uint256 amountOut,
        uint256 amountInMax,
        address tokenIn,
        address to,
        uint256 deadline,
        bytes memory permitData
    ) external returns (uint256 amountIn) {}

    function quoteRedemptionCurve(
        uint256 amount
    ) external view returns (address[] memory tokens, uint256[] memory amounts) {}

    function redeem(
        uint256 amount,
        address receiver,
        uint256 deadline,
        uint256[] memory minAmountOuts
    ) external returns (address[] memory tokens, uint256[] memory amounts) {}

    function redeemWithForfeit(
        uint256 amount,
        address receiver,
        uint256 deadline,
        uint256[] memory minAmountOuts,
        address[] memory forfeitTokens
    ) external returns (address[] memory tokens, uint256[] memory amounts) {}

    function updateNormalizer(uint256 amount, bool increase) external returns (uint256) {}
}
