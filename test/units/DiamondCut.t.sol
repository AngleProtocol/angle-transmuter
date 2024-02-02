// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import { IMockFacet, MockPureFacet, MockWriteFacet, MockWriteExpanded, MockInitializer, DiamondProxy } from "mock/MockFacets.sol";

import "contracts/transmuter/Storage.sol";
import { Test } from "contracts/transmuter/configs/Test.sol";
import { DiamondCut } from "contracts/transmuter/facets/DiamondCut.sol";
import { LibDiamond } from "contracts/transmuter/libraries/LibDiamond.sol";
import "contracts/utils/Constants.sol";
import "contracts/utils/Errors.sol" as Errors;

import { Fixture } from "../Fixture.sol";

struct FacetCutAux {
    address facetAddress;
    uint8 action;
    bytes4[] functionSelectors;
}

interface DiamondCutAux {
    function diamondCut(FacetCutAux[] calldata _diamondCut, address _init, bytes calldata _calldata) external;
}

contract Test_DiamondCut is Fixture {
    address pureFacet = address(new MockPureFacet());
    address writeFacet = address(new MockWriteFacet());
    address writeExpandedFacet = address(new MockWriteExpanded());
    address initializer = address(new MockInitializer());
    bytes4[] selectors = _generateSelectors("IMockFacet");

    function test_RevertWhen_NotGovernor() public {
        FacetCut[] memory facetCut = new FacetCut[](1);
        facetCut[0] = FacetCut({
            facetAddress: address(pureFacet),
            action: FacetCutAction.Add,
            functionSelectors: selectors
        });

        vm.expectRevert(Errors.NotGovernor.selector);

        hoax(guardian);
        transmuter.diamondCut(facetCut, address(0x0), "");
    }

    function test_RevertWhen_NoSelectorsProvidedForFacetForCut() public {
        FacetCut[] memory facetCut = new FacetCut[](1);

        facetCut[0] = FacetCut({
            facetAddress: address(pureFacet),
            action: FacetCutAction.Add,
            functionSelectors: new bytes4[](0)
        });

        vm.expectRevert(abi.encodeWithSelector(Errors.NoSelectorsProvidedForFacetForCut.selector, pureFacet));

        hoax(governor);
        transmuter.diamondCut(facetCut, address(0x0), "");
    }

    function test_RevertWhen_IncorrectFacetCutAction() public {
        FacetCutAux[] memory facetCut = new FacetCutAux[](1);

        facetCut[0] = FacetCutAux({
            facetAddress: address(pureFacet),
            action: uint8(4),
            functionSelectors: new bytes4[](0)
        });

        vm.expectRevert(bytes("")); // Reverts with a Panic code

        hoax(governor);
        DiamondCutAux(address(transmuter)).diamondCut(facetCut, address(0x0), "");
    }

    function test_RevertWhen_InitializerHasNoCode() public {
        FacetCut[] memory facetCut = new FacetCut[](1);
        facetCut[0] = FacetCut({
            facetAddress: address(pureFacet),
            action: FacetCutAction.Add,
            functionSelectors: selectors
        });

        vm.expectRevert(Errors.ContractHasNoCode.selector);

        hoax(governor);
        transmuter.diamondCut(facetCut, address(1), "");
    }

    function test_RevertWhen_InitializerRevert() public {
        FacetCut[] memory facetCut = new FacetCut[](1);
        facetCut[0] = FacetCut({
            facetAddress: address(pureFacet),
            action: FacetCutAction.Add,
            functionSelectors: selectors
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InitializationFunctionReverted.selector,
                initializer,
                abi.encodeWithSelector(MockInitializer.initializeRevert.selector)
            )
        );

        hoax(governor);
        transmuter.diamondCut(facetCut, initializer, abi.encodeWithSelector(MockInitializer.initializeRevert.selector));
    }

    function test_RevertWhen_InitializerRevertWithMessage() public {
        FacetCut[] memory facetCut = new FacetCut[](1);
        facetCut[0] = FacetCut({
            facetAddress: address(pureFacet),
            action: FacetCutAction.Add,
            functionSelectors: selectors
        });

        vm.expectRevert(MockInitializer.CustomError.selector);

        hoax(governor);
        transmuter.diamondCut(
            facetCut,
            initializer,
            abi.encodeWithSelector(MockInitializer.initializeRevertWithMessage.selector)
        );
    }

    function test_RevertWhen_AddToZeroAddress() public {
        FacetCut[] memory facetCut = new FacetCut[](1);
        facetCut[0] = FacetCut({ facetAddress: address(0), action: FacetCutAction.Add, functionSelectors: selectors });

        vm.expectRevert(abi.encodeWithSelector(Errors.CannotAddSelectorsToZeroAddress.selector, selectors));

        hoax(governor);
        transmuter.diamondCut(facetCut, address(0), "");
    }

    function test_RevertWhen_AddAlreadyExistingSelector() public {
        FacetCut[] memory facetCut = new FacetCut[](1);
        facetCut[0] = FacetCut({
            facetAddress: address(pureFacet),
            action: FacetCutAction.Add,
            functionSelectors: selectors
        });

        hoax(governor);
        transmuter.diamondCut(facetCut, address(0x0), "");

        facetCut[0] = FacetCut({
            facetAddress: address(writeFacet),
            action: FacetCutAction.Add,
            functionSelectors: selectors
        });

        vm.expectRevert(
            abi.encodeWithSelector(Errors.CannotAddFunctionToDiamondThatAlreadyExists.selector, selectors[0])
        );

        hoax(governor);
        transmuter.diamondCut(facetCut, address(0), "");
    }

    function test_RevertWhen_ReplaceFromZeroAddress() public {
        FacetCut[] memory facetCut = new FacetCut[](1);
        facetCut[0] = FacetCut({
            facetAddress: address(0),
            action: FacetCutAction.Replace,
            functionSelectors: selectors
        });

        vm.expectRevert(
            abi.encodeWithSelector(Errors.CannotReplaceFunctionsFromFacetWithZeroAddress.selector, selectors)
        );

        hoax(governor);
        transmuter.diamondCut(facetCut, address(0), "");
    }

    function test_RevertWhen_ReplaceImmutableFunction() public {
        DiamondProxy diamondImmutable = new DiamondProxy();
        diamondImmutable.initialize();

        bytes4[] memory functionSelectors = new bytes4[](1);
        functionSelectors[0] = DiamondProxy.diamondCut.selector;

        // Trying to replace `diamondCut`
        FacetCut[] memory facetCut = new FacetCut[](1);
        facetCut[0] = FacetCut({
            facetAddress: address(diamondImmutable),
            action: FacetCutAction.Replace,
            functionSelectors: functionSelectors
        });

        vm.expectRevert(abi.encodeWithSelector(Errors.CannotReplaceImmutableFunction.selector, functionSelectors[0]));

        hoax(governor);
        diamondImmutable.diamondCut(facetCut, address(0), "");
    }

    function test_RevertWhen_ReplaceWithoutChange() public {
        FacetCut[] memory facetCut = new FacetCut[](1);
        facetCut[0] = FacetCut({
            facetAddress: address(pureFacet),
            action: FacetCutAction.Add,
            functionSelectors: selectors
        });

        hoax(governor);
        transmuter.diamondCut(facetCut, address(0x0), "");

        facetCut[0] = FacetCut({
            facetAddress: address(pureFacet),
            action: FacetCutAction.Replace,
            functionSelectors: selectors
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.CannotReplaceFunctionWithTheSameFunctionFromTheSameFacet.selector,
                selectors[0]
            )
        );

        hoax(governor);
        transmuter.diamondCut(facetCut, address(0), "");
    }

    function test_RevertWhen_ReplaceFunctionThatDoesNotExists() public {
        FacetCut[] memory facetCut = new FacetCut[](1);
        facetCut[0] = FacetCut({
            facetAddress: address(pureFacet),
            action: FacetCutAction.Replace,
            functionSelectors: selectors
        });

        vm.expectRevert(abi.encodeWithSelector(Errors.CannotReplaceFunctionThatDoesNotExists.selector, selectors[0]));

        hoax(governor);
        transmuter.diamondCut(facetCut, address(0), "");
    }

    function test_RevertWhen_RemoveFacetAddressMustBeZeroAddress() public {
        FacetCut[] memory facetCut = new FacetCut[](1);
        facetCut[0] = FacetCut({
            facetAddress: address(pureFacet),
            action: FacetCutAction.Remove,
            functionSelectors: selectors
        });

        vm.expectRevert(abi.encodeWithSelector(Errors.RemoveFacetAddressMustBeZeroAddress.selector, pureFacet));

        hoax(governor);
        transmuter.diamondCut(facetCut, address(0), "");
    }

    function test_RevertWhen_RemoveFunctionThatDoesNotExist() public {
        FacetCut[] memory facetCut = new FacetCut[](1);
        facetCut[0] = FacetCut({
            facetAddress: address(0),
            action: FacetCutAction.Remove,
            functionSelectors: selectors
        });

        vm.expectRevert(abi.encodeWithSelector(Errors.CannotRemoveFunctionThatDoesNotExist.selector, selectors[0]));

        hoax(governor);
        transmuter.diamondCut(facetCut, address(0), "");
    }

    function test_RevertWhen_RemoveImmutableFunction() public {
        DiamondProxy diamondImmutable = new DiamondProxy();
        diamondImmutable.initialize();

        bytes4[] memory functionSelectors = new bytes4[](1);
        functionSelectors[0] = DiamondProxy.diamondCut.selector;

        // Trying to replace `diamondCut`
        FacetCut[] memory facetCut = new FacetCut[](1);
        facetCut[0] = FacetCut({
            facetAddress: address(0),
            action: FacetCutAction.Remove,
            functionSelectors: functionSelectors
        });

        vm.expectRevert(abi.encodeWithSelector(Errors.CannotRemoveImmutableFunction.selector, functionSelectors[0]));

        hoax(governor);
        diamondImmutable.diamondCut(facetCut, address(0), "");
    }

    function test_AddSimplePureFacet() public {
        FacetCut[] memory facetCut = new FacetCut[](1);
        facetCut[0] = FacetCut({
            facetAddress: address(pureFacet),
            action: FacetCutAction.Add,
            functionSelectors: selectors
        });

        // Events
        vm.expectEmit(address(transmuter));
        emit LibDiamond.DiamondCut(facetCut, address(0x0), "");

        hoax(governor);
        transmuter.diamondCut(facetCut, address(0x0), "");

        assertEq(IMockFacet(address(transmuter)).newFunction(), 1);
        assertEq(IMockFacet(address(transmuter)).newFunction2(), 2);
    }

    function test_AddSimpleWriteFacet() public {
        FacetCut[] memory facetCut = new FacetCut[](1);
        facetCut[0] = FacetCut({
            facetAddress: address(writeFacet),
            action: FacetCutAction.Add,
            functionSelectors: selectors
        });

        // Event
        vm.expectEmit(address(transmuter));
        emit LibDiamond.DiamondCut(facetCut, address(0x0), "");

        hoax(governor);
        transmuter.diamondCut(facetCut, address(0x0), "");

        assertEq(IMockFacet(address(transmuter)).newFunction(), 0);
        assertEq(IMockFacet(address(transmuter)).newFunction2(), 1);
    }

    function test_AddWriteFacetWithInitializer() public {
        FacetCut[] memory facetCut = new FacetCut[](1);
        facetCut[0] = FacetCut({
            facetAddress: address(writeFacet),
            action: FacetCutAction.Add,
            functionSelectors: selectors
        });

        // Event
        vm.expectEmit(address(transmuter));
        emit LibDiamond.DiamondCut(facetCut, initializer, abi.encodeWithSelector(MockInitializer.initialize.selector));

        hoax(governor);
        transmuter.diamondCut(facetCut, initializer, abi.encodeWithSelector(MockInitializer.initialize.selector));

        assertEq(IMockFacet(address(transmuter)).newFunction(), 2); // 2 because of the initializer
        assertEq(IMockFacet(address(transmuter)).newFunction2(), 1);
    }

    function test_ReplaceReadWithWriteFacet() public {
        FacetCut[] memory facetCut = new FacetCut[](1);
        facetCut[0] = FacetCut({
            facetAddress: address(pureFacet),
            action: FacetCutAction.Add,
            functionSelectors: selectors
        });

        hoax(governor);
        transmuter.diamondCut(facetCut, address(0), "0x");

        assertEq(IMockFacet(address(transmuter)).newFunction(), 1);
        assertEq(IMockFacet(address(transmuter)).newFunction2(), 2);

        facetCut[0] = FacetCut({
            facetAddress: address(writeFacet),
            action: FacetCutAction.Replace,
            functionSelectors: selectors
        });

        // Event
        vm.expectEmit(address(transmuter));
        emit LibDiamond.DiamondCut(facetCut, address(0), "0x");

        hoax(governor);
        transmuter.diamondCut(facetCut, address(0), "0x");

        assertEq(IMockFacet(address(transmuter)).newFunction(), 0);
        assertEq(IMockFacet(address(transmuter)).newFunction2(), 1);
    }

    function test_ReplaceWriteWithExtendedWriteFacet() public {
        FacetCut[] memory facetCut = new FacetCut[](1);
        facetCut[0] = FacetCut({
            facetAddress: address(writeFacet),
            action: FacetCutAction.Add,
            functionSelectors: selectors
        });

        hoax(governor);
        transmuter.diamondCut(
            facetCut,
            address(initializer),
            abi.encodeWithSelector(MockInitializer.initialize.selector)
        );

        assertEq(IMockFacet(address(transmuter)).newFunction(), 2); // Slot 1 is 2 with the initializer
        assertEq(IMockFacet(address(transmuter)).newFunction2(), 1); // Slot 1 is now 1

        facetCut[0] = FacetCut({
            facetAddress: address(writeExpandedFacet),
            action: FacetCutAction.Replace,
            functionSelectors: selectors
        });

        // Event
        vm.expectEmit(address(transmuter));
        emit LibDiamond.DiamondCut(facetCut, address(0), "0x");

        hoax(governor);
        transmuter.diamondCut(facetCut, address(0), "0x");

        assertEq(IMockFacet(address(transmuter)).newFunction(), 1); // Slot 1 is still 2
        assertEq(IMockFacet(address(transmuter)).newFunction2(), 20); // Slot 2 is 20
    }

    function test_RemoveWriteFacet() public {
        FacetCut[] memory facetCut = new FacetCut[](1);
        facetCut[0] = FacetCut({
            facetAddress: address(writeFacet),
            action: FacetCutAction.Add,
            functionSelectors: selectors
        });

        hoax(governor);
        transmuter.diamondCut(
            facetCut,
            address(initializer),
            abi.encodeWithSelector(MockInitializer.initialize.selector)
        );

        assertEq(IMockFacet(address(transmuter)).newFunction(), 2); // Slot 1 is 2 with the initializer
        assertEq(IMockFacet(address(transmuter)).newFunction2(), 1); // Slot 1 is now 1

        facetCut[0] = FacetCut({
            facetAddress: address(0),
            action: FacetCutAction.Remove,
            functionSelectors: selectors
        });

        // Event
        vm.expectEmit(address(transmuter));
        emit LibDiamond.DiamondCut(facetCut, address(0), "0x");

        hoax(governor);
        transmuter.diamondCut(facetCut, address(0), "0x");

        vm.expectRevert(abi.encodeWithSelector(Errors.FunctionNotFound.selector, IMockFacet.newFunction.selector));
        IMockFacet(address(transmuter)).newFunction();
        vm.expectRevert(abi.encodeWithSelector(Errors.FunctionNotFound.selector, IMockFacet.newFunction2.selector));
        IMockFacet(address(transmuter)).newFunction2();
    }
}
