// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { SafeERC20 } from "oz/token/ERC20/utils/SafeERC20.sol";

import { IPermit2, PermitTransferFrom, SignatureTransferDetails, TokenPermissions } from "interfaces/external/permit2/IPermit2.sol";

import { stdError } from "forge-std/Test.sol";

import "mock/MockManager.sol";
import { IERC20Metadata } from "mock/MockTokenPermit.sol";
import { Permit2, SignatureVerification } from "mock/Permit2.sol";

import "contracts/transmuter/Storage.sol";
import "contracts/utils/Errors.sol" as Errors;

import "../Fixture.sol";
import "../utils/FunctionUtils.sol";

contract Permit2Test is Fixture, FunctionUtils {
    Permit2 permit2;
    bytes32 DOMAIN_SEPARATOR;

    function setUp() public override {
        permit2 = Permit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

        Permit2 tempPermit2 = new Permit2();
        vm.etch(address(permit2), address(tempPermit2).code);

        DOMAIN_SEPARATOR = permit2.DOMAIN_SEPARATOR();

        super.setUp();

        hoax(alice);
        eurA.approve(address(permit2), type(uint256).max);
    }

    function test_RevertWhen_SwapExactInputWithPermit_InvalidSigner() public {
        deal(address(eurA), alice, BASE_6);
        uint256 amountIn = BASE_6;
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;

        PermitTransferFrom memory permit = PermitTransferFrom({
            permitted: TokenPermissions({ token: address(eurA), amount: amountIn }),
            nonce: nonce,
            deadline: deadline
        });
        bytes memory sig = getPermitTransferSignature(permit, 2, DOMAIN_SEPARATOR, address(transmuter));

        vm.expectRevert(SignatureVerification.InvalidSigner.selector);
        startHoax(alice);
        transmuter.swapExactInputWithPermit(BASE_6, 0, address(eurA), alice, deadline, abi.encode(nonce, sig));
    }

    function test_RevertWhen_SwapExactInputWithPermit_InvalidSender() public {
        deal(address(eurA), alice, BASE_6);
        uint256 amountIn = BASE_6;
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;

        PermitTransferFrom memory permit = PermitTransferFrom({
            permitted: TokenPermissions({ token: address(eurA), amount: amountIn }),
            nonce: nonce,
            deadline: deadline
        });
        bytes memory sig = getPermitTransferSignature(permit, 1, DOMAIN_SEPARATOR, address(transmuter));

        vm.expectRevert(SignatureVerification.InvalidSigner.selector);
        startHoax(bob);
        transmuter.swapExactInputWithPermit(BASE_6, 0, address(eurA), alice, deadline, abi.encode(nonce, sig));
    }

    function test_RevertWhen_SwapExactInputWithPermit_InvalidDeadline() public {
        deal(address(eurA), alice, BASE_6);
        uint256 amountIn = BASE_6;
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;

        PermitTransferFrom memory permit = PermitTransferFrom({
            permitted: TokenPermissions({ token: address(eurA), amount: amountIn }),
            nonce: nonce,
            deadline: deadline - 1
        });
        bytes memory sig = getPermitTransferSignature(permit, 1, DOMAIN_SEPARATOR, address(transmuter));

        vm.expectRevert(SignatureVerification.InvalidSigner.selector);
        startHoax(bob);
        transmuter.swapExactInputWithPermit(BASE_6, 0, address(eurA), alice, deadline, abi.encode(nonce, sig));
    }

    function test_RevertWhen_SwapExactInputWithPermit_InvalidNonce() public {
        deal(address(eurA), alice, BASE_6);
        uint256 amountIn = BASE_6;
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;

        PermitTransferFrom memory permit = PermitTransferFrom({
            permitted: TokenPermissions({ token: address(eurA), amount: amountIn }),
            nonce: nonce,
            deadline: deadline - 1
        });
        bytes memory sig = getPermitTransferSignature(permit, 1, DOMAIN_SEPARATOR, address(transmuter));

        vm.expectRevert(SignatureVerification.InvalidSigner.selector);
        startHoax(bob);
        transmuter.swapExactInputWithPermit(BASE_6, 0, address(eurA), alice, deadline, abi.encode(nonce + 1, sig));
    }

    function test_RevertWhen_SwapExactInputWithPermit_InvalidAmount() public {
        deal(address(eurA), alice, BASE_6);
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;

        PermitTransferFrom memory permit = PermitTransferFrom({
            permitted: TokenPermissions({ token: address(eurA), amount: 1 }),
            nonce: nonce,
            deadline: deadline
        });
        bytes memory sig = getPermitTransferSignature(permit, 1, DOMAIN_SEPARATOR, address(transmuter));

        vm.expectRevert(SignatureVerification.InvalidSigner.selector);
        startHoax(bob);
        transmuter.swapExactInputWithPermit(BASE_6, 0, address(eurA), alice, deadline, abi.encode(nonce, sig));
    }

    function test_RevertWhen_SwapExactOutputWithPermit_InvalidAmount() public {
        uint256 amountOut = BASE_18;
        uint256 amountInMax = (3 * BASE_6) / 2;
        uint256 amountIn = (3 * BASE_6) / 2 - 489899;
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;

        deal(address(eurA), alice, amountInMax);

        PermitTransferFrom memory permit = PermitTransferFrom({
            permitted: TokenPermissions({ token: address(eurA), amount: amountIn }),
            nonce: nonce,
            deadline: deadline
        });
        bytes memory sig = getPermitTransferSignature(permit, 1, DOMAIN_SEPARATOR, address(transmuter));

        vm.expectRevert(SignatureVerification.InvalidSigner.selector);
        startHoax(alice);
        transmuter.swapExactOutputWithPermit(
            amountOut,
            amountInMax,
            address(eurA),
            alice,
            deadline,
            abi.encode(nonce, sig)
        );
    }

    function test_SwapExactInputWithPermit() public {
        deal(address(eurA), alice, BASE_6);
        uint256 amountIn = BASE_6;
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;

        PermitTransferFrom memory permit = PermitTransferFrom({
            permitted: TokenPermissions({ token: address(eurA), amount: amountIn }),
            nonce: nonce,
            deadline: deadline
        });
        bytes memory sig = getPermitTransferSignature(permit, 1, DOMAIN_SEPARATOR, address(transmuter));

        startHoax(alice);
        transmuter.swapExactInputWithPermit(BASE_6, 0, address(eurA), alice, deadline, abi.encode(nonce, sig));

        assertEq(agToken.balanceOf(alice), BASE_27 / (BASE_9 + BASE_9 / 99));
        assertEq(eurA.balanceOf(alice), 0);
        assertEq(eurA.balanceOf(address(transmuter)), BASE_6);
    }

    function test_SwapExactOutputWithPermit() public {
        uint256 amountOut = BASE_18;
        uint256 amountInMax = (3 * BASE_6) / 2;
        uint256 amountIn = (3 * BASE_6) / 2 - 489899;
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;

        deal(address(eurA), alice, amountInMax);

        PermitTransferFrom memory permit = PermitTransferFrom({
            permitted: TokenPermissions({ token: address(eurA), amount: amountInMax }),
            nonce: nonce,
            deadline: deadline
        });
        bytes memory sig = getPermitTransferSignature(permit, 1, DOMAIN_SEPARATOR, address(transmuter));

        startHoax(alice);
        transmuter.swapExactOutputWithPermit(
            amountOut,
            amountInMax,
            address(eurA),
            alice,
            deadline,
            abi.encode(nonce, sig)
        );

        assertEq(agToken.balanceOf(alice), BASE_18);
        assertEq(eurA.balanceOf(alice), amountInMax - amountIn);
        assertEq(eurA.balanceOf(address(transmuter)), amountIn);
    }

    function test_SwapExactInputWithPermitAndManager() public {
        // Set manager
        MockManager manager = new MockManager(address(eurA));
        IERC20[] memory subCollaterals = new IERC20[](2);
        subCollaterals[0] = eurA;
        subCollaterals[1] = eurB;
        ManagerStorage memory data = ManagerStorage({
            subCollaterals: subCollaterals,
            config: abi.encode(ManagerType.EXTERNAL, abi.encode(manager))
        });
        manager.setSubCollaterals(data.subCollaterals, data.config);

        hoax(governor);
        transmuter.setCollateralManager(address(eurA), data);

        // Test
        deal(address(eurA), alice, BASE_6);
        uint256 amountIn = BASE_6;
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;

        PermitTransferFrom memory permit = PermitTransferFrom({
            permitted: TokenPermissions({ token: address(eurA), amount: amountIn }),
            nonce: nonce,
            deadline: deadline
        });
        bytes memory sig = getPermitTransferSignature(permit, 1, DOMAIN_SEPARATOR, address(transmuter));

        startHoax(alice);
        transmuter.swapExactInputWithPermit(BASE_6, 0, address(eurA), alice, deadline, abi.encode(nonce, sig));

        assertEq(agToken.balanceOf(alice), BASE_27 / (BASE_9 + BASE_9 / 99));
        assertEq(eurA.balanceOf(alice), 0);
        assertEq(eurA.balanceOf(address(manager)), BASE_6);
    }

    function test_SwapExactOutputWithPermitAndManager() public {
        // Set manager
        MockManager manager = new MockManager(address(eurA));
        IERC20[] memory subCollaterals = new IERC20[](2);
        subCollaterals[0] = eurA;
        subCollaterals[1] = eurB;
        ManagerStorage memory data = ManagerStorage({
            subCollaterals: subCollaterals,
            config: abi.encode(ManagerType.EXTERNAL, abi.encode(manager))
        });
        manager.setSubCollaterals(data.subCollaterals, data.config);

        hoax(governor);
        transmuter.setCollateralManager(address(eurA), data);

        // Test
        uint256 amountOut = BASE_18;
        uint256 amountInMax = (3 * BASE_6) / 2;
        uint256 amountIn = (3 * BASE_6) / 2 - 489899;
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;

        deal(address(eurA), alice, amountInMax);

        PermitTransferFrom memory permit = PermitTransferFrom({
            permitted: TokenPermissions({ token: address(eurA), amount: amountInMax }),
            nonce: nonce,
            deadline: deadline
        });
        bytes memory sig = getPermitTransferSignature(permit, 1, DOMAIN_SEPARATOR, address(transmuter));

        startHoax(alice);
        transmuter.swapExactOutputWithPermit(
            amountOut,
            amountInMax,
            address(eurA),
            alice,
            deadline,
            abi.encode(nonce, sig)
        );

        assertEq(agToken.balanceOf(alice), BASE_18);
        assertEq(eurA.balanceOf(alice), amountInMax - amountIn);
        assertEq(eurA.balanceOf(address(manager)), amountIn);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         UTILS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    bytes32 public constant _TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

    bytes32 public constant _PERMIT_TRANSFER_FROM_TYPEHASH =
        keccak256(
            "PermitTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
        );

    /// @notice Forked from https://github.com/Uniswap/permit2/blob/main/test/utils/PermitSignature.sol
    function getPermitTransferSignature(
        PermitTransferFrom memory permit,
        uint256 privateKey,
        bytes32 domainSeparator,
        address to
    ) internal pure returns (bytes memory sig) {
        bytes32 tokenPermissions = keccak256(abi.encode(_TOKEN_PERMISSIONS_TYPEHASH, permit.permitted));
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    abi.encode(_PERMIT_TRANSFER_FROM_TYPEHASH, tokenPermissions, to, permit.nonce, permit.deadline)
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        return bytes.concat(r, s, bytes1(v));
    }
}
