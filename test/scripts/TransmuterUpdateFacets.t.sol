// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { stdJson } from "forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";

import { BC3M, BPS, EUROC, BASE_6, DEPLOYER, NEW_DEPLOYER, KEEPER, NEW_KEEPER } from "../../scripts/Constants.s.sol";

import { Helpers } from "../../scripts/Helpers.s.sol";
import "contracts/utils/Errors.sol" as Errors;
import "contracts/transmuter/Storage.sol" as Storage;
import { Getters } from "contracts/transmuter/facets/Getters.sol";
import { Oracle } from "contracts/transmuter/facets/Oracle.sol";
import { Redeemer } from "contracts/transmuter/facets/Redeemer.sol";
import { SettersGovernor } from "contracts/transmuter/facets/SettersGovernor.sol";
import { SettersGuardian } from "contracts/transmuter/facets/SettersGuardian.sol";
import { Swapper } from "contracts/transmuter/facets/Swapper.sol";
import "contracts/transmuter/libraries/LibHelpers.sol";
import { ITransmuter } from "interfaces/ITransmuter.sol";
import "utils/src/Constants.sol";
import { IERC20 } from "oz/interfaces/IERC20.sol";

interface OldTransmuter {
    function getOracle(
        address
    ) external view returns (Storage.OracleReadType, Storage.OracleReadType, bytes memory, bytes memory);
}

