// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UnlessRetainer} from "../UnlessRetainer.sol";
import {UnlessRetainerBase} from "./UnlessRetainer.Base.t.sol";

/// @notice Unit tests: objectToClaim (4.6).
contract UnlessRetainerObjectTest is UnlessRetainerBase {
    UnlessRetainer.ClaimStatus internal constant PENDING = UnlessRetainer.ClaimStatus.Pending;
    UnlessRetainer.ClaimStatus internal constant OBJECTED = UnlessRetainer.ClaimStatus.Objected;
    UnlessRetainer.PaidVia internal constant NO_VIA = UnlessRetainer.PaidVia.None;

    function test_objectToClaim_byClient_unreservesWithoutMovingTokens() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        uint256 retainerTokens = usdc.balanceOf(address(retainer));

        _expectObjected(id, claimId, "work not delivered");
        vm.prank(client);
        retainer.objectToClaim(id, claimId, "work not delivered");

        _assertState(id, 10e6, 0, 10e6, 0, 0, 0);
        _assertClaim(id, claimId, 3e6, OBJECTED, NO_VIA);
        assertEq(retainer.availableOf(id), 10e6, "money is available again");
        assertEq(usdc.balanceOf(address(retainer)), retainerTokens, "retainer tokens");
        assertEq(usdc.balanceOf(client), START_BALANCE - 10e6, "client tokens");
        assertEq(usdc.balanceOf(freelancer), START_BALANCE, "freelancer tokens");
        assertEq(usdc.balanceOf(stranger), START_BALANCE, "stranger tokens");
    }

    function test_objectToClaim_oneOfTwoClaims_leavesOtherReserved() public {
        uint256 id = _create(10e6);
        _file(id, 3e6, "a");
        _file(id, 2e6, "b");
        _expectObjected(id, 1, "no");
        vm.prank(client);
        retainer.objectToClaim(id, 1, "no");
        _assertState(id, 10e6, 3e6, 10e6, 0, 0, 1);
        _assertClaim(id, 0, 3e6, PENDING, NO_VIA);
    }

    // ---------------------------------------------------------------- window boundary

    function test_objectToClaim_oneSecondBeforePayableAt_succeeds() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        vm.warp(uint256(_payableAt(id, claimId)) - 1);
        _expectObjected(id, claimId, "late but in time");
        vm.prank(client);
        retainer.objectToClaim(id, claimId, "late but in time");
        _assertClaim(id, claimId, 3e6, OBJECTED, NO_VIA);
    }

    function test_objectToClaim_atPayableAt_revertsObjectionWindowClosed() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        vm.warp(_payableAt(id, claimId));
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.ObjectionWindowClosed.selector);
        retainer.objectToClaim(id, claimId, "too late");
        _assertState(id, 10e6, 3e6, 10e6, 0, 0, 1);
    }

    function test_objectToClaim_oneSecondAfterPayableAt_revertsObjectionWindowClosed() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        vm.warp(uint256(_payableAt(id, claimId)) + 1);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.ObjectionWindowClosed.selector);
        retainer.objectToClaim(id, claimId, "too late");
    }

    // ---------------------------------------------------------------- reason length

    function test_objectToClaim_reason280Bytes_succeeds() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        string memory reason = _str(MAX_TEXT);
        _expectObjected(id, claimId, reason);
        vm.prank(client);
        retainer.objectToClaim(id, claimId, reason);
        _assertClaim(id, claimId, 3e6, OBJECTED, NO_VIA);
    }

    function test_objectToClaim_reason281Bytes_revertsTextTooLong() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        string memory reason = _str(MAX_TEXT + 1);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.TextTooLong.selector);
        retainer.objectToClaim(id, claimId, reason);
        _assertState(id, 10e6, 3e6, 10e6, 0, 0, 1);
    }

    function test_objectToClaim_emptyReason_succeeds() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        _expectObjected(id, claimId, "");
        vm.prank(client);
        retainer.objectToClaim(id, claimId, "");
        _assertClaim(id, claimId, 3e6, OBJECTED, NO_VIA);
    }

    // ---------------------------------------------------------------- reverts

    function test_objectToClaim_byStranger_revertsNotClient() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.objectToClaim(id, claimId, "x");
    }

    function test_objectToClaim_byFreelancer_revertsNotClient() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.objectToClaim(id, claimId, "x");
        _assertState(id, 10e6, 3e6, 10e6, 0, 0, 1);
    }

    function test_objectToClaim_alreadyObjected_revertsClaimNotPending() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        _object(id, claimId);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.ClaimNotPending.selector);
        retainer.objectToClaim(id, claimId, "again");
    }

    function test_objectToClaim_paid_revertsClaimNotPending() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        _approveNow(id, claimId);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.ClaimNotPending.selector);
        retainer.objectToClaim(id, claimId, "x");
    }

    function test_objectToClaim_cancelled_revertsClaimNotPending() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        _cancel(id, claimId);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.ClaimNotPending.selector);
        retainer.objectToClaim(id, claimId, "x");
    }

    function test_objectToClaim_unknownClaimId_revertsClaimNotFound() public {
        (uint256 id,) = _setupClaim(10e6, 3e6);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.ClaimNotFound.selector);
        retainer.objectToClaim(id, 1, "x");
    }

    function test_objectToClaim_unknownRetainerId_revertsRetainerNotFound() public {
        _setupClaim(10e6, 3e6);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.RetainerNotFound.selector);
        retainer.objectToClaim(1, 0, "x");
    }

    // ---------------------------------------------------------------- check order

    function test_objectToClaim_strangerWithUnknownClaimId_revertsClaimNotFoundBeforeNotClient() public {
        (uint256 id,) = _setupClaim(10e6, 3e6);
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.ClaimNotFound.selector);
        retainer.objectToClaim(id, 3, "x");
    }

    function test_objectToClaim_strangerWithUnknownRetainerId_revertsRetainerNotFound() public {
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.RetainerNotFound.selector);
        retainer.objectToClaim(8, 8, "x");
    }

    function test_objectToClaim_strangerOnObjectedClaim_revertsNotClientBeforeClaimNotPending() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        _object(id, claimId);
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.objectToClaim(id, claimId, "x");
    }

    function test_objectToClaim_strangerAfterWindow_revertsNotClientBeforeObjectionWindowClosed() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        vm.warp(_payableAt(id, claimId));
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.objectToClaim(id, claimId, "x");
    }

    function test_objectToClaim_paidClaimAfterWindow_revertsClaimNotPendingBeforeObjectionWindowClosed() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        vm.warp(_payableAt(id, claimId));
        _payOut(id, claimId);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.ClaimNotPending.selector);
        retainer.objectToClaim(id, claimId, "x");
    }

    function test_objectToClaim_pendingPastWindowWith281ByteReason_revertsObjectionWindowClosed() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        vm.warp(_payableAt(id, claimId));
        string memory reason = _str(MAX_TEXT + 1);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.ObjectionWindowClosed.selector);
        retainer.objectToClaim(id, claimId, reason);
    }
}
