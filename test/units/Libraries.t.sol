// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";

import { stdError } from "forge-std/Test.sol";

import "mock/MockManager.sol";
import { IERC20Metadata } from "mock/MockTokenPermit.sol";
import { MockLib } from "mock/MockLib.sol";
import "contracts/transmuter/Storage.sol";

import "contracts/utils/Errors.sol" as Errors;

import "../Fixture.sol";
import "../utils/FunctionUtils.sol";

contract LibrariesTest is Fixture {
    MockLib mockLib;
    MockManager manager;

    function setUp() public override {
        mockLib = new MockLib();
        manager = new MockManager(address(eurA));

        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    LIBHELPERS TEST                                                 
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function test_ConvertDecimalTo() public {
        assertEq(mockLib.convertDecimalTo(100, 18, 18), 100);
        assertEq(mockLib.convertDecimalTo(100, 19, 18), 10);
        assertEq(mockLib.convertDecimalTo(100, 18, 19), 1000);
        assertEq(mockLib.convertDecimalTo(100, 18, 23), 10000000);
        assertEq(mockLib.convertDecimalTo(100, 23, 18), 0);
    }

    function test_CheckList() public {
        address[] memory tokens = new address[](3);
        tokens[0] = alice;
        tokens[1] = bob;
        tokens[2] = charlie;
        assertEq(mockLib.checkList(alice, tokens), 0);
        assertEq(mockLib.checkList(bob, tokens), 1);
        assertEq(mockLib.checkList(charlie, tokens), 2);
        assertEq(mockLib.checkList(governor, tokens), -1);
    }

    function test_FindLowerBound() public {
        uint64[] memory array0;
        assertEq(mockLib.findLowerBound(true, array0, 1, 5), 0);
        uint64[] memory array1 = new uint64[](3);
        array1[0] = 1;
        array1[1] = 2;
        array1[2] = 4;
        assertEq(mockLib.findLowerBound(true, array1, 1, 6), 2);
        assertEq(mockLib.findLowerBound(true, array1, 1, 5), 2);
        assertEq(mockLib.findLowerBound(true, array1, 1, 4), 2);
        assertEq(mockLib.findLowerBound(true, array1, 1, 3), 1);
        assertEq(mockLib.findLowerBound(true, array1, 1, 2), 1);
        assertEq(mockLib.findLowerBound(true, array1, 1, 1), 0);
        assertEq(mockLib.findLowerBound(true, array1, 1, 0), 0);
        uint64[] memory array2 = new uint64[](3);
        array2[0] = 6;
        array2[1] = 4;
        array2[2] = 3;
        assertEq(mockLib.findLowerBound(false, array2, 1, 7), 0);
        assertEq(mockLib.findLowerBound(false, array2, 1, 6), 0);
        assertEq(mockLib.findLowerBound(false, array2, 1, 5), 0);
        assertEq(mockLib.findLowerBound(false, array2, 1, 4), 1);
        assertEq(mockLib.findLowerBound(false, array2, 1, 3), 2);
        assertEq(mockLib.findLowerBound(false, array2, 1, 2), 2);
        assertEq(mockLib.findLowerBound(false, array2, 1, 1), 2);
        assertEq(mockLib.findLowerBound(false, array2, 1, 0), 2);
    }

    function test_PiecewiseLinear() public {
        uint64[] memory xArray0 = new uint64[](1);
        int64[] memory yArray0 = new int64[](1);
        xArray0[0] = 1;
        yArray0[0] = 2;
        assertEq(mockLib.piecewiseLinear(3, xArray0, yArray0), 2);
        assertEq(mockLib.piecewiseLinear(0, xArray0, yArray0), 2);
        assertEq(mockLib.piecewiseLinear(2, xArray0, yArray0), 2);
        uint64[] memory xArray1 = new uint64[](3);
        int64[] memory yArray1 = new int64[](3);
        xArray1[0] = 1;
        xArray1[1] = 3;
        xArray1[2] = 5;
        yArray1[0] = 1;
        yArray1[1] = 3;
        yArray1[2] = 7;
        assertEq(mockLib.piecewiseLinear(4, xArray1, yArray1), 5);
        assertEq(mockLib.piecewiseLinear(3, xArray1, yArray1), 3);
        assertEq(mockLib.piecewiseLinear(2, xArray1, yArray1), 2);
        assertEq(mockLib.piecewiseLinear(1, xArray1, yArray1), 1);
        assertEq(mockLib.piecewiseLinear(5, xArray1, yArray1), 7);
        assertEq(mockLib.piecewiseLinear(6, xArray1, yArray1), 7);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                   LIBSTORAGE TESTS                                                
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function test_CorrectImplementationStorage() public {
        ImplementationStorage memory ims = mockLib.implementationStorage();

        assertEq(ims.implementation, address(0));
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                   LIBMANAGER TESTS                                                 
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function test_TransferRecipient() public {
        bytes memory config = abi.encode(ManagerType.EXTERNAL, abi.encode(IManager(address(manager))));

        assertEq(mockLib.transferRecipient(config), address(manager));

        bytes memory invalidConfig = abi.encode(1, abi.encode(IManager(address(manager))));

        vm.expectRevert();
        mockLib.transferRecipient(invalidConfig);
    }

    function test_TotalAssets() public {
        // Tested elsewhere, for the sake of Forge coverage here
        bytes memory config = abi.encode(ManagerType.EXTERNAL, abi.encode(IManager(address(manager))));
        (uint256[] memory balances, uint256 totalValue) = mockLib.totalAssets(config);
        assertEq(balances.length, 0);
        assertEq(totalValue, 0);
    }

    function test_Invest() public {
        // Tested elsewhere, for the sake of Forge coverage here
        bytes memory config = abi.encode(ManagerType.EXTERNAL, abi.encode(IManager(address(manager))));
        mockLib.invest(0, config);
    }

    function test_MaxAvailable() public {
        MockManager manager2 = new MockManager(address(eurA));
        deal(address(eurA), address(manager2), 500);
        bytes memory config = abi.encode(ManagerType.EXTERNAL, abi.encode(IManager(address(manager2))));
        assertEq(mockLib.maxAvailable(config), 500);
    }
}
