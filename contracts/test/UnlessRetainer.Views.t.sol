// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UnlessRetainer} from "../UnlessRetainer.sol";
import {UnlessRetainerExtBase} from "./UnlessRetainer.ExtBase.t.sol";

/// @notice 4.14 views: getRetainer, getClaim, getClaims, retainersOfClient, retainersOfFreelancer,
/// nextRetainerId. Every read goes through the real public functions.
contract UnlessRetainerViewsTest is UnlessRetainerExtBase {
    UnlessRetainer.ClaimStatus internal constant PENDING = UnlessRetainer.ClaimStatus.Pending;
    UnlessRetainer.ClaimStatus internal constant PAID = UnlessRetainer.ClaimStatus.Paid;
    UnlessRetainer.ClaimStatus internal constant OBJECTED = UnlessRetainer.ClaimStatus.Objected;
    UnlessRetainer.ClaimStatus internal constant CANCELLED = UnlessRetainer.ClaimStatus.Cancelled;

    // ---------------------------------------------------------------- getRetainer

    function test_getRetainer_afterCreation_returnsEveryField() public {
        vm.warp(5000);
        uint256 id = _create(10e6);

        (UnlessRetainer.Retainer memory r, uint256 available, bool ended) = retainer.getRetainer(id);

        assertEq(r.client, client, "client");
        assertEq(r.freelancer, freelancer, "freelancer");
        assertEq(uint256(r.objectionWindow), uint256(WINDOW), "objectionWindow");
        assertEq(uint256(r.noticePeriod), uint256(NOTICE), "noticePeriod");
        assertEq(uint256(r.endTime), uint256(END), "endTime");
        assertEq(uint256(r.balance), 10e6, "balance");
        assertEq(uint256(r.reserved), 0, "reserved");
        assertEq(uint256(r.withdrawalAmount), 0, "withdrawalAmount");
        assertEq(uint256(r.withdrawalReadyAt), 0, "withdrawalReadyAt");
        assertEq(uint256(r.claimCount), 0, "claimCount");
        assertEq(uint256(r.pendingClaims), 0, "pendingClaims");
        assertEq(uint256(r.totalDeposited), 10e6, "totalDeposited");
        assertEq(uint256(r.totalPaid), 0, "totalPaid");
        assertEq(uint256(r.totalReturned), 0, "totalReturned");
        assertEq(uint256(r.createdAt), 5000, "createdAt");
        assertEq(available, 10e6, "available");
        assertFalse(ended, "ended");
    }

    function test_getRetainer_createdWithoutDeposit_hasZeroBalanceAndAvailable() public {
        uint256 id = _create(0);

        (UnlessRetainer.Retainer memory r, uint256 available, bool ended) = retainer.getRetainer(id);

        assertEq(r.client, client);
        assertEq(uint256(r.balance), 0);
        assertEq(uint256(r.totalDeposited), 0);
        assertEq(available, 0);
        assertFalse(ended);
    }

    function test_getRetainer_endedFlag_flipsExactlyAtEndTime() public {
        uint256 id = _create(10e6);

        (,, bool endedNow) = retainer.getRetainer(id);
        assertFalse(endedNow, "fresh");

        vm.warp(uint256(END) - 1);
        assertFalse(_isEnded(id), "END-1");
        vm.warp(END);
        assertTrue(_isEnded(id), "END");
        vm.warp(uint256(END) + 1);
        assertTrue(_isEnded(id), "END+1");
        assertEq(_avail(id), 10e6, "available unaffected by ending");
    }

    function test_getRetainer_availableWithReservationsAndPendingWithdrawal_subtractsOnlyReserved() public {
        (uint256 id,) = _setupClaim(10e6, 3e6);
        _request(id, 5e6);

        (UnlessRetainer.Retainer memory r, uint256 available,) = retainer.getRetainer(id);

        assertEq(uint256(r.balance), 10e6);
        assertEq(uint256(r.reserved), 3e6);
        assertEq(uint256(r.withdrawalAmount), 5e6);
        assertEq(uint256(r.withdrawalReadyAt), block.timestamp + NOTICE);
        assertEq(uint256(r.pendingClaims), 1);
        assertEq(uint256(r.claimCount), 1);
        assertEq(available, 7e6, "balance - reserved; the request reserves nothing");
    }

    function test_getRetainer_availableAfterPayoutObjectionAndCancel_tracksReservations() public {
        uint256 id = _create(10e6);
        uint256 c0 = _file(id, 3e6, "a");
        uint256 c1 = _file(id, 2e6, "b");
        uint256 c2 = _file(id, 1e6, "c");
        assertEq(_avail(id), 4e6);

        _object(id, c0);
        assertEq(_avail(id), 7e6, "objected releases");
        _cancel(id, c1);
        assertEq(_avail(id), 9e6, "cancelled releases");
        _approveNow(id, c2);
        assertEq(_avail(id), 9e6, "approved: balance and reserved both drop");
        assertEq(uint256(_ret(id).balance), 9e6);
        assertEq(uint256(_ret(id).claimCount), 3);
    }

    function test_getRetainer_secondRetainer_returnsItsOwnFields() public {
        _create(10e6);
        uint256 id1 = _createFor(client2, freelancer2, 4e6);

        UnlessRetainer.Retainer memory r = _ret(id1);

        assertEq(id1, 1);
        assertEq(r.client, client2);
        assertEq(r.freelancer, freelancer2);
        assertEq(uint256(r.balance), 4e6);
        assertEq(_ret(0).client, client);
        assertEq(uint256(_ret(0).balance), 10e6);
    }

    function test_getRetainer_unknownIdWithNoRetainers_revertsRetainerNotFound() public {
        vm.expectRevert(UnlessRetainer.RetainerNotFound.selector);
        retainer.getRetainer(0);
    }

    function test_getRetainer_idEqualToNextRetainerId_revertsRetainerNotFound() public {
        _create(1e6);
        _create(1e6);
        assertEq(retainer.nextRetainerId(), 2);

        vm.expectRevert(UnlessRetainer.RetainerNotFound.selector);
        retainer.getRetainer(2);
    }

    function test_getRetainer_maxId_revertsRetainerNotFound() public {
        vm.expectRevert(UnlessRetainer.RetainerNotFound.selector);
        retainer.getRetainer(type(uint256).max);
    }

    // ---------------------------------------------------------------- getClaim

    function test_getClaim_afterFiling_returnsEveryField() public {
        uint256 id = _create(10e6);
        vm.warp(100);
        uint256 claimId = _file(id, 3e6, "hello");

        UnlessRetainer.Claim memory c = retainer.getClaim(id, claimId);

        assertEq(uint256(c.amount), 3e6, "amount");
        assertEq(uint256(c.filedAt), 100, "filedAt");
        assertEq(uint256(c.payableAt), 100 + WINDOW, "payableAt");
        assertEq(uint256(c.status), uint256(PENDING), "status");
        assertEq(uint256(c.paidVia), uint256(UnlessRetainer.PaidVia.None), "paidVia");
        assertEq(c.noteHash, keccak256(bytes("hello")), "noteHash");
    }

    function test_getClaim_emptyNote_hashesEmptyBytes() public {
        uint256 id = _create(10e6);
        uint256 claimId = _file(id, 1e6, "");

        assertEq(retainer.getClaim(id, claimId).noteHash, keccak256(""));
    }

    function test_getClaim_afterEachResolution_reportsStatusAndPaidVia() public {
        uint256 id = _create(10e6);
        uint256 approved = _file(id, 1e6, "a");
        uint256 objected = _file(id, 2e6, "b");
        uint256 cancelled = _file(id, 3e6, "c");
        uint256 paidOut = _file(id, 4e6, "d");
        _approveNow(id, approved);
        _object(id, objected);
        _cancel(id, cancelled);
        vm.warp(_payableAtV(id, paidOut));
        _payOut(id, paidOut);

        _assertClaimV(id, approved, 1e6, PAID, UnlessRetainer.PaidVia.ApprovedNow);
        _assertClaimV(id, objected, 2e6, OBJECTED, UnlessRetainer.PaidVia.None);
        _assertClaimV(id, cancelled, 3e6, CANCELLED, UnlessRetainer.PaidVia.None);
        _assertClaimV(id, paidOut, 4e6, PAID, UnlessRetainer.PaidVia.PaidOut);
    }

    function test_getClaim_claimIdEqualToClaimCount_revertsClaimNotFound() public {
        uint256 id = _create(10e6);
        vm.expectRevert(UnlessRetainer.ClaimNotFound.selector);
        retainer.getClaim(id, 0);

        _file(id, 1e6, "a");
        _file(id, 1e6, "b");
        vm.expectRevert(UnlessRetainer.ClaimNotFound.selector);
        retainer.getClaim(id, 2);
    }

    function test_getClaim_maxClaimId_revertsClaimNotFound() public {
        (uint256 id,) = _setupClaim(10e6, 1e6);

        vm.expectRevert(UnlessRetainer.ClaimNotFound.selector);
        retainer.getClaim(id, type(uint256).max);
    }

    function test_getClaim_unknownRetainer_revertsRetainerNotFound() public {
        _setupClaim(10e6, 1e6);

        vm.expectRevert(UnlessRetainer.RetainerNotFound.selector);
        retainer.getClaim(1, 0);
    }

    function test_getClaim_unknownRetainerAndUnknownClaim_revertsRetainerNotFound() public {
        vm.expectRevert(UnlessRetainer.RetainerNotFound.selector);
        retainer.getClaim(type(uint256).max, type(uint256).max);
    }

    function test_getClaim_otherRetainersClaimId_revertsClaimNotFound() public {
        _setupClaim(10e6, 1e6); // retainer 0 has claim 0
        uint256 id1 = _createFor(client2, freelancer2, 5e6); // retainer 1 has no claims

        vm.expectRevert(UnlessRetainer.ClaimNotFound.selector);
        retainer.getClaim(id1, 0);
    }

    // ---------------------------------------------------------------- getClaims

    /// @dev Retainer 0 with 8 claims (amounts 1..8 USDC, filed one second apart starting at t = 100):
    /// 0 approved, 1 objected, 2 cancelled, 3 paid out, 4..7 pending. Returns the retainer id.
    function _eightClaims() internal returns (uint256 id) {
        id = _create(100e6);
        for (uint256 i = 0; i < 8; i++) {
            vm.warp(100 + i);
            _file(id, uint128((i + 1) * 1e6), "claim");
        }
        vm.warp(110);
        _approveNow(id, 0);
        _object(id, 1);
        _cancel(id, 2);
        vm.warp(_payableAtV(id, 3));
        _payOut(id, 3);
    }

    function _expectedStatus(uint256 claimId) internal pure returns (UnlessRetainer.ClaimStatus) {
        if (claimId == 0 || claimId == 3) return PAID;
        if (claimId == 1) return OBJECTED;
        if (claimId == 2) return CANCELLED;
        return PENDING;
    }

    /// @dev `got` must equal claims [offset, offset + got.length) as returned by getClaim, with the
    /// scenario's expected amounts and statuses.
    function _assertSlice(uint256 id, UnlessRetainer.Claim[] memory got, uint256 offset) internal view {
        for (uint256 i = 0; i < got.length; i++) {
            uint256 claimId = offset + i;
            assertEq(
                keccak256(abi.encode(got[i])), keccak256(abi.encode(retainer.getClaim(id, claimId))), "same as getClaim"
            );
            assertEq(uint256(got[i].amount), (claimId + 1) * 1e6, "amount");
            assertEq(uint256(got[i].status), uint256(_expectedStatus(claimId)), "status");
            assertEq(uint256(got[i].filedAt), 100 + claimId, "filedAt");
        }
    }

    function test_getClaims_setupHasMixedStatuses() public {
        uint256 id = _eightClaims();

        assertEq(uint256(_ret(id).claimCount), 8);
        _assertClaimV(id, 0, 1e6, PAID, UnlessRetainer.PaidVia.ApprovedNow);
        _assertClaimV(id, 1, 2e6, OBJECTED, UnlessRetainer.PaidVia.None);
        _assertClaimV(id, 2, 3e6, CANCELLED, UnlessRetainer.PaidVia.None);
        _assertClaimV(id, 3, 4e6, PAID, UnlessRetainer.PaidVia.PaidOut);
        _assertClaimV(id, 7, 8e6, PENDING, UnlessRetainer.PaidVia.None);
        assertEq(uint256(_ret(id).pendingClaims), 4);
    }

    function test_getClaims_fullRange_returnsAllClaimsInOrder() public {
        uint256 id = _eightClaims();

        UnlessRetainer.Claim[] memory got = retainer.getClaims(id, 0, 8);

        assertEq(got.length, 8);
        _assertSlice(id, got, 0);
    }

    function test_getClaims_middleWindow_returnsExactSlice() public {
        uint256 id = _eightClaims();

        UnlessRetainer.Claim[] memory got = retainer.getClaims(id, 2, 3);

        assertEq(got.length, 3);
        _assertSlice(id, got, 2);
    }

    function test_getClaims_singleItemPages_walkEveryClaim() public {
        uint256 id = _eightClaims();

        for (uint256 i = 0; i < 8; i++) {
            UnlessRetainer.Claim[] memory got = retainer.getClaims(id, i, 1);
            assertEq(got.length, 1);
            _assertSlice(id, got, i);
        }
    }

    function test_getClaims_limitExceedsRemaining_clampsToClaimsAfterOffset() public {
        uint256 id = _eightClaims();

        UnlessRetainer.Claim[] memory got = retainer.getClaims(id, 6, 10);

        assertEq(got.length, 2);
        _assertSlice(id, got, 6);
    }

    function test_getClaims_offsetLastClaim_returnsOne() public {
        uint256 id = _eightClaims();

        UnlessRetainer.Claim[] memory got = retainer.getClaims(id, 7, 100);

        assertEq(got.length, 1);
        _assertSlice(id, got, 7);
    }

    function test_getClaims_offsetEqualToClaimCount_returnsEmpty() public {
        uint256 id = _eightClaims();

        assertEq(retainer.getClaims(id, 8, 5).length, 0);
    }

    function test_getClaims_offsetBeyondClaimCount_returnsEmpty() public {
        uint256 id = _eightClaims();

        assertEq(retainer.getClaims(id, 9, 5).length, 0);
        assertEq(retainer.getClaims(id, 1000, 5).length, 0);
    }

    function test_getClaims_limitZero_returnsEmpty() public {
        uint256 id = _eightClaims();

        assertEq(retainer.getClaims(id, 0, 0).length, 0);
        assertEq(retainer.getClaims(id, 4, 0).length, 0);
        assertEq(retainer.getClaims(id, 8, 0).length, 0);
    }

    function test_getClaims_maxLimit_returnsEverythingAfterOffset() public {
        uint256 id = _eightClaims();

        UnlessRetainer.Claim[] memory all = retainer.getClaims(id, 0, type(uint256).max);
        assertEq(all.length, 8);
        _assertSlice(id, all, 0);

        UnlessRetainer.Claim[] memory tail = retainer.getClaims(id, 3, type(uint256).max);
        assertEq(tail.length, 5);
        _assertSlice(id, tail, 3);
    }

    function test_getClaims_maxOffset_returnsEmptyWithoutOverflow() public {
        uint256 id = _eightClaims();

        assertEq(retainer.getClaims(id, type(uint256).max, 5).length, 0);
        assertEq(retainer.getClaims(id, type(uint256).max, type(uint256).max).length, 0);
        assertEq(retainer.getClaims(id, type(uint256).max - 1, type(uint256).max).length, 0);
    }

    function test_getClaims_retainerWithoutClaims_returnsEmpty() public {
        uint256 id = _create(10e6);

        assertEq(retainer.getClaims(id, 0, 10).length, 0);
        assertEq(retainer.getClaims(id, 0, type(uint256).max).length, 0);
    }

    function test_getClaims_unknownRetainer_returnsEmptyAndDoesNotRevert() public {
        _eightClaims();

        assertEq(retainer.getClaims(1, 0, 10).length, 0);
        assertEq(retainer.getClaims(type(uint256).max, 0, 10).length, 0);
        assertEq(retainer.getClaims(type(uint256).max, type(uint256).max, type(uint256).max).length, 0);
    }

    function test_getClaims_unknownRetainerOnFreshContract_returnsEmpty() public view {
        assertEq(retainer.getClaims(0, 0, 10).length, 0);
    }

    function test_getClaims_claimsOfOtherRetainer_areNotMixedIn() public {
        uint256 id = _eightClaims();
        uint256 other = _createFor(client2, freelancer2, 5e6);
        vm.prank(freelancer2);
        retainer.fileClaim(other, 9e6 / 3, "other");

        assertEq(retainer.getClaims(other, 0, 100).length, 1);
        assertEq(retainer.getClaims(id, 0, 100).length, 8);
        assertEq(uint256(retainer.getClaims(other, 0, 1)[0].amount), 3e6);
    }

    // ---------------------------------------------------------------- index arrays

    function test_retainersOfClient_severalRetainers_listsIdsInCreationOrder() public {
        _createFor(client, freelancer, 1e6); // 0
        _createFor(client2, freelancer, 1e6); // 1
        _createFor(client, freelancer2, 1e6); // 2
        _createFor(client, freelancer, 0); // 3

        uint256[] memory mine = retainer.retainersOfClient(client);
        assertEq(mine.length, 3);
        assertEq(mine[0], 0);
        assertEq(mine[1], 2);
        assertEq(mine[2], 3);

        uint256[] memory other = retainer.retainersOfClient(client2);
        assertEq(other.length, 1);
        assertEq(other[0], 1);
        assertEq(retainer.nextRetainerId(), 4);
    }

    function test_retainersOfFreelancer_sameFreelancerAcrossSeveralClients_listsAllInOrder() public {
        _createFor(client, freelancer, 1e6); // 0
        _createFor(client2, freelancer, 1e6); // 1
        _createFor(client, freelancer2, 1e6); // 2
        _createFor(stranger, freelancer, 0); // 3

        uint256[] memory f1 = retainer.retainersOfFreelancer(freelancer);
        assertEq(f1.length, 3);
        assertEq(f1[0], 0);
        assertEq(f1[1], 1);
        assertEq(f1[2], 3);

        uint256[] memory f2 = retainer.retainersOfFreelancer(freelancer2);
        assertEq(f2.length, 1);
        assertEq(f2[0], 2);
    }

    function test_retainersOfClientAndFreelancer_strangerAndZeroAddress_returnEmpty() public {
        _createFor(client, freelancer, 1e6);

        assertEq(retainer.retainersOfClient(stranger).length, 0);
        assertEq(retainer.retainersOfFreelancer(stranger).length, 0);
        assertEq(retainer.retainersOfClient(address(0)).length, 0);
        assertEq(retainer.retainersOfFreelancer(address(0)).length, 0);
        // A party is not listed on the opposite side.
        assertEq(retainer.retainersOfFreelancer(client).length, 0);
        assertEq(retainer.retainersOfClient(freelancer).length, 0);
    }

    function test_retainersOfClient_freshContract_returnsEmpty() public view {
        assertEq(retainer.retainersOfClient(client).length, 0);
        assertEq(retainer.retainersOfFreelancer(freelancer).length, 0);
        assertEq(retainer.nextRetainerId(), 0);
    }

    function test_retainersOfClient_unaffectedByLaterActivity() public {
        uint256 id = _createFor(client, freelancer, 5e6);
        _request(id, 1e6);
        vm.warp(END);
        vm.prank(client);
        retainer.extendEndTime(id, END + 1);

        uint256[] memory mine = retainer.retainersOfClient(client);
        assertEq(mine.length, 1);
        assertEq(mine[0], id);
        assertEq(retainer.retainersOfFreelancer(freelancer).length, 1);
    }
}
