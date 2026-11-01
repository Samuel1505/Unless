// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UnlessRetainer} from "../UnlessRetainer.sol";
import {UnlessRetainerExtBase} from "./UnlessRetainer.ExtBase.t.sol";

/// @notice 04-TEST-PLAN 4.16: testFuzz_window_boundaries. Objection and execution are disjoint
/// and exhaustive for a pending claim: at every offset exactly one of them is possible.
contract UnlessRetainerWindowFuzzTest is UnlessRetainerExtBase {
    function testFuzz_window_boundaries(uint32 window, uint32 offset) public {
        uint32 w = uint32(bound(uint256(window), MIN_WINDOW, MAX_WINDOW));
        uint256 off = bound(uint256(offset), 0, uint256(w) * 2);

        _approve(client, 5e6);
        vm.prank(client);
        uint256 id = retainer.createRetainer(freelancer, w, NOTICE, END, 5e6);
        uint256 claimId = _file(id, 5e6, "fuzz");
        uint256 filedAt = block.timestamp;
        uint256 payableAt = filedAt + uint256(w);
        assertEq(uint256(_payableAtV(id, claimId)), payableAt, "payableAt == filedAt + window");

        vm.warp(filedAt + off);
        uint256 snap = vm.snapshotState();

        // ---- Path 1: the client tries to object.
        if (off < uint256(w)) {
            _expectObjected(id, claimId, "fuzz");
            vm.prank(client);
            retainer.objectToClaim(id, claimId, "fuzz");
            _assertClaimV(id, claimId, 5e6, UnlessRetainer.ClaimStatus.Objected, UnlessRetainer.PaidVia.None);
            _assertAcct(id, 5e6, 0, 5e6, 0, 0, 0);
            // Once objected, a payout is impossible regardless of time.
            vm.prank(stranger);
            vm.expectRevert(UnlessRetainer.ClaimNotPending.selector);
            retainer.payOutClaim(id, claimId);
        } else {
            vm.prank(client);
            vm.expectRevert(UnlessRetainer.ObjectionWindowClosed.selector);
            retainer.objectToClaim(id, claimId, "fuzz");
            _assertClaimV(id, claimId, 5e6, UnlessRetainer.ClaimStatus.Pending, UnlessRetainer.PaidVia.None);
            _assertAcct(id, 5e6, 5e6, 5e6, 0, 0, 1);
        }

        // ---- Path 2 (same state, same instant): anyone tries to pay out.
        assertTrue(vm.revertToState(snap), "snapshot restored");
        assertEq(block.timestamp, filedAt + off, "time preserved by snapshot");
        if (off < uint256(w)) {
            vm.prank(stranger);
            vm.expectRevert(UnlessRetainer.ObjectionWindowOpen.selector);
            retainer.payOutClaim(id, claimId);
            _assertClaimV(id, claimId, 5e6, UnlessRetainer.ClaimStatus.Pending, UnlessRetainer.PaidVia.None);
            _assertAcct(id, 5e6, 5e6, 5e6, 0, 0, 1);
        } else {
            _expectPaid(id, claimId, freelancer, 5e6, UnlessRetainer.PaidVia.PaidOut);
            vm.prank(stranger);
            retainer.payOutClaim(id, claimId);
            _assertClaimV(id, claimId, 5e6, UnlessRetainer.ClaimStatus.Paid, UnlessRetainer.PaidVia.PaidOut);
            _assertAcct(id, 0, 0, 5e6, 5e6, 0, 0);
            assertEq(usdc.balanceOf(freelancer), START_BALANCE + 5e6, "freelancer paid");
            assertEq(usdc.balanceOf(stranger), START_BALANCE, "stranger gained nothing");
            // A paid claim cannot be objected to afterwards either.
            vm.prank(client);
            vm.expectRevert(UnlessRetainer.ClaimNotPending.selector);
            retainer.objectToClaim(id, claimId, "late");
        }
    }

    /// @dev The exact edges, independent of the fuzzed offset: payableAt - 1, payableAt, payableAt + 1.
    function testFuzz_window_exactEdges(uint32 window) public {
        uint32 w = uint32(bound(uint256(window), MIN_WINDOW, MAX_WINDOW));
        _approve(client, 3e6);
        vm.prank(client);
        uint256 id = retainer.createRetainer(freelancer, w, NOTICE, END, 3e6);
        uint256 c0 = _file(id, 1e6, "a");
        uint256 c1 = _file(id, 1e6, "b");
        uint256 c2 = _file(id, 1e6, "c");
        uint256 payableAt = _payableAtV(id, c0);

        vm.warp(payableAt - 1);
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.ObjectionWindowOpen.selector);
        retainer.payOutClaim(id, c0);
        _object(id, c0); // still objectable one second before

        vm.warp(payableAt);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.ObjectionWindowClosed.selector);
        retainer.objectToClaim(id, c1, "x");
        _payOut(id, c1); // payable exactly at payableAt

        vm.warp(payableAt + 1);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.ObjectionWindowClosed.selector);
        retainer.objectToClaim(id, c2, "x");
        _payOut(id, c2);
        _assertAcct(id, 1e6, 0, 3e6, 2e6, 0, 0);
    }
}