contract TransmuterUpdateFacets is Helpers, Test {
    using stdJson for string;

    uint128 constant FIREWALL_MINT_EUROC = 0;
    uint128 constant FIREWALL_BURN_EUROC = uint128(5 * BPS);
    uint128 constant FIREWALL_MINT_BC3M = uint128(BASE_18);
    uint128 constant FIREWALL_BURN_BC3M = uint128(100 * BPS);
    uint96 constant DEVIATION_THRESHOLD_BC3M = uint96(100 * BPS);
    uint32 constant HEARTBEAT = uint32(1 days);
    address constant WHALE_AGEUR = 0x4Fa745FCCC04555F2AFA8874cd23961636CdF982;

    uint256 public CHAIN_SOURCE;

    string[] replaceFacetNames;
    string[] addFacetNames;
    address[] facetAddressList;

    ITransmuter transmuter;
    IERC20 agEUR;
    address governor;
    bytes public oracleConfigEUROC;
    bytes public oracleConfigBC3M;

    function setUp() public override {
        super.setUp();

        CHAIN_SOURCE = CHAIN_ETHEREUM;

        vm.selectFork(forkIdentifier[CHAIN_SOURCE]);

        governor = _chainToContract(CHAIN_SOURCE, ContractType.Timelock);
        transmuter = ITransmuter(_chainToContract(CHAIN_SOURCE, ContractType.TransmuterAgEUR));
        agEUR = IERC20(_chainToContract(CHAIN_SOURCE, ContractType.AgEUR));
        governor = 0x09D81464c7293C774203E46E3C921559c8E9D53f;
        transmuter = ITransmuter(0x00253582b2a3FE112feEC532221d9708c64cEFAb);

        Storage.FacetCut[] memory replaceCut;
        Storage.FacetCut[] memory addCut;

        replaceFacetNames.push("Getters");
        facetAddressList.push(address(new Getters()));
        console.log("Getters deployed at: ", facetAddressList[facetAddressList.length - 1]);

        replaceFacetNames.push("Redeemer");
        facetAddressList.push(address(new Redeemer()));
        console.log("Redeemer deployed at: ", facetAddressList[facetAddressList.length - 1]);

        replaceFacetNames.push("SettersGovernor");
        facetAddressList.push(address(new SettersGovernor()));
        console.log("SettersGovernor deployed at: ", facetAddressList[facetAddressList.length - 1]);

        replaceFacetNames.push("Swapper");
        facetAddressList.push(address(new Swapper()));
        console.log("Swapper deployed at: ", facetAddressList[facetAddressList.length - 1]);

        // // TODO This one should be useless
        // replaceFacetNames.push("SettersGuardian");
        // facetAddressList.push(address(new SettersGuardian()));
        // console.log("SettersGuardian deployed at: ", facetAddressList[facetAddressList.length-1]);

        addFacetNames.push("Oracle");
        facetAddressList.push(address(new Oracle()));
        console.log("Oracle deployed at: ", facetAddressList[facetAddressList.length - 1]);

        string memory json = vm.readFile(JSON_SELECTOR_PATH);
        {
            // Build appropriate payload
            uint256 n = replaceFacetNames.length;
            replaceCut = new Storage.FacetCut[](n);
            for (uint256 i = 0; i < n; ++i) {
                // Get Selectors from json
                bytes4[] memory selectors = _arrayBytes32ToBytes4(
                    json.readBytes32Array(string.concat("$.", replaceFacetNames[i]))
                );

                replaceCut[i] = Storage.FacetCut({
                    facetAddress: facetAddressList[i],
                    action: Storage.FacetCutAction.Replace,
                    functionSelectors: selectors
                });
            }
        }

        {
            // Build appropriate payload
            uint256 r = replaceFacetNames.length;
            uint256 n = addFacetNames.length;
            addCut = new Storage.FacetCut[](n);
            for (uint256 i = 0; i < n; ++i) {
                // Get Selectors from json
                bytes4[] memory selectors = _arrayBytes32ToBytes4(
                    json.readBytes32Array(string.concat("$.", addFacetNames[i]))
                );
                addCut[i] = Storage.FacetCut({
                    facetAddress: facetAddressList[r + i],
                    action: Storage.FacetCutAction.Add,
                    functionSelectors: selectors
                });
            }
        }

        vm.startPrank(governor);

        // Get the previous oracles configs
        (
            Storage.OracleReadType oracleTypeEUROC,
            Storage.OracleReadType targetTypeEUROC,
            bytes memory oracleDataEUROC,
            bytes memory targetDataEUROC
        ) = OldTransmuter(address(transmuter)).getOracle(address(EUROC));

        (Storage.OracleReadType oracleTypeBC3M, , bytes memory oracleDataBC3M, ) = OldTransmuter(address(transmuter))
            .getOracle(address(BC3M));

        (, , , , uint256 currentBC3MPrice) = transmuter.getOracleValues(address(BC3M));

        bytes memory callData;
        // set the right implementations
        transmuter.diamondCut(replaceCut, address(0), callData);
        transmuter.diamondCut(addCut, address(0), callData);

        // update the oracles
        oracleConfigEUROC = abi.encode(
            oracleTypeEUROC,
            targetTypeEUROC,
            oracleDataEUROC,
            targetDataEUROC,
            abi.encode(FIREWALL_MINT_EUROC, FIREWALL_BURN_EUROC)
        );
        transmuter.setOracle(EUROC, oracleConfigEUROC);

        oracleConfigBC3M = abi.encode(
            oracleTypeBC3M,
            Storage.OracleReadType.MAX,
            oracleDataBC3M,
            abi.encode(currentBC3MPrice, DEVIATION_THRESHOLD_BC3M, uint96(block.timestamp), HEARTBEAT),
            abi.encode(FIREWALL_MINT_BC3M, FIREWALL_BURN_BC3M)
        );
        transmuter.setOracle(BC3M, oracleConfigBC3M);

        transmuter.toggleWhitelist(Storage.WhitelistType.BACKED, WHALE_AGEUR);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        GETTERS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testUnit_Upgrade_AccessControlManager() external {
        assertEq(address(transmuter.accessControlManager()), _chainToContract(CHAIN_SOURCE, ContractType.CoreBorrow));
    }

    function testUnit_Upgrade_AgToken() external {
        assertEq(address(transmuter.agToken()), _chainToContract(CHAIN_SOURCE, ContractType.AgEUR));
    }

    function testUnit_Upgrade_GetCollateralList() external {
        address[] memory collateralList = transmuter.getCollateralList();
        assertEq(collateralList.length, 2);
        assertEq(collateralList[0], address(EUROC));
        assertEq(collateralList[1], address(BC3M));
    }

    function testUnit_Upgrade_GetCollateralInfo() external {
        {
            Storage.Collateral memory collatInfoEUROC = transmuter.getCollateralInfo(address(EUROC));
            assertEq(collatInfoEUROC.isManaged, 0);
            assertEq(collatInfoEUROC.isMintLive, 1);
            assertEq(collatInfoEUROC.isBurnLive, 1);
            assertEq(collatInfoEUROC.decimals, 6);
            assertEq(collatInfoEUROC.onlyWhitelisted, 0);
            assertApproxEqRel(collatInfoEUROC.normalizedStables, 10893124 * BASE_18, 100 * BPS);
            assertEq(collatInfoEUROC.oracleConfig, oracleConfigEUROC);
            assertEq(collatInfoEUROC.whitelistData.length, 0);
            assertEq(collatInfoEUROC.managerData.subCollaterals.length, 0);
            assertEq(collatInfoEUROC.managerData.config.length, 0);

            {
                assertEq(collatInfoEUROC.xFeeMint.length, 5);
                assertEq(collatInfoEUROC.yFeeMint.length, 5);
                assertEq(collatInfoEUROC.xFeeMint[0], 0);
                assertEq(collatInfoEUROC.yFeeMint[0], 0);
                assertEq(collatInfoEUROC.xFeeMint[1], 730000000);
                assertEq(collatInfoEUROC.yFeeMint[1], 0);
                assertEq(collatInfoEUROC.xFeeMint[2], 740000000);
                assertEq(collatInfoEUROC.yFeeMint[2], 500000);
                assertEq(collatInfoEUROC.xFeeMint[3], 745000000);
                assertEq(collatInfoEUROC.yFeeMint[3], 1000000);
                assertEq(collatInfoEUROC.xFeeMint[4], 750000000);
                assertEq(collatInfoEUROC.yFeeMint[4], 1000000000000);
            }
            {
                assertEq(collatInfoEUROC.xFeeBurn.length, 5);
                assertEq(collatInfoEUROC.yFeeBurn.length, 5);
                assertEq(collatInfoEUROC.xFeeBurn[0], 1000000000);
                assertEq(collatInfoEUROC.yFeeBurn[0], 0);
                assertEq(collatInfoEUROC.xFeeBurn[1], 670000000);
                assertEq(collatInfoEUROC.yFeeBurn[1], 0);
                assertEq(collatInfoEUROC.xFeeBurn[2], 590000000);
                assertEq(collatInfoEUROC.yFeeBurn[2], 1000000);
                assertEq(collatInfoEUROC.xFeeBurn[3], 505000000);
                assertEq(collatInfoEUROC.yFeeBurn[3], 1000000);
                assertEq(collatInfoEUROC.xFeeBurn[4], 500000000);
                assertEq(collatInfoEUROC.yFeeBurn[4], 999000000);
            }
        }

        {
            Storage.Collateral memory collatInfoBC3M = transmuter.getCollateralInfo(address(BC3M));
            assertEq(collatInfoBC3M.isManaged, 0);
            assertEq(collatInfoBC3M.isMintLive, 1);
            assertEq(collatInfoBC3M.isBurnLive, 1);
            assertEq(collatInfoBC3M.decimals, 18);
            assertEq(collatInfoBC3M.onlyWhitelisted, 1);
            assertApproxEqRel(collatInfoBC3M.normalizedStables, 6236650 * BASE_18, 100 * BPS);
            assertEq(collatInfoBC3M.oracleConfig, oracleConfigBC3M);
            {
                (Storage.WhitelistType whitelist, bytes memory data) = abi.decode(
                    collatInfoBC3M.whitelistData,
                    (Storage.WhitelistType, bytes)
                );
                address keyringGuard = abi.decode(data, (address));
                assertEq(uint8(whitelist), uint8(Storage.WhitelistType.BACKED));
                assertEq(keyringGuard, 0x9391B14dB2d43687Ea1f6E546390ED4b20766c46);
            }
            assertEq(collatInfoBC3M.managerData.subCollaterals.length, 0);
            assertEq(collatInfoBC3M.managerData.config.length, 0);

            {
                assertEq(collatInfoBC3M.xFeeMint.length, 4);
                assertEq(collatInfoBC3M.yFeeMint.length, 4);
                assertEq(collatInfoBC3M.xFeeMint[0], 0);
                assertEq(collatInfoBC3M.yFeeMint[0], 0);
                assertEq(collatInfoBC3M.xFeeMint[1], 400000000);
                assertEq(collatInfoBC3M.yFeeMint[1], 0);
                assertEq(collatInfoBC3M.xFeeMint[2], 495000000);
                assertEq(collatInfoBC3M.yFeeMint[2], 2000000);
                assertEq(collatInfoBC3M.xFeeMint[3], 500000000);
                assertEq(collatInfoBC3M.yFeeMint[3], 1000000000000);
            }
            {
                assertEq(collatInfoBC3M.xFeeBurn.length, 3);
                assertEq(collatInfoBC3M.yFeeBurn.length, 3);
                assertEq(collatInfoBC3M.xFeeBurn[0], 1000000000);
                assertEq(collatInfoBC3M.yFeeBurn[0], 5000000);
                assertEq(collatInfoBC3M.xFeeBurn[1], 260000000);
                assertEq(collatInfoBC3M.yFeeBurn[1], 5000000);
                assertEq(collatInfoBC3M.xFeeBurn[2], 250000000);
                assertEq(collatInfoBC3M.yFeeBurn[2], 999000000);
            }
        }
    }

    function testUnit_Upgrade_GetCollateralDecimals() external {
        assertEq(transmuter.getCollateralDecimals(address(EUROC)), 6);
        assertEq(transmuter.getCollateralDecimals(address(BC3M)), 18);
    }

    function testUnit_Upgrade_getCollateralMintFees() external {
        {
            (uint64[] memory xFeeMint, int64[] memory yFeeMint) = transmuter.getCollateralMintFees(address(EUROC));
            assertEq(xFeeMint.length, 5);
            assertEq(yFeeMint.length, 5);
            assertEq(xFeeMint[0], 0);
            assertEq(yFeeMint[0], 0);
            assertEq(xFeeMint[1], 730000000);
            assertEq(yFeeMint[1], 0);
            assertEq(xFeeMint[2], 740000000);
            assertEq(yFeeMint[2], 500000);
            assertEq(xFeeMint[3], 745000000);
            assertEq(yFeeMint[3], 1000000);
            assertEq(xFeeMint[4], 750000000);
            assertEq(yFeeMint[4], 1000000000000);
        }
        {
            (uint64[] memory xFeeMint, int64[] memory yFeeMint) = transmuter.getCollateralMintFees(address(BC3M));
            assertEq(xFeeMint.length, 4);
            assertEq(yFeeMint.length, 4);
            assertEq(xFeeMint[0], 0);
            assertEq(yFeeMint[0], 0);
            assertEq(xFeeMint[1], 400000000);
            assertEq(yFeeMint[1], 0);
            assertEq(xFeeMint[2], 495000000);
            assertEq(yFeeMint[2], 2000000);
            assertEq(xFeeMint[3], 500000000);
            assertEq(yFeeMint[3], 1000000000000);
        }
    }

    function testUnit_Upgrade_getCollateralBurnFees() external {
        {
            (uint64[] memory xFeeBurn, int64[] memory yFeeBurn) = transmuter.getCollateralBurnFees(address(EUROC));
            assertEq(xFeeBurn.length, 5);
            assertEq(yFeeBurn.length, 5);
            assertEq(xFeeBurn[0], 1000000000);
            assertEq(yFeeBurn[0], 0);
            assertEq(xFeeBurn[1], 670000000);
            assertEq(yFeeBurn[1], 0);
            assertEq(xFeeBurn[2], 590000000);
            assertEq(yFeeBurn[2], 1000000);
            assertEq(xFeeBurn[3], 505000000);
            assertEq(yFeeBurn[3], 1000000);
            assertEq(xFeeBurn[4], 500000000);
            assertEq(yFeeBurn[4], 999000000);
        }
        {
            (uint64[] memory xFeeBurn, int64[] memory yFeeBurn) = transmuter.getCollateralBurnFees(address(BC3M));
            assertEq(xFeeBurn.length, 3);
            assertEq(yFeeBurn.length, 3);
            assertEq(xFeeBurn[0], 1000000000);
            assertEq(yFeeBurn[0], 5000000);
            assertEq(xFeeBurn[1], 260000000);
            assertEq(yFeeBurn[1], 5000000);
            assertEq(xFeeBurn[2], 250000000);
            assertEq(yFeeBurn[2], 999000000);
        }
    }

    function testUnit_Upgrade_GetCollateralRatio() external {
        (uint64 collatRatio, uint256 stablecoinIssued) = transmuter.getCollateralRatio();
        assertApproxEqRel(collatRatio, 1065 * 10 ** 6, BPS * 100);
        assertApproxEqRel(stablecoinIssued, 17129775 * BASE_18, 100 * BPS);
    }

    function testUnit_Upgrade_isTrusted() external {
        assertEq(transmuter.isTrusted(address(governor)), false);
        assertEq(transmuter.isTrustedSeller(address(governor)), false);
        assertEq(transmuter.isTrusted(DEPLOYER), false);
        assertEq(transmuter.isTrustedSeller(DEPLOYER), false);
        assertEq(transmuter.isTrusted(NEW_DEPLOYER), false);
        assertEq(transmuter.isTrustedSeller(NEW_DEPLOYER), false);
        assertEq(transmuter.isTrusted(KEEPER), false);
        assertEq(transmuter.isTrustedSeller(KEEPER), false);
        assertEq(transmuter.isTrusted(NEW_KEEPER), false);
        assertEq(transmuter.isTrustedSeller(NEW_KEEPER), false);
    }

    function testUnit_Upgrade_IsWhitelistedForCollateral() external {
        assertEq(transmuter.isWhitelistedForCollateral(address(EUROC), alice), true);
        assertEq(transmuter.isWhitelistedForCollateral(address(BC3M), alice), false);
        assertEq(transmuter.isWhitelistedForCollateral(address(EUROC), WHALE_AGEUR), true);
        assertEq(transmuter.isWhitelistedForCollateral(address(BC3M), WHALE_AGEUR), true);
        assertEq(
            transmuter.isWhitelistedForCollateral(address(EUROC), 0xB00b1E53909F8253783D8e54AEe462f99bAcb435),
            true
        );
        assertEq(
            transmuter.isWhitelistedForCollateral(address(BC3M), 0xB00b1E53909F8253783D8e54AEe462f99bAcb435),
            true
        );
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        ORACLE                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testUnit_Upgrade_getOracleValues_Success() external {
        _checkOracleValues(address(EUROC), BASE_18, FIREWALL_MINT_EUROC, FIREWALL_BURN_EUROC);
        _checkOracleValues(address(BC3M), (11944 * BASE_18) / 100, FIREWALL_MINT_BC3M, FIREWALL_BURN_BC3M);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         MINT                                                       
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_Upgrade_QuoteMintExactInput_Reflexivity(uint256 amountIn, uint256 fromToken) public {
        fromToken = bound(fromToken, 0, transmuter.getCollateralList().length - 1);
        address collateral = transmuter.getCollateralList()[fromToken];
        amountIn = bound(amountIn, BASE_6, collateral == BC3M ? 1000 * BASE_18 : BASE_6 * 1e6);

        uint256 amountStable = transmuter.quoteIn(amountIn, collateral, address(agEUR));
        uint256 amountInReflexive = transmuter.quoteOut(amountStable, collateral, address(agEUR));
        assertApproxEqRel(amountIn, amountInReflexive, BPS * 10);
    }

    function testFuzz_Upgrade_QuoteMintExactInput_Independant(
        uint256 amountIn,
        uint256 splitProportion,
        uint256 fromToken
    ) public {
        fromToken = bound(fromToken, 0, transmuter.getCollateralList().length - 1);
        address collateral = transmuter.getCollateralList()[fromToken];
        amountIn = bound(amountIn, BASE_6, collateral == BC3M ? 1000 * BASE_18 : BASE_6 * 1e6);
        splitProportion = bound(splitProportion, 0, BASE_9);

        uint256 amountStable = transmuter.quoteIn(amountIn, collateral, address(agEUR));
        uint256 amountInSplit1 = (amountIn * splitProportion) / BASE_9;
        amountInSplit1 = amountInSplit1 == 0 ? 1 : amountInSplit1;
        uint256 amountStableSplit1 = transmuter.quoteIn(amountInSplit1, collateral, address(agEUR));
        // do the swap to update the system
        _mintExactInput(alice, collateral, amountInSplit1, amountStableSplit1);
        uint256 amountStableSplit2 = transmuter.quoteIn(amountIn - amountInSplit1, collateral, address(agEUR));
        assertApproxEqRel(amountStableSplit1 + amountStableSplit2, amountStable, BPS * 10);
    }

    function testFuzz_Upgrade_MintExactOutput(uint256 stableAmount, uint256 fromToken) public {
        fromToken = bound(fromToken, 0, transmuter.getCollateralList().length - 1);
        address collateral = transmuter.getCollateralList()[fromToken];
        stableAmount = bound(stableAmount, BASE_18, BASE_6 * 1e18);

        uint256 prevBalanceStable = agEUR.balanceOf(alice);
        uint256 prevTransmuterCollat = IERC20(collateral).balanceOf(address(transmuter));
        uint256 prevAgTokenSupply = IERC20(agEUR).totalSupply();
        (uint256 prevStableAmountCollat, uint256 prevStableAmount) = transmuter.getIssuedByCollateral(collateral);

        uint256 amountIn = transmuter.quoteOut(stableAmount, collateral, address(agEUR));
        if (amountIn == 0 || stableAmount == 0) return;
        _mintExactOutput(alice, collateral, stableAmount, amountIn);

        uint256 balanceStable = agEUR.balanceOf(alice);

        assertEq(balanceStable, prevBalanceStable + stableAmount);
        assertEq(agEUR.totalSupply(), prevAgTokenSupply + stableAmount);
        assertEq(IERC20(collateral).balanceOf(alice), 0);
        assertEq(IERC20(collateral).balanceOf(address(transmuter)), prevTransmuterCollat + amountIn);

        (uint256 newStableAmountCollat, uint256 newStableAmount) = transmuter.getIssuedByCollateral(collateral);

        assertApproxEqAbs(newStableAmountCollat, prevStableAmountCollat + stableAmount, 1 wei);
        assertApproxEqAbs(newStableAmount, prevStableAmount + stableAmount, 1 wei);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         BURN                                                       
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_Upgrade_QuoteBurnExactInput_Reflexivity(uint256 amountStable, uint256 fromToken) public {
        fromToken = bound(fromToken, 0, transmuter.getCollateralList().length - 1);
        address collateral = transmuter.getCollateralList()[fromToken];
        amountStable = bound(amountStable, BASE_18, BASE_6 * 1e18);

        uint256 amountOut = transmuter.quoteIn(amountStable, address(agEUR), collateral);
        uint256 amountStableReflexive = transmuter.quoteOut(amountOut, address(agEUR), collateral);
        assertApproxEqRel(amountStable, amountStableReflexive, BPS * 10);
    }

    function testFuzz_Upgrade_QuoteBurnExactInput_Independant(
        uint256 amountStable,
        uint256 splitProportion,
        uint256 fromToken
    ) public {
        fromToken = bound(fromToken, 0, transmuter.getCollateralList().length - 1);
        address collateral = transmuter.getCollateralList()[fromToken];
        amountStable = bound(amountStable, BASE_18, BASE_6 * 1e18);
        splitProportion = bound(splitProportion, 0, BASE_9);

        uint256 amountOut = transmuter.quoteIn(amountStable, address(agEUR), collateral);
        uint256 amountStableSplit1 = (amountStable * splitProportion) / BASE_9;
        amountStableSplit1 = amountStableSplit1 == 0 ? 1 : amountStableSplit1;
        uint256 amountOutSplit1 = transmuter.quoteIn(amountStableSplit1, address(agEUR), collateral);
        // do the swap to update the system
        _burnExactInput(WHALE_AGEUR, collateral, amountStableSplit1, amountOutSplit1);
        uint256 amountOutSplit2 = transmuter.quoteIn(amountStable - amountStableSplit1, address(agEUR), collateral);
        assertApproxEqRel(amountOutSplit1 + amountOutSplit2, amountOut, BPS * 10);
    }

    function testFuzz_Upgrade_BurnExactOutput(uint256 amountOut, uint256 fromToken) public {
        fromToken = bound(fromToken, 0, transmuter.getCollateralList().length - 1);
        address collateral = transmuter.getCollateralList()[fromToken];
        amountOut = bound(amountOut, BASE_6, collateral == BC3M ? 1000 * BASE_18 : BASE_6 * 1e6);

        uint256 prevBalanceStable = agEUR.balanceOf(WHALE_AGEUR);
        uint256 prevTransmuterCollat = IERC20(collateral).balanceOf(address(transmuter));
        uint256 prevAgTokenSupply = IERC20(agEUR).totalSupply();
        (uint256 prevStableAmountCollat, uint256 prevStableAmount) = transmuter.getIssuedByCollateral(collateral);

        uint256 stableAmount = transmuter.quoteOut(amountOut, address(agEUR), collateral);
        if (amountOut == 0 || stableAmount == 0) return;
        _burnExactOutput(WHALE_AGEUR, collateral, amountOut, stableAmount);

        uint256 balanceStable = agEUR.balanceOf(WHALE_AGEUR);

        assertEq(balanceStable, prevBalanceStable - stableAmount);
        assertEq(agEUR.totalSupply(), prevAgTokenSupply - stableAmount);
        assertEq(IERC20(collateral).balanceOf(WHALE_AGEUR), amountOut);
        assertEq(IERC20(collateral).balanceOf(address(transmuter)), prevTransmuterCollat - amountOut);

        (uint256 newStableAmountCollat, uint256 newStableAmount) = transmuter.getIssuedByCollateral(collateral);

        assertApproxEqAbs(newStableAmountCollat, prevStableAmountCollat - stableAmount, 1 wei);
        assertApproxEqAbs(newStableAmount, prevStableAmount - stableAmount, 1 wei);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        REDEEM                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testFuzz_Upgrade_QuoteRedeemRandomFees(uint256[3] memory latestOracleValue) public {
        (uint64 collatRatio, ) = transmuter.getCollateralRatio();
        uint256 amountBurnt = agEUR.balanceOf(WHALE_AGEUR);
        vm.prank(WHALE_AGEUR);
        (address[] memory tokens, uint256[] memory amounts) = transmuter.quoteRedemptionCurve(amountBurnt);

        // compute fee at current collatRatio
        assertEq(tokens.length, 2);
        assertEq(tokens.length, amounts.length);
        assertEq(tokens[0], address(EUROC));
        assertEq(tokens[1], address(BC3M));
        uint64 fee;
        (uint64[] memory xFeeRedeem, int64[] memory yFeeRedeem) = transmuter.getRedemptionFees();
        if (collatRatio >= BASE_9) fee = uint64(yFeeRedeem[yFeeRedeem.length - 1]);
        else fee = uint64(LibHelpers.piecewiseLinear(collatRatio, xFeeRedeem, yFeeRedeem));
        uint256 mintedStables = transmuter.getTotalIssued();
        _assertQuoteAmounts(collatRatio, mintedStables, amountBurnt, fee, amounts);

        uint256 balanceEURC = IERC20(EUROC).balanceOf(address(WHALE_AGEUR));
        uint256 balanceBC3M = IERC20(BC3M).balanceOf(address(WHALE_AGEUR));
        uint256 balanceAgToken = agEUR.balanceOf(WHALE_AGEUR);
        uint256[] memory minAmountOuts = new uint256[](2);

        vm.prank(WHALE_AGEUR);
        transmuter.redeem(amountBurnt, WHALE_AGEUR, block.timestamp + 1000, minAmountOuts);
        assertEq(IERC20(EUROC).balanceOf(address(WHALE_AGEUR)), balanceEURC + amounts[0]);
        assertEq(IERC20(BC3M).balanceOf(address(WHALE_AGEUR)), balanceBC3M + amounts[1]);
        assertEq(agEUR.balanceOf(WHALE_AGEUR), balanceAgToken - amountBurnt);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         UTILS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _mintExactOutput(
        address owner,
        address tokenIn,
        uint256 amountStable,
        uint256 estimatedAmountIn
    ) internal {
        vm.startPrank(owner);
        deal(tokenIn, owner, estimatedAmountIn);
        IERC20(tokenIn).approve(address(transmuter), type(uint256).max);
        transmuter.swapExactOutput(
            amountStable,
            estimatedAmountIn,
            tokenIn,
            address(agEUR),
            owner,
            block.timestamp * 2
        );
        vm.stopPrank();
    }

    function _mintExactInput(address owner, address tokenIn, uint256 amountIn, uint256 estimatedStable) internal {
        vm.startPrank(owner);
        deal(tokenIn, owner, amountIn);
        IERC20(tokenIn).approve(address(transmuter), type(uint256).max);
        transmuter.swapExactInput(amountIn, estimatedStable, tokenIn, address(agEUR), owner, block.timestamp * 2);
        vm.stopPrank();
    }

    function _burnExactInput(
        address owner,
        address tokenOut,
        uint256 amountStable,
        uint256 estimatedAmountOut
    ) internal returns (bool burnMoreThanHad) {
        // we need to increase the balance because fees are negative and we need to transfer
        // more than what we received with the mint
        if (IERC20(tokenOut).balanceOf(address(transmuter)) < estimatedAmountOut) {
            deal(tokenOut, address(transmuter), estimatedAmountOut);
            burnMoreThanHad = true;
        }

        vm.startPrank(owner);
        transmuter.swapExactInput(amountStable, estimatedAmountOut, address(agEUR), tokenOut, owner, 0);
        vm.stopPrank();
    }

    function _burnExactOutput(
        address owner,
        address tokenOut,
        uint256 amountOut,
        uint256 estimatedStable
    ) internal returns (bool) {
        // _logIssuedCollateral();
        vm.startPrank(owner);
        (uint256 maxAmount, ) = transmuter.getIssuedByCollateral(tokenOut);
        uint256 balanceStableOwner = agEUR.balanceOf(owner);
        if (estimatedStable > maxAmount) vm.expectRevert();
        else if (estimatedStable > balanceStableOwner) vm.expectRevert("ERC20: burn amount exceeds balance");
        transmuter.swapExactOutput(amountOut, estimatedStable, address(agEUR), tokenOut, owner, block.timestamp * 2);
        if (amountOut > maxAmount) return false;
        vm.stopPrank();
        return true;
    }

    function _assertQuoteAmounts(
        uint64 collatRatio,
        uint256 mintedStables,
        uint256 amountBurnt,
        uint64 fee,
        uint256[] memory amounts
    ) internal {
        uint256 amountInValueReceived;
        {
            (, , , , uint256 redemptionPrice) = transmuter.getOracleValues(address(EUROC));
            amountInValueReceived += (redemptionPrice * amounts[0]) / 10 ** 6;
        }
        {
            (, , , , uint256 redemptionPrice) = transmuter.getOracleValues(address(BC3M));
            amountInValueReceived += (redemptionPrice * amounts[1]) / 10 ** 18;
        }

        uint256 denom = (mintedStables * BASE_9);
        uint256 valueCheck = (collatRatio * amountBurnt * fee) / BASE_18;
        if (collatRatio >= BASE_9) {
            denom = (mintedStables * collatRatio);
            // for rounding errors
            assertLe(amountInValueReceived, amountBurnt + 1);
            valueCheck = (amountBurnt * fee) / BASE_9;
        }
        assertApproxEqAbs(
            amounts[0],
            (IERC20(EUROC).balanceOf(address(transmuter)) * amountBurnt * fee) / denom,
            1 wei
        );
        assertApproxEqAbs(amounts[1], (IERC20(BC3M).balanceOf(address(transmuter)) * amountBurnt * fee) / denom, 1 wei);
        if (collatRatio < BASE_9) {
            assertLe(amountInValueReceived, (collatRatio * amountBurnt) / BASE_9 + 1);
        }
        assertApproxEqRel(amountInValueReceived, valueCheck, BPS * 10);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        CHECKS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _checkOracleValues(
        address collateral,
        uint256 targetValue,
        uint128 firewallMint,
        uint128 firewallBurn
    ) internal {
        (uint256 mint, uint256 burn, uint256 ratio, uint256 minRatio, uint256 redemption) = transmuter.getOracleValues(
            collateral
        );
        assertApproxEqRel(targetValue, redemption, 100 * BPS);
        assertEq(burn, redemption);
        if (redemption * BASE_18 < targetValue * (BASE_18 - firewallBurn)) {
            assertEq(mint, redemption);
            assertEq(ratio, (redemption * BASE_18) / targetValue);
        } else if (redemption < targetValue) {
            assertEq(mint, redemption);
            assertEq(ratio, BASE_18);
        } else if (redemption * BASE_18 < targetValue * ((BASE_18 + firewallMint))) {
            assertEq(mint, redemption);
            assertEq(ratio, BASE_18);
        } else {
            assertEq(mint, targetValue);
            assertEq(ratio, BASE_18);
        }
    }
}
