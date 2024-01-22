// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import "./ProductionTypes.sol";

/// @dev This contract is used only once to initialize the diamond proxy.
contract ProductionUSD {
    function initialize(
        IAccessControlManager _accessControlManager,
        address _agToken,
        address dummyImplementation
    ) external {
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        /*
        require(address(_accessControlManager) == 0x5bc6BEf80DA563EBf6Df6D6913513fa9A7ec89BE);
        require(address(_agToken) == 0x0000206329b97DB379d5E1Bf586BbDB969C63274);
        */

        // Set Collaterals
        CollateralSetupProd[] memory collaterals = new CollateralSetupProd[](1);
        // USDC
        {
            uint64[] memory xMintFeeUsdc = new uint64[](1);
            xMintFeeUsdc[0] = uint64(0);

            int64[] memory yMintFeeUsdc = new int64[](1);
            yMintFeeUsdc[0] = int64(0);

            uint64[] memory xBurnFeeUsdc = new uint64[](1);
            xBurnFeeUsdc[0] = uint64(BASE_9);

            int64[] memory yBurnFeeUsdc = new int64[](1);
            yBurnFeeUsdc[0] = int64(0);

            bytes memory oracleConfig;
            {
                AggregatorV3Interface[] memory circuitChainlink = new AggregatorV3Interface[](1);
                uint32[] memory stalePeriods = new uint32[](1);
                uint8[] memory circuitChainIsMultiplied = new uint8[](1);
                uint8[] memory chainlinkDecimals = new uint8[](1);

                // Chainlink USDC/USD oracle
                circuitChainlink[0] = AggregatorV3Interface(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);
                stalePeriods[0] = 1 days;
                circuitChainIsMultiplied[0] = 1;
                chainlinkDecimals[0] = 8;
                OracleQuoteType quoteType = OracleQuoteType.UNIT;
                bytes memory readData = abi.encode(
                    circuitChainlink,
                    stalePeriods,
                    circuitChainIsMultiplied,
                    chainlinkDecimals,
                    quoteType
                );
                bytes memory targetData;
                oracleConfig = abi.encode(
                    Storage.OracleReadType.CHAINLINK_FEEDS,
                    Storage.OracleReadType.STABLE,
                    readData,
                    targetData
                );
            }
            collaterals[0] = CollateralSetupProd(
                usdc,
                oracleConfig,
                xMintFeeUsdc,
                yMintFeeUsdc,
                xBurnFeeUsdc,
                yBurnFeeUsdc
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
        LibSetters.togglePause(usdc, ActionType.Redeem);
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

        // setDummyImplementation
        LibDiamondEtherscan.setDummyImplementation(dummyImplementation);
    }
}
