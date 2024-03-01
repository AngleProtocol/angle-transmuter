// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { stdJson } from "forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";

import { BC3M, BPS, EUROC } from "../../scripts/Constants.s.sol";

import { Helpers } from "../../scripts/Helpers.s.sol";
import "contracts/utils/Errors.sol" as Errors;
import "contracts/transmuter/Storage.sol" as Storage;
import { Getters } from "contracts/transmuter/facets/Getters.sol";
import { Oracle } from "contracts/transmuter/facets/Oracle.sol";
import { Redeemer } from "contracts/transmuter/facets/Redeemer.sol";
import { SettersGovernor } from "contracts/transmuter/facets/SettersGovernor.sol";
import { SettersGuardian } from "contracts/transmuter/facets/SettersGuardian.sol";
import { Swapper } from "contracts/transmuter/facets/Swapper.sol";
import { ITransmuter } from "interfaces/ITransmuter.sol";
import "utils/src/Constants.sol";

interface OldTransmuter {
    function getOracle(address)
        external
        view
        returns (
            Storage.OracleReadType,
            Storage.OracleReadType,
            bytes memory,
            bytes memory
        );
}

contract TransmuterUpdateFacets is Helpers, Test {
    using stdJson for string;

    uint128 constant FIREWALL_MINT_EUROC = 0;
    uint128 constant FIREWALL_BURN_EUROC = uint128(5 * BPS);
    uint128 constant FIREWALL_MINT_BC3M = uint128(BASE_18);
    uint128 constant FIREWALL_BURN_BC3M = uint128(100 * BPS);
    uint96 constant DEVIATION_THRESHOLD_BC3M = uint96(100 * BPS);
    uint32 constant HEARTBEAT = uint32(1 days);

    uint256 public CHAIN_SOURCE;

    string[] replaceFacetNames;
    string[] addFacetNames;
    address[] facetAddressList;

    ITransmuter transmuter;
    address governor;

    function setUp() public override {
        super.setUp();

        CHAIN_SOURCE = CHAIN_ETHEREUM;

        vm.selectFork(forkIdentifier[CHAIN_SOURCE]);

        governor = _chainToContract(CHAIN_SOURCE, ContractType.Timelock);
        transmuter = ITransmuter(_chainToContract(CHAIN_SOURCE, ContractType.TransmuterAgEUR));
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
        transmuter.setOracle(
            EUROC,
            abi.encode(
                oracleTypeEUROC,
                targetTypeEUROC,
                oracleDataEUROC,
                targetDataEUROC,
                abi.encode(FIREWALL_MINT_EUROC, FIREWALL_BURN_EUROC)
            )
        );

        transmuter.setOracle(
            BC3M,
            abi.encode(
                oracleTypeBC3M,
                Storage.OracleReadType.MAX,
                oracleDataBC3M,
                abi.encode(currentBC3MPrice, DEVIATION_THRESHOLD_BC3M, uint96(block.timestamp), HEARTBEAT),
                abi.encode(FIREWALL_MINT_BC3M, FIREWALL_BURN_BC3M)
            )
        );

        vm.stopPrank();
    }

    function testUnit_getOracleValues_Success() external {
        _checkOracleValues(address(EUROC), BASE_18, FIREWALL_MINT_EUROC, FIREWALL_BURN_EUROC);
        _checkOracleValues(address(BC3M), (11944 * BASE_18) / 100, FIREWALL_MINT_BC3M, FIREWALL_BURN_BC3M);
    }

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
