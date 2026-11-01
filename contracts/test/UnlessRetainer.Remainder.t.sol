// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UnlessRetainer} from "../UnlessRetainer.sol";
import {UnlessRetainerExtBase} from "./UnlessRetainer.ExtBase.t.sol";

/// @notice 4.10 withdrawRemainder. (The blocked-client credit case lives in UnlessRetainer.Owed.t.sol.)
contract UnlessRetainerRemainderTest is UnlessRetainerExtBase {
    UnlessRetainer.ClaimStatus internal constant PENDING = UnlessRetainer.ClaimStatus.Pending;
    UnlessRetainer.ClaimStatus internal constant PAID = UnlessRetainer.ClaimStatus.Paid;

    function _remainder(uint256 id) internal {
        vm.prank(client);
        retainer.withdrawRemainder(id);
    }

    // ---------------------------------------------------------------- timing

    function test_withdrawRemainder_oneSecondBeforeEnd_revertsRetainerNotEnded() public {
        uint256 id = _create(10e6);
        vm.warp(uint256(END) - 1);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.RetainerNotEnded.selector);
        retainer.withdrawRemainder(id);
    }

    function test_withdrawRemainder_rightAfterCreation_revertsRetainerNotEnded() public {
        uint256 id = _create(10e6);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.RetainerNotEnded.selector);
        retainer.withdrawRemainder(id);
    }

    function test_withdrawRemainder_atEndTime_succeeds() public {
        uint256 id = _create(10e6);
        vm.warp(END);

        _expectRemainder(id, 10e6);
        _remainder(id);

        _assertAcct(id, 0, 0, 10e6, 0, 10e6, 0);
    }

    function test_withdrawRemainder_oneSecondAfterEnd_succeeds() public {
        uint256 id = _create(10e6);
        vm.warp(uint256(END) + 1);

        _expectRemainder(id, 10e6);
        _remainder(id);

        _assertAcct(id, 0, 0, 10e6, 0, 10e6, 0);
    }

    // ---------------------------------------------------------------- payout

    function test_withdrawRemainder_afterEnd_paysClientEmitsAndUpdatesTotals() public {
        uint256 id = _create(10e6);
        _approve(client, 5e6);
        vm.prank(client);
        retainer.deposit(id, 5e6);
        vm.warp(END);

        _expectRemainder(id, 15e6);
        _expectTransfer(address(retainer), client, 15e6);
        _remainder(id);

        assertEq(usdc.balanceOf(client), START_BALANCE, "client made whole");
        assertEq(usdc.balanceOf(address(retainer)), 0);
        assertEq(retainer.totalOwed(), 0);
        _assertAcct(id, 0, 0, 15e6, 0, 15e6, 0);
        _assertSolvent();
    }

    function test_withdrawRemainder_withPendingClaims_paysOnlyAvailableAndKeepsReserved() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        vm.warp(END);

        _expectRemainder(id, 7e6);
        _expectTransfer(address(retainer), client, 7e6);
        _remainder(id);

        _assertAcct(id, 3e6, 3e6, 10e6, 0, 7e6, 1);
        _assertClaimV(id, claimId, 3e6, PENDING, UnlessRetainer.PaidVia.None);
        assertEq(usdc.balanceOf(address(retainer)), 3e6, "reserved money stays");
        assertEq(usdc.balanceOf(client), START_BALANCE - 3e6);
        _assertSolvent();
    }

    function test_withdrawRemainder_thenPayOutClaim_pendingClaimStillPaysFreelancer() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        vm.warp(END);
        _remainder(id);

        _expectPaid(id, claimId, freelancer, 3e6, UnlessRetainer.PaidVia.PaidOut);
        _payOut(id, claimId);

        _assertAcct(id, 0, 0, 10e6, 3e6, 7e6, 0);
        _assertClaimV(id, claimId, 3e6, PAID, UnlessRetainer.PaidVia.PaidOut);
        assertEq(usdc.balanceOf(freelancer), START_BALANCE + 3e6);
        assertEq(usdc.balanceOf(address(retainer)), 0);
        _assertSolvent();
    }

    function test_withdrawRemainder_thenApproveClaim_pendingClaimStillPaysFreelancer() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        vm.warp(END);
        _remainder(id);

        _expectPaid(id, claimId, freelancer, 3e6, UnlessRetainer.PaidVia.ApprovedNow);
        _approveNow(id, claimId);

        _assertAcct(id, 0, 0, 10e6, 3e6, 7e6, 0);
        _assertClaimV(id, claimId, 3e6, PAID, UnlessRetainer.PaidVia.ApprovedNow);
        assertEq(usdc.balanceOf(freelancer), START_BALANCE + 3e6);
        _assertSolvent();
    }

    // ---------------------------------------------------------------- pending withdrawal

    function test_withdrawRemainder_withPendingWithdrawal_emitsCancelledBeforeRemainderAndClears() public {
        uint256 id = _create(10e6);
        _request(id, 4e6);
        vm.warp(END);

        vm.recordLogs();
        _expectWdCancelled(id);
        _expectRemainder(id, 10e6);
        _remainder(id);
        bytes32[] memory topics0 = _topics0(vm.getRecordedLogs());

        assertEq(topics0.length, 2, "exactly two retainer events");
        assertEq(topics0[0], UnlessRetainer.WithdrawalCancelled.selector, "cancelled first");
        assertEq(topics0[1], UnlessRetainer.RemainderWithdrawn.selector, "remainder second");
        _assertNoWithdrawal(id);
        _assertAcct(id, 0, 0, 10e6, 0, 10e6, 0);
    }

    function test_withdrawRemainder_withPendingWithdrawalAndClaims_paysAllAvailableNotJustRequested() public {
        uint256 id = _create(10e6);
        _request(id, 4e6);
        _file(id, 3e6, "c");
        vm.warp(END);

        _expectWdCancelled(id);
        _expectRemainder(id, 7e6);
        _remainder(id);

        _assertNoWithdrawal(id);
        _assertAcct(id, 3e6, 3e6, 10e6, 0, 7e6, 1);
    }

    function test_withdrawRemainder_withoutPendingWithdrawal_emitsOnlyRemainder() public {
        uint256 id = _create(10e6);
        vm.warp(END);

        vm.recordLogs();
        _remainder(id);
        bytes32[] memory topics0 = _topics0(vm.getRecordedLogs());

        assertEq(topics0.length, 1);
        assertEq(topics0[0], UnlessRetainer.RemainderWithdrawn.selector);
    }

    // ---------------------------------------------------------------- repeat / reopen

    function test_withdrawRemainder_calledTwice_secondRevertsZeroAmount() public {
        uint256 id = _create(10e6);
        vm.warp(END);
        _remainder(id);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.ZeroAmount.selector);
        retainer.withdrawRemainder(id);
    }

    function test_withdrawRemainder_afterExtendReopens_revertsRetainerNotEnded() public {
        uint256 id = _create(10e6);
        vm.warp(END);
        vm.prank(client);
        retainer.extendEndTime(id, END + 1 days);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.RetainerNotEnded.selector);
        retainer.withdrawRemainder(id);

        // ...and it becomes available again once the new end is reached.
        vm.warp(uint256(END) + 1 days);
        _expectRemainder(id, 10e6);
        _remainder(id);
    }

    // ---------------------------------------------------------------- reverts: ZeroAmount

    function test_withdrawRemainder_unfundedRetainerAfterEnd_revertsZeroAmount() public {
        uint256 id = _create(0);
        vm.warp(END);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.ZeroAmount.selector);
        retainer.withdrawRemainder(id);
    }

    function test_withdrawRemainder_everythingReserved_revertsZeroAmount() public {
        (uint256 id,) = _setupClaim(10e6, 10e6);
        vm.warp(END);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.ZeroAmount.selector);
        retainer.withdrawRemainder(id);
        _assertAcct(id, 10e6, 10e6, 10e6, 0, 0, 1);
    }

    function test_withdrawRemainder_everythingReservedWithPendingWithdrawal_revertsZeroAmountAndKeepsRequest()
        public
    {
        uint256 id = _create(10e6);
        _request(id, 10e6);
        uint64 readyAt = _readyAt(id);
        _file(id, 10e6, "all");
        vm.warp(END);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.ZeroAmount.selector);
        retainer.withdrawRemainder(id);
        _assertWithdrawal(id, 10e6, readyAt);
    }

    // ---------------------------------------------------------------- reverts: ordering

    function test_withdrawRemainder_beforeEndAndZeroAvailable_revertsRetainerNotEnded() public {
        uint256 id = _create(0);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.RetainerNotEnded.selector);
        retainer.withdrawRemainder(id);
    }

    function test_withdrawRemainder_byStrangerBeforeEnd_revertsNotClient() public {
        uint256 id = _create(10e6);

        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.withdrawRemainder(id);
    }

    function test_withdrawRemainder_byFreelancerBeforeEnd_revertsNotClient() public {
        uint256 id = _create(10e6);

        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.withdrawRemainder(id);
    }

    function test_withdrawRemainder_byStrangerAfterEnd_revertsNotClient() public {
        uint256 id = _create(10e6);
        vm.warp(END);

        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.withdrawRemainder(id);
    }

    function test_withdrawRemainder_byStrangerAfterEndWithZeroAvailable_revertsNotClient() public {
        uint256 id = _create(0);
        vm.warp(END);

        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.withdrawRemainder(id);
    }

    function test_withdrawRemainder_byOtherClient_revertsNotClient() public {
        uint256 id = _create(10e6);
        vm.warp(END);

        vm.prank(client2);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.withdrawRemainder(id);
    }

    function test_withdrawRemainder_unknownId_revertsRetainerNotFound() public {
        _create(10e6);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.RetainerNotFound.selector);
        retainer.withdrawRemainder(1);
    }

    function test_withdrawRemainder_unknownIdByStranger_revertsRetainerNotFound() public {
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.RetainerNotFound.selector);
        retainer.withdrawRemainder(type(uint256).max);
    }
}
