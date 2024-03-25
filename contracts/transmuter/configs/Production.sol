// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import "./ProductionTypes.sol";

/// @dev This contract is used only once to initialize the diamond proxy.
contract Production {
    error WrongSetup();

    address public constant EUROC = 0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c;
    address public constant BC3M = 0x2F123cF3F37CE3328CC9B5b8415f9EC5109b45e7;

    function initialize(
        IAccessControlManager _accessControlManager,
        address _agToken,
        address dummyImplementation
    ) external {
        if (address(_accessControlManager) != 0x5bc6BEf80DA563EBf6Df6D6913513fa9A7ec89BE) revert NotTrusted();
        if (address(_agToken) != 0x1a7e4e63778B4f12a199C062f3eFdD288afCBce8) revert NotTrusted();

        // Check this docs for simulations:
        // https://docs.google.com/spreadsheets/d/1UxS1m4sG8j2Lv02wONYJNkF4S7NDLv-5iyAzFAFTfXw/edit#gid=0

        // Set Collaterals
        CollateralSetupProd[] memory collaterals = new CollateralSetupProd[](2);

        // EUROC
        {
            uint64[] memory xMintFeeEuroc = new uint64[](3);
            xMintFeeEuroc[0] = uint64(0);
            xMintFeeEuroc[1] = uint64((74 * BASE_9) / 100);
            xMintFeeEuroc[2] = uint64((75 * BASE_9) / 100);

            int64[] memory yMintFeeEuroc = new int64[](3);
            yMintFeeEuroc[0] = int64(uint64(BASE_9 / 1000));
            yMintFeeEuroc[1] = int64(uint64(BASE_9 / 1000));
            yMintFeeEuroc[2] = int64(uint64(MAX_MINT_FEE));

            uint64[] memory xBurnFeeEuroc = new uint64[](3);
            xBurnFeeEuroc[0] = uint64(BASE_9);
            xBurnFeeEuroc[1] = uint64((51 * BASE_9) / 100);
            xBurnFeeEuroc[2] = uint64((50 * BASE_9) / 100);

            int64[] memory yBurnFeeEuroc = new int64[](3);
            yBurnFeeEuroc[0] = int64(uint64((2 * BASE_9) / 1000));
            yBurnFeeEuroc[1] = int64(uint64((2 * BASE_9) / 1000));
            yBurnFeeEuroc[2] = int64(uint64(MAX_BURN_FEE));

            bytes memory oracleConfig;
            {
                // Pyth oracle for EUROC
                bytes memory readData;
                {
                    bytes32[] memory feedIds = new bytes32[](2);
                    uint32[] memory stalePeriods = new uint32[](2);
                    uint8[] memory isMultiplied = new uint8[](2);
                    // pyth address
                    address pyth = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6;
                    // EUROC/USD
                    feedIds[0] = 0x76fa85158bf14ede77087fe3ae472f66213f6ea2f5b411cb2de472794990fa5c;
                    // USD/EUR
                    feedIds[1] = 0xa995d00bb36a63cef7fd2c287dc105fc8f3d93779f062f09551b0af3e81ec30b;
                    stalePeriods[0] = 14 days;
                    stalePeriods[1] = 14 days;
                    isMultiplied[0] = 1;
                    isMultiplied[1] = 0;
                    OracleQuoteType quoteType = OracleQuoteType.UNIT;
                    readData = abi.encode(pyth, feedIds, stalePeriods, isMultiplied, quoteType);
                }
                bytes memory targetData;
                oracleConfig = abi.encode(
                    Storage.OracleReadType.PYTH,
                    Storage.OracleReadType.STABLE,
                    readData,
                    targetData,
                    abi.encode(uint80(5 * BPS), uint80(0), uint80(0))
                );
            }
            collaterals[0] = CollateralSetupProd(
                EUROC,
                oracleConfig,
                xMintFeeEuroc,
                yMintFeeEuroc,
                xBurnFeeEuroc,
                yBurnFeeEuroc
            );
        }

        // bC3M
        {
            uint64[] memory xMintFeeC3M = new uint64[](3);
            xMintFeeC3M[0] = uint64(0);
            xMintFeeC3M[1] = uint64((49 * BASE_9) / 100);
            xMintFeeC3M[2] = uint64((50 * BASE_9) / 100);

            int64[] memory yMintFeeC3M = new int64[](3);
            yMintFeeC3M[0] = int64(uint64((2 * BASE_9) / 1000));
            yMintFeeC3M[1] = int64(uint64((2 * BASE_9) / 1000));
            yMintFeeC3M[2] = int64(uint64(MAX_MINT_FEE));

            uint64[] memory xBurnFeeC3M = new uint64[](3);
            xBurnFeeC3M[0] = uint64(BASE_9);
            xBurnFeeC3M[1] = uint64((26 * BASE_9) / 100);
            xBurnFeeC3M[2] = uint64((25 * BASE_9) / 100);

            int64[] memory yBurnFeeC3M = new int64[](3);
            yBurnFeeC3M[0] = int64(uint64((5 * BASE_9) / 1000));
            yBurnFeeC3M[1] = int64(uint64((5 * BASE_9) / 1000));
            yBurnFeeC3M[2] = int64(uint64(MAX_BURN_FEE));

            bytes memory readData;
            {
                AggregatorV3Interface[] memory circuitChainlink = new AggregatorV3Interface[](1);
                uint32[] memory stalePeriods = new uint32[](1);
                uint8[] memory circuitChainIsMultiplied = new uint8[](1);
                uint8[] memory chainlinkDecimals = new uint8[](1);

                // bC3M: Redstone as a current price (more accurate for redemptions), and Backed as a target

                // Redstone C3M Oracle
                circuitChainlink[0] = AggregatorV3Interface(0x6E27A25999B3C665E44D903B2139F5a4Be2B6C26);
                stalePeriods[0] = 3 days;
                circuitChainIsMultiplied[0] = 1;
                chainlinkDecimals[0] = 8;
                OracleQuoteType quoteType = OracleQuoteType.UNIT;
                readData = abi.encode(
                    circuitChainlink,
                    stalePeriods,
                    circuitChainIsMultiplied,
                    chainlinkDecimals,
                    quoteType
                );
            }

            // Backed C3M Oracle
            bytes memory targetData;
            {
                uint256 initialValue;

                {
                    (, int256 ratio, , , ) = AggregatorV3Interface(0x83Ec02059F686E747392A22ddfED7833bA0d7cE3)
                        .latestRoundData();
                    if (ratio <= 0) revert WrongSetup();
                    initialValue = (BASE_18 * uint256(ratio)) / 1e8;
                }
                targetData = abi.encode(initialValue, block.timestamp, 50 * BPS, 1 days);
            }
            bytes memory oracleConfig = abi.encode(
                Storage.OracleReadType.CHAINLINK_FEEDS,
                Storage.OracleReadType.MAX,
                readData,
                targetData,
                abi.encode(uint80(0), uint80(20000 * BPS), uint128(100 * BPS))
            );

            collaterals[1] = CollateralSetupProd(
                BC3M,
                oracleConfig,
                xMintFeeC3M,
                yMintFeeC3M,
                xBurnFeeC3M,
                yBurnFeeC3M
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

        // Set whitelist status for bC3M
        bytes memory whitelistData = abi.encode(
            WhitelistType.BACKED,
            // Keyring whitelist check
            abi.encode(address(0x4954c61984180868495D1a7Fb193b05a2cbd9dE3))
        );
        LibSetters.setWhitelistStatus(BC3M, 1, whitelistData);

        // adjustStablecoins
        LibSetters.adjustStablecoins(EUROC, 8851136430000000000000000, true);
        LibSetters.adjustStablecoins(BC3M, 4192643570000000000000000, true);

        // setRedemptionCurveParams
        LibSetters.togglePause(EUROC, ActionType.Redeem);
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
