// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "../utils/Utils.s.sol";
import { console } from "forge-std/console.sol";
import { StdCheats } from "forge-std/Test.sol";
import { IERC20 } from "oz/token/ERC20/IERC20.sol";
import { ITransmuter } from "interfaces/ITransmuter.sol";
import { IAgToken } from "interfaces/IAgToken.sol";
import "stringutils/strings.sol";
import "../Constants.s.sol";
import "contracts/transmuter/Storage.sol" as Storage;

contract CheckTransmuter is Utils, StdCheats {
    using strings for *;

    // TODO: replace with deployed Transmuter address
    ITransmuter public constant transmuter = ITransmuter(0x1757a98c1333B9dc8D408b194B2279b5AFDF70Cc);

    function run() external {
        /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        FEE STRUCTURE                                                  
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

        address[] memory collaterals = new address[](2);
        collaterals[0] = EUROC;
        collaterals[1] = BC3M;

        /*
        // Checks all valid selectors are here
        bytes4[] memory selectors = _generateSelectors("ITransmuter");
        console.log("Num selectors: ", selectors.length);
        for (uint i = 0; i < selectors.length; ++i) {
            assertEq(transmuter.isValidSelector(selectors[i]), true);
        }
        */

        assertEq(
            address(transmuter.accessControlManager()),
            address(_chainToContract(CHAIN_ETHEREUM, ContractType.CoreBorrow))
        );
        assertEq(address(transmuter.agToken()), address(AGEUR));
        assertEq(transmuter.getCollateralList(), collaterals);
        assertEq(transmuter.getCollateralDecimals(EUROC), 6);
        assertEq(transmuter.getCollateralDecimals(BC3M), 18);

        {
            address collat = EUROC;
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
            (uint64[] memory xRealFeeMint, int64[] memory yRealFeeMint) = transmuter.getCollateralMintFees(collat);
            _assertArrayUint64(xRealFeeMint, xMintFeeEuroc);
            _assertArrayInt64(yRealFeeMint, yMintFeeEuroc);
            (uint64[] memory xRealFeeBurn, int64[] memory yRealFeeBurn) = transmuter.getCollateralBurnFees(collat);
            _assertArrayUint64(xRealFeeBurn, xBurnFeeEuroc);
            _assertArrayInt64(yRealFeeBurn, yBurnFeeEuroc);
        }

        {
            address collat = BC3M;
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
            (uint64[] memory xRealFeeMint, int64[] memory yRealFeeMint) = transmuter.getCollateralMintFees(collat);
            _assertArrayUint64(xRealFeeMint, xMintFeeC3M);
            _assertArrayInt64(yRealFeeMint, yMintFeeC3M);
            (uint64[] memory xRealFeeBurn, int64[] memory yRealFeeBurn) = transmuter.getCollateralBurnFees(collat);
            _assertArrayUint64(xRealFeeBurn, xBurnFeeC3M);
            _assertArrayInt64(yRealFeeBurn, yBurnFeeC3M);
        }
        {
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

            (uint64[] memory xRedemptionCurve, int64[] memory yRedemptionCurve) = transmuter.getRedemptionFees();
            _assertArrayUint64(xRedemptionCurve, xRedeemFee);
            _assertArrayInt64(yRedemptionCurve, yRedeemFee);
        }

        /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         PAUSE                                                      
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

        assertEq(transmuter.isPaused(EUROC, Storage.ActionType.Mint), false);
        assertEq(transmuter.isPaused(EUROC, Storage.ActionType.Burn), false);
        assertEq(transmuter.isPaused(EUROC, Storage.ActionType.Redeem), false);

        assertEq(transmuter.isPaused(BC3M, Storage.ActionType.Mint), false);
        assertEq(transmuter.isPaused(BC3M, Storage.ActionType.Burn), false);
        assertEq(transmuter.isPaused(BC3M, Storage.ActionType.Redeem), false);

        /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        ORACLES                                                     
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/
        {
            address collat = EUROC;
            (uint256 mint, uint256 burn, uint256 ratio, uint256 minRatio, uint256 redemption) = transmuter
                .getOracleValues(collat);
            console.log("EUROC oracle values");
            console.log(mint, burn, ratio);
            console.log(minRatio, redemption);
        }

        {
            address collat = BC3M;
            (uint256 mint, uint256 burn, uint256 ratio, uint256 minRatio, uint256 redemption) = transmuter
                .getOracleValues(collat);
            console.log("BC3M oracle values");
            console.log(mint, burn, ratio);
            console.log(minRatio, redemption);
        }

        /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                  STABLECOINS MINTED                                                
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

        (uint64 collatRatio, uint256 stablecoinsIssued) = transmuter.getCollateralRatio();
        assertEq(stablecoinsIssued, 13043780000000000000000000);
        assertEq(collatRatio, 0);

        /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                   WHITELIST STATUS                                                 
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

        assert(transmuter.isWhitelistedCollateral(BC3M));
        bytes memory whitelistData = abi.encode(
            Storage.WhitelistType.BACKED,
            abi.encode(address(0x4954c61984180868495D1a7Fb193b05a2cbd9dE3))
        );
        assertEq(transmuter.getCollateralWhitelistData(BC3M), whitelistData);
        // Choosing a random address here
        assert(!transmuter.isWhitelistedForCollateral(BC3M, EUROC));

        /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                      TEST SWAPS                                                    
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

        console.log("quoteIn EUROC Mint", transmuter.quoteIn(1000000, EUROC, address(AGEUR)));
        console.log("quoteIn C3M Mint", transmuter.quoteIn(BASE_18, BC3M, address(AGEUR)));
        console.log("quoteOut EUROC Mint", transmuter.quoteOut(BASE_18, EUROC, address(AGEUR)));
        console.log("quoteOut C3M Mint", transmuter.quoteOut(BASE_18, BC3M, address(AGEUR)));
        vm.expectRevert();
        transmuter.quoteIn(BASE_18, address(AGEUR), BC3M);
        vm.expectRevert();
        transmuter.quoteIn(BASE_18, address(AGEUR), EUROC);

        deal(BC3M, address(transmuter), 38445108900000000000000);
        deal(EUROC, address(transmuter), 9500000000000);

        console.log("quoteIn BC3M Burn", transmuter.quoteIn(BASE_18, address(AGEUR), BC3M));
        console.log("quoteIn EUROC Burn", transmuter.quoteIn(BASE_18, address(AGEUR), EUROC));

        deal(BC3M, address(transmuter), BASE_18);

        hoax(_chainToContract(CHAIN_ETHEREUM, ContractType.GovernorMultisig));
        IAgToken(address(_chainToContract(CHAIN_ETHEREUM, ContractType.TreasuryAgEUR))).addMinter(address(transmuter));
        uint256 deployerPrivateKey = vm.deriveKey(vm.envString("MNEMONIC_FORK"), "m/44'/60'/0'/0/", 0);
        address deployer = vm.addr(deployerPrivateKey);

        deal(BC3M, deployer, BASE_18);
        vm.startBroadcast(deployerPrivateKey);

        IERC20(BC3M).approve(address(transmuter), BASE_18);
        console.log("Balance AGEUR Pre", IERC20(address(AGEUR)).balanceOf(deployer));
        console.log("Balance BC3M Pre", IERC20(BC3M).balanceOf(deployer));
        transmuter.swapExactInput(BASE_18, 0, BC3M, address(AGEUR), deployer, type(uint256).max);
        console.log("Balance AGEUR Post Mint", IERC20(address(AGEUR)).balanceOf(deployer));
        console.log("Balance BC3M Post Mint", IERC20(BC3M).balanceOf(deployer));
        vm.expectRevert();
        // Not whitelisted
        transmuter.swapExactInput(BASE_18, 0, address(AGEUR), BC3M, deployer, type(uint256).max);

        transmuter.swapExactInput(BASE_18, 0, address(AGEUR), EUROC, deployer, type(uint256).max);
        console.log("Balance AGEUR Post Burn", IERC20(address(AGEUR)).balanceOf(deployer));
        console.log("Balance BC3M Post Burn", IERC20(BC3M).balanceOf(deployer));
        console.log("Balance EUROC Post Burn", IERC20(EUROC).balanceOf(deployer));
        vm.stopBroadcast();
    }
}
