// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UnlessRetainer} from "../UnlessRetainer.sol";
import {UnlessRetainerBase} from "./UnlessRetainer.Base.t.sol";

/// @notice Unit tests: approveClaim (4.5) and cancelClaim (4.7).
contract UnlessRetainerApproveTest is UnlessRetainerBase {
    UnlessRetainer.ClaimStatus internal constant PENDING = UnlessRetainer.ClaimStatus.Pending;
    UnlessRetainer.ClaimStatus internal constant PAID = UnlessRetainer.ClaimStatus.Paid;
    UnlessRetainer.ClaimStatus internal constant CANCELLED = UnlessRetainer.ClaimStatus.Cancelled;
    UnlessRetainer.PaidVia internal constant NO_VIA = UnlessRetainer.PaidVia.None;
    UnlessRetainer.PaidVia internal constant APPROVED_NOW = UnlessRetainer.PaidVia.ApprovedNow;

    // ================================================================ 4.5 approveClaim

    function test_approveClaim_byClient_paysFreelancerImmediately() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        uint256 retainerTokens = usdc.balanceOf(address(retainer));
        uint256 clientTokens = usdc.balanceOf(client);

        _expectPaid(id, claimId, freelancer, 3e6, APPROVED_NOW);
        vm.prank(client);
        retainer.approveClaim(id, claimId);

        assertEq(usdc.balanceOf(freelancer), START_BALANCE + 3e6, "freelancer paid");
        assertEq(usdc.balanceOf(address(retainer)), retainerTokens - 3e6, "retainer paid out");
        assertEq(usdc.balanceOf(client), clientTokens, "client unchanged");
        _assertState(id, 7e6, 0, 10e6, 3e6, 0, 0);
        _assertClaim(id, claimId, 3e6, PAID, APPROVED_NOW);
        assertEq(retainer.owed(freelancer), 0);
        assertEq(retainer.totalOwed(), 0);
    }

    function test_approveClaim_afterPayableAt_stillPending_succeeds() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        uint64 payableAt = _payableAt(id, claimId);
        vm.warp(uint256(payableAt) + 1);
        _assertClaim(id, claimId, 3e6, PENDING, NO_VIA);

        _expectPaid(id, claimId, freelancer, 3e6, APPROVED_NOW);
        vm.prank(client);
        retainer.approveClaim(id, claimId);

        _assertClaim(id, claimId, 3e6, PAID, APPROVED_NOW);
        _assertState(id, 7e6, 0, 10e6, 3e6, 0, 0);
        assertEq(usdc.balanceOf(freelancer), START_BALANCE + 3e6);
    }

    function test_approveClaim_atPayableAt_succeeds() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        vm.warp(_payableAt(id, claimId));
        _expectPaid(id, claimId, freelancer, 3e6, APPROVED_NOW);
        vm.prank(client);
        retainer.approveClaim(id, claimId);
        _assertClaim(id, claimId, 3e6, PAID, APPROVED_NOW);
    }

    function test_approveClaim_oneOfTwoClaims_leavesOtherReserved() public {
        uint256 id = _create(10e6);
        _file(id, 3e6, "a");
        _file(id, 2e6, "b");
        _expectPaid(id, 1, freelancer, 2e6, APPROVED_NOW);
        vm.prank(client);
        retainer.approveClaim(id, 1);
        _assertState(id, 8e6, 3e6, 10e6, 2e6, 0, 1);
        _assertClaim(id, 0, 3e6, PENDING, NO_VIA);
        _assertClaim(id, 1, 2e6, PAID, APPROVED_NOW);
    }

    function test_approveClaim_byStranger_revertsNotClient() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.approveClaim(id, claimId);
    }

    function test_approveClaim_byFreelancer_revertsNotClient() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.approveClaim(id, claimId);
        _assertState(id, 10e6, 3e6, 10e6, 0, 0, 1);
    }

    function test_approveClaim_alreadyPaid_revertsClaimNotPending() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        _approveNow(id, claimId);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.ClaimNotPending.selector);
        retainer.approveClaim(id, claimId);
        _assertState(id, 7e6, 0, 10e6, 3e6, 0, 0);
    }

    function test_approveClaim_paidOut_revertsClaimNotPending() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        vm.warp(_payableAt(id, claimId));
        _payOut(id, claimId);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.ClaimNotPending.selector);
        retainer.approveClaim(id, claimId);
    }

    function test_approveClaim_objected_revertsClaimNotPending() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        _object(id, claimId);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.ClaimNotPending.selector);
        retainer.approveClaim(id, claimId);
    }

    function test_approveClaim_cancelled_revertsClaimNotPending() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        _cancel(id, claimId);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.ClaimNotPending.selector);
        retainer.approveClaim(id, claimId);
    }

    function test_approveClaim_unknownClaimId_revertsClaimNotFound() public {
        (uint256 id,) = _setupClaim(10e6, 3e6);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.ClaimNotFound.selector);
        retainer.approveClaim(id, 1);
    }

    function test_approveClaim_hugeClaimId_revertsClaimNotFound() public {
        (uint256 id,) = _setupClaim(10e6, 3e6);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.ClaimNotFound.selector);
        retainer.approveClaim(id, type(uint256).max);
    }

    function test_approveClaim_retainerWithoutClaims_revertsClaimNotFound() public {
        uint256 id = _create(10e6);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.ClaimNotFound.selector);
        retainer.approveClaim(id, 0);
    }

    function test_approveClaim_unknownRetainerId_revertsRetainerNotFound() public {
        _setupClaim(10e6, 3e6);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.RetainerNotFound.selector);
        retainer.approveClaim(1, 0);
    }

    function test_approveClaim_strangerWithUnknownClaimId_revertsClaimNotFoundBeforeNotClient() public {
        (uint256 id,) = _setupClaim(10e6, 3e6);
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.ClaimNotFound.selector);
        retainer.approveClaim(id, 5);
    }

    function test_approveClaim_strangerWithUnknownRetainerId_revertsRetainerNotFound() public {
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.RetainerNotFound.selector);
        retainer.approveClaim(9, 9);
    }

    function test_approveClaim_strangerOnPaidClaim_revertsNotClientBeforeClaimNotPending() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        _approveNow(id, claimId);
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.approveClaim(id, claimId);
    }

    function test_approveClaim_clientOfOtherRetainer_revertsNotClient() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        _createFor(client2, freelancer2, 0);
        vm.prank(client2);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.approveClaim(id, claimId);
    }

    // ================================================================ 4.7 cancelClaim

    function test_cancelClaim_byFreelancer_unreservesWithoutMovingTokens() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        uint256 retainerTokens = usdc.balanceOf(address(retainer));

        _expectCancelled(id, claimId);
        vm.prank(freelancer);
        retainer.cancelClaim(id, claimId);

        _assertState(id, 10e6, 0, 10e6, 0, 0, 0);
        _assertClaim(id, claimId, 3e6, CANCELLED, NO_VIA);
        assertEq(retainer.availableOf(id), 10e6);
        assertEq(usdc.balanceOf(address(retainer)), retainerTokens);
        assertEq(usdc.balanceOf(freelancer), START_BALANCE);
        assertEq(usdc.balanceOf(client), START_BALANCE - 10e6);
    }

    function test_cancelClaim_afterPayableAt_succeeds() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        vm.warp(uint256(_payableAt(id, claimId)) + 1);
        _expectCancelled(id, claimId);
        vm.prank(freelancer);
        retainer.cancelClaim(id, claimId);
        _assertState(id, 10e6, 0, 10e6, 0, 0, 0);
        _assertClaim(id, claimId, 3e6, CANCELLED, NO_VIA);
    }

    function test_cancelClaim_afterRetainerEnded_succeeds() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        vm.warp(uint256(END) + 1);
        _expectCancelled(id, claimId);
        vm.prank(freelancer);
        retainer.cancelClaim(id, claimId);
        _assertState(id, 10e6, 0, 10e6, 0, 0, 0);
    }

    function test_cancelClaim_oneOfTwoClaims_leavesOtherReserved() public {
        uint256 id = _create(10e6);
        _file(id, 3e6, "a");
        _file(id, 2e6, "b");
        _expectCancelled(id, 0);
        vm.prank(freelancer);
        retainer.cancelClaim(id, 0);
        _assertState(id, 10e6, 2e6, 10e6, 0, 0, 1);
        _assertClaim(id, 1, 2e6, PENDING, NO_VIA);
    }

    function test_cancelClaim_byClient_revertsNotFreelancer() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.NotFreelancer.selector);
        retainer.cancelClaim(id, claimId);
    }

    function test_cancelClaim_byStranger_revertsNotFreelancer() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NotFreelancer.selector);
        retainer.cancelClaim(id, claimId);
        _assertState(id, 10e6, 3e6, 10e6, 0, 0, 1);
    }

    function test_cancelClaim_alreadyCancelled_revertsClaimNotPending() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        _cancel(id, claimId);
        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.ClaimNotPending.selector);
        retainer.cancelClaim(id, claimId);
    }

    function test_cancelClaim_paid_revertsClaimNotPending() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        _approveNow(id, claimId);
        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.ClaimNotPending.selector);
        retainer.cancelClaim(id, claimId);
        _assertState(id, 7e6, 0, 10e6, 3e6, 0, 0);
    }

    function test_cancelClaim_objected_revertsClaimNotPending() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        _object(id, claimId);
        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.ClaimNotPending.selector);
        retainer.cancelClaim(id, claimId);
    }

    function test_cancelClaim_unknownClaimId_revertsClaimNotFound() public {
        (uint256 id,) = _setupClaim(10e6, 3e6);
        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.ClaimNotFound.selector);
        retainer.cancelClaim(id, 1);
    }

    function test_cancelClaim_unknownRetainerId_revertsRetainerNotFound() public {
        _setupClaim(10e6, 3e6);
        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.RetainerNotFound.selector);
        retainer.cancelClaim(1, 0);
    }

    function test_cancelClaim_strangerWithUnknownClaimId_revertsClaimNotFoundBeforeNotFreelancer() public {
        (uint256 id,) = _setupClaim(10e6, 3e6);
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.ClaimNotFound.selector);
        retainer.cancelClaim(id, 7);
    }

    function test_cancelClaim_strangerWithUnknownRetainerId_revertsRetainerNotFound() public {
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.RetainerNotFound.selector);
        retainer.cancelClaim(4, 4);
    }

    function test_cancelClaim_strangerOnCancelledClaim_revertsNotFreelancerBeforeClaimNotPending() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        _cancel(id, claimId);
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NotFreelancer.selector);
        retainer.cancelClaim(id, claimId);
    }

    function test_cancelClaim_clientOnPaidClaim_revertsNotFreelancerBeforeClaimNotPending() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        _approveNow(id, claimId);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.NotFreelancer.selector);
        retainer.cancelClaim(id, claimId);
    }
}
