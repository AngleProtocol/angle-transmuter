// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { Utils, AssertUtils } from "../utils/Utils.s.sol";
import { console } from "forge-std/console.sol";
import { StdCheats } from "forge-std/Test.sol";
import { IERC20 } from "oz/token/ERC20/IERC20.sol";
import { ITransmuter } from "interfaces/ITransmuter.sol";
import { IAgToken } from "interfaces/IAgToken.sol";
import "stringutils/strings.sol";
import "../Constants.s.sol";
import "contracts/transmuter/Storage.sol" as Storage;

contract CheckTransmuterUSD is Utils, AssertUtils, StdCheats {
    using strings for *;

    // TODO: replace with deployed Transmuter address
    ITransmuter public constant transmuter = ITransmuter(0x712B29A840d717C5B1150f02cCaA01fedaD78F4c);
    address public AGEUR;

    function run() external {
        AGEUR = _chainToContract(CHAIN_SOURCE, ContractType.AgEUR);
        address stablecoin = address(transmuter.agToken());
        /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        FEE STRUCTURE                                                  
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

        address[] memory collaterals = new address[](1);
        collaterals[0] = USDC;

        /*
        // Checks all valid selectors are here
        bytes4[] memory selectors = _generateSelectors("ITransmuter");
        console.log("Num selectors: ", selectors.length);
        for (uint i = 0; i < selectors.length; ++i) {
            assertEq(transmuter.isValidSelector(selectors[i]), true);
        }
        */
        /*
        assertEq(address(transmuter.accessControlManager()), address(_chainToContract(CHAIN_SOURCE, ContractType.CoreBorrow)));
        assertEq(address(transmuter.agToken()), address(AGEUR));
        */
        assertEq(transmuter.getCollateralList(), collaterals);
        assertEq(transmuter.getCollateralDecimals(USDC), 6);

        {
            address collat = USDC;
            uint64[] memory xMintFeeUsdc = new uint64[](1);
            xMintFeeUsdc[0] = uint64(0);

            int64[] memory yMintFeeUsdc = new int64[](1);
            yMintFeeUsdc[0] = int64(0);

            uint64[] memory xBurnFeeUsdc = new uint64[](1);
            xBurnFeeUsdc[0] = uint64(BASE_9);

            int64[] memory yBurnFeeUsdc = new int64[](1);
            yBurnFeeUsdc[0] = int64(0);

            (uint64[] memory xRealFeeMint, int64[] memory yRealFeeMint) = transmuter.getCollateralMintFees(collat);
            _assertArrayUint64(xRealFeeMint, xMintFeeUsdc);
            _assertArrayInt64(yRealFeeMint, yMintFeeUsdc);
            (uint64[] memory xRealFeeBurn, int64[] memory yRealFeeBurn) = transmuter.getCollateralBurnFees(collat);
            _assertArrayUint64(xRealFeeBurn, xBurnFeeUsdc);
            _assertArrayInt64(yRealFeeBurn, yBurnFeeUsdc);
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

        assertEq(transmuter.isPaused(USDC, Storage.ActionType.Mint), false);
        assertEq(transmuter.isPaused(USDC, Storage.ActionType.Burn), false);
        assertEq(transmuter.isPaused(USDC, Storage.ActionType.Redeem), false);

        /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        ORACLES                                                     
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/
        {
            address collat = USDC;
            (uint256 mint, uint256 burn, uint256 ratio, uint256 minRatio, uint256 redemption) = transmuter
                .getOracleValues(collat);
            console.log("USDC oracle values");
            console.log(mint, burn, ratio);
            console.log(minRatio, redemption);
        }

        /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                  STABLECOINS MINTED                                                
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

        (uint64 collatRatio, uint256 stablecoinsIssued) = transmuter.getCollateralRatio();
        assertEq(stablecoinsIssued, 0);
        assertEq(collatRatio, type(uint64).max);

        /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                      TEST SWAPS                                                    
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

        console.log("quoteIn USDC Mint", transmuter.quoteIn(1000000, USDC, stablecoin));
        console.log("quoteOut USDC Mint", transmuter.quoteOut(BASE_18, USDC, stablecoin));
        vm.expectRevert();
        transmuter.quoteIn(BASE_18, address(stablecoin), USDC);
        vm.expectRevert();
        transmuter.quoteIn(BASE_18, address(stablecoin), USDC);

        uint256 deployerPrivateKey = vm.deriveKey(vm.envString("MNEMONIC_FORK"), "m/44'/60'/0'/0/", 0);
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);
        deal(USDC, deployer, BASE_6);
        console.log("deployer", deployer);

        IERC20(USDC).approve(address(transmuter), BASE_6);
        console.log("Balance stablecoin Pre", IERC20(stablecoin).balanceOf(deployer));
        console.log("Balance USDC Pre", IERC20(USDC).balanceOf(deployer));
        transmuter.swapExactInput(BASE_6, 0, USDC, address(stablecoin), deployer, type(uint256).max);
        console.log("Balance stablecoin Post Mint", IERC20(address(stablecoin)).balanceOf(deployer));
        console.log("Balance USDC Post Mint", IERC20(USDC).balanceOf(deployer));

        transmuter.swapExactInput(BASE_18 / 2, 0, address(stablecoin), USDC, deployer, type(uint256).max);
        console.log("Balance stablecoin Post Burn", IERC20(address(stablecoin)).balanceOf(deployer));
        console.log("Balance USDC Post Burn", IERC20(USDC).balanceOf(deployer));
        vm.stopBroadcast();
    }
}
