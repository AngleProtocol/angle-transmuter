// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import "./ProductionTypes.sol";

/// @dev This contract is used only once to initialize the diamond proxy.
contract ProductionSidechain {
    function initialize(
        IAccessControlManager _accessControlManager,
        address _agToken,
        // USDC like tokens
        address liquidStablecoin,
        address[] memory oracleLiquidStablecoin,
        uint8[] memory oracleIsMultiplied,
        uint256 hardCap,
        address dummyImplementation
    ) external {
        // Set Collaterals
        CollateralSetupProd[] memory collaterals = new CollateralSetupProd[](1);
        // Liquid stablecoin
        {
            bytes memory oracleConfig;
            {
                bytes memory readData;
                {
                    uint256 oracleLength = oracleLiquidStablecoin.length;
                    if (oracleLength != oracleIsMultiplied.length) {
                        revert("ProductionSidechain: oracles length not equal");
                    }
                    AggregatorV3Interface[] memory circuitChainlink = new AggregatorV3Interface[](oracleLength);
                    uint32[] memory stalePeriods = new uint32[](oracleLength);
                    uint8[] memory circuitChainIsMultiplied = new uint8[](oracleLength);
                    uint8[] memory chainlinkDecimals = new uint8[](oracleLength);

                    // Oracle between liquid stablecoin and the fiat it is peg to
                    for (uint256 i; i < oracleLiquidStablecoin.length; i++) {
                        circuitChainlink[i] = AggregatorV3Interface(oracleLiquidStablecoin[i]);
                        stalePeriods[i] = 1 days;
                        circuitChainIsMultiplied[i] = oracleIsMultiplied[i];
                        chainlinkDecimals[i] = 8;
                    }
                    OracleQuoteType quoteType = OracleQuoteType.UNIT;
                    readData = abi.encode(
                        circuitChainlink,
                        stalePeriods,
                        circuitChainIsMultiplied,
                        chainlinkDecimals,
                        quoteType
                    );
                }
                bytes memory targetData;
                oracleConfig = abi.encode(
                    Storage.OracleReadType.CHAINLINK_FEEDS,
                    Storage.OracleReadType.STABLE,
                    readData,
                    targetData,
                    abi.encode(uint128(20 * BPS), uint128(0))
                );
            }

            uint64[] memory xMintFee = new uint64[](1);
            xMintFee[0] = uint64(0);

            int64[] memory yMintFee = new int64[](1);
            yMintFee[0] = int64(0);

            uint64[] memory xBurnFee = new uint64[](1);
            xBurnFee[0] = uint64(BASE_9);

            int64[] memory yBurnFee = new int64[](1);
            yBurnFee[0] = int64(0);

            collaterals[0] = CollateralSetupProd(
                liquidStablecoin,
                oracleConfig,
                xMintFee,
                yMintFee,
                xBurnFee,
                yBurnFee
            );
        }

        LibSetters.setAccessControlManager(_accessControlManager);

        TransmuterStorage storage ts = s.transmuterStorage();
        ts.statusReentrant = NOT_ENTERED;
        ts.normalizer = uint128(BASE_27);
        ts.agToken = IAgToken(_agToken);

        // Setup each collateral
        uint256 collateralsLength = collaterals.length;
        for (uint256 i; i < collateralsLength; i++) {
            CollateralSetupProd memory collateral = collaterals[i];
            LibSetters.addCollateral(collateral.token);
            LibSetters.setOracle(collateral.token, collateral.oracleConfig);
            // Mint fees
            LibSetters.setFees(collateral.token, collateral.xMintFee, collateral.yMintFee, true);
            // Burn fees
            LibSetters.setFees(collateral.token, collateral.xBurnFee, collateral.yBurnFee, false);
            LibSetters.togglePause(collateral.token, ActionType.Mint);
            LibSetters.togglePause(collateral.token, ActionType.Burn);
        }

        // setRedemptionCurveParams
        LibSetters.togglePause(liquidStablecoin, ActionType.Redeem);
        uint64[] memory xRedeemFee = new uint64[](4);
        xRedeemFee[0] = uint64((75 * BASE_9) / 100);
        xRedeemFee[1] = uint64((85 * BASE_9) / 100);
        xRedeemFee[2] = uint64((95 * BASE_9) / 100);
        xRedeemFee[3] = uint64((97 * BASE_9) / 100);

        int64[] memory yRedeemFee = new int64[](4);
        yRedeemFee[0] = int64(uint64((995 * BASE_9) / 1000));
        yRedeemFee[1] = int64(uint64((950 * BASE_9) / 1000));
        yRedeemFee[2] = int64(uint64((950 * BASE_9) / 1000));
        yRedeemFee[3] = int64(uint64((995 * BASE_9) / 1000));
        LibSetters.setRedemptionCurveParams(xRedeemFee, yRedeemFee);

        LibSetters.setStablecoinCap(liquidStablecoin, hardCap);
        // setDummyImplementation
        LibDiamondEtherscan.setDummyImplementation(dummyImplementation);
    }
}
