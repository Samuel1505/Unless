// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UnlessRetainer} from "../UnlessRetainer.sol";
import {UnlessRetainerExtBase} from "./UnlessRetainer.ExtBase.t.sol";

/// @notice 4.16 stateless fuzz for the withdrawal path. State is read through the view functions.
contract UnlessRetainerWithdrawalFuzzTest is UnlessRetainerExtBase {
    function testFuzz_completeWithdrawal_paysMinOfRequestedAndAvailable(
        uint128 deposit,
        uint128 request,
        uint128 claim
    ) public {
        uint128 dep = uint128(bound(deposit, 1, 1_000_000e6));
        uint128 req = uint128(bound(request, 1, dep));
        uint128 clm = uint128(bound(claim, 0, dep));
        usdc.mint(client, dep);

        uint256 id = _create(dep);
        _request(id, req);
        if (clm > 0) _file(id, clm, "fuzz"); // allowed during notice: the request reserved nothing
        vm.warp(_readyAt(id));

        uint128 availableAtCompletion = dep - clm;
        uint128 expectedPaid = req < availableAtCompletion ? req : availableAtCompletion;
        uint256 clientBefore = usdc.balanceOf(client);

        _expectWdCompleted(id, req, expectedPaid);
        _complete(id);

        assertEq(usdc.balanceOf(client), clientBefore + expectedPaid, "client received min(requested, available)");
        assertEq(usdc.balanceOf(address(retainer)), uint256(dep) - expectedPaid, "contract keeps the rest");
        _assertNoWithdrawal(id);
        _assertAcct(id, dep - expectedPaid, clm, dep, 0, expectedPaid, clm > 0 ? 1 : 0);

        // Invariant: balance == totalDeposited - totalPaid - totalReturned.
        UnlessRetainer.Retainer memory r = _ret(id);
        assertEq(uint256(r.balance), uint256(r.totalDeposited) - r.totalPaid - r.totalReturned);
        // The reserved claim is never touched by the completion.
        assertGe(uint256(r.balance), uint256(r.reserved));
        assertEq(retainer.totalOwed(), 0);
        _assertSolvent();
    }

    function testFuzz_withdrawal_notice_boundaries(uint32 notice, uint32 offset) public {
        uint32 n = uint32(bound(notice, MIN_NOTICE, MAX_NOTICE));
        uint32 elapsed = uint32(bound(offset, 0, uint256(n) * 2));
        uint64 farEnd = uint64(block.timestamp) + uint64(MAX_NOTICE) + 365 days;

        _approve(client, 10e6);
        vm.prank(client);
        uint256 id = retainer.createRetainer(freelancer, WINDOW, n, farEnd, 10e6);
        uint64 t0 = uint64(block.timestamp);
        _request(id, 4e6);
        uint64 readyAt = _readyAt(id);
        assertEq(uint256(readyAt), uint256(t0) + n, "readyAt == now + notice");

        // The exact edge never depends on the fuzzed offset.
        vm.warp(uint256(readyAt) - 1);
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NoticeNotElapsed.selector);
        retainer.completeWithdrawal(id);

        vm.warp(uint256(t0) + elapsed);
        if (elapsed < n) {
            vm.prank(stranger);
            vm.expectRevert(UnlessRetainer.NoticeNotElapsed.selector);
            retainer.completeWithdrawal(id);
            _assertWithdrawal(id, 4e6, readyAt);
        } else {
            _expectWdCompleted(id, 4e6, 4e6);
            _complete(id);
            _assertNoWithdrawal(id);
            _assertAcct(id, 6e6, 0, 10e6, 0, 4e6, 0);
            assertEq(usdc.balanceOf(client), START_BALANCE - 6e6);
        }
    }
}
