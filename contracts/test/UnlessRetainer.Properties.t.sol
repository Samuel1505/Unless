// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {UnlessRetainer} from "../UnlessRetainer.sol";
import {UnlessRetainerBase} from "./UnlessRetainer.Base.t.sol";

/// @notice Cross-cutting properties: isolation (4.13 subset), conservation, and stateless fuzz (4.16 subset).
contract UnlessRetainerPropertiesTest is UnlessRetainerBase {
    using SafeCast for uint256;

    // ---------------------------------------------------------------- isolation

    function test_actionsOnOneRetainer_leaveAnotherRetainerCompletelyUntouched() public {
        uint256 a = _create(10e6);
        uint256 b = _createFor(client2, freelancer2, 8e6);
        vm.prank(freelancer2);
        retainer.fileClaim(b, 2e6, "pending on b");

        bytes32 retainerBefore = keccak256(abi.encode(retainer.retainerOf(b)));
        bytes32 claimBefore = keccak256(abi.encode(retainer.claimOf(b, 0)));
        uint256 client2Tokens = usdc.balanceOf(client2);
        uint256 freelancer2Tokens = usdc.balanceOf(freelancer2);

        // Every state-changing action on retainer `a`.
        _file(a, 4e6, "0");
        _file(a, 3e6, "1");
        _file(a, 2e6, "2");
        _file(a, 1e6, "3");
        _approveNow(a, 0);
        _object(a, 1);
        _cancel(a, 2);
        vm.warp(_payableAt(a, 3));
        _payOut(a, 3);
        _approve(client, 1e6);
        vm.prank(client);
        retainer.deposit(a, 1e6);

        assertEq(keccak256(abi.encode(retainer.retainerOf(b))), retainerBefore, "retainer b fields");
        assertEq(keccak256(abi.encode(retainer.claimOf(b, 0))), claimBefore, "claim b");
        assertEq(usdc.balanceOf(client2), client2Tokens, "client2 tokens");
        assertEq(usdc.balanceOf(freelancer2), freelancer2Tokens, "freelancer2 tokens");
        _assertState(b, 8e6, 2e6, 8e6, 0, 0, 1);
        _assertState(a, 6e6, 0, 11e6, 5e6, 0, 0);
    }

    function test_payOutAndApprove_onSecondRetainer_leaveFirstRetainerUntouched() public {
        uint256 a = _create(10e6);
        _file(a, 3e6, "a");
        uint256 b = _createFor(client2, freelancer2, 5e6);
        vm.prank(freelancer2);
        retainer.fileClaim(b, 1e6, "b0");
        vm.prank(freelancer2);
        retainer.fileClaim(b, 2e6, "b1");

        bytes32 retainerBefore = keccak256(abi.encode(retainer.retainerOf(a)));
        bytes32 claimBefore = keccak256(abi.encode(retainer.claimOf(a, 0)));
        uint256 clientTokens = usdc.balanceOf(client);
        uint256 freelancerTokens = usdc.balanceOf(freelancer);

        vm.prank(client2);
        retainer.approveClaim(b, 0);
        vm.warp(_payableAt(b, 1));
        _payOut(b, 1);

        assertEq(keccak256(abi.encode(retainer.retainerOf(a))), retainerBefore, "retainer a fields");
        assertEq(keccak256(abi.encode(retainer.claimOf(a, 0))), claimBefore, "claim a");
        assertEq(usdc.balanceOf(client), clientTokens);
        assertEq(usdc.balanceOf(freelancer), freelancerTokens);
        _assertState(b, 2e6, 0, 5e6, 3e6, 0, 0);
    }

    // ---------------------------------------------------------------- conservation

    function test_mixedActions_conserveFundsAndReservations() public {
        uint256 a = _create(100e6);
        uint256 b = _createFor(client2, freelancer2, 40e6);
        _approve(client, 20e6);
        vm.prank(client);
        retainer.deposit(a, 20e6);

        uint128[5] memory amounts = [uint128(10e6), uint128(20e6), uint128(5e6), uint128(15e6), uint128(8e6)];
        for (uint256 i = 0; i < amounts.length; i++) {
            _file(a, amounts[i], "claim");
        }
        vm.prank(freelancer2);
        retainer.fileClaim(b, 12e6, "b claim");
        vm.prank(freelancer2);
        retainer.fileClaim(b, 3e6, "b claim 2");

        _approveNow(a, 1); // paid, ApprovedNow
        _object(a, 2); // objected
        _cancel(a, 3); // cancelled
        vm.warp(_payableAt(a, 0));
        _payOut(a, 0); // paid, PaidOut
        vm.prank(client2);
        retainer.approveClaim(b, 1);
        // a: claim 4 (8e6) still pending; b: claim 0 (12e6) still pending.

        _assertConserved(a);
        _assertConserved(b);
        _assertState(a, 90e6, 8e6, 120e6, 30e6, 0, 1);
        _assertState(b, 37e6, 12e6, 40e6, 3e6, 0, 1);
        assertEq(
            usdc.balanceOf(address(retainer)),
            uint256(retainer.retainerOf(a).balance) + uint256(retainer.retainerOf(b).balance)
                + retainer.totalOwed(),
            "token balance == sum of balances + totalOwed"
        );
    }

    function _assertConserved(uint256 id) internal view {
        UnlessRetainer.Retainer memory r = retainer.retainerOf(id);
        assertEq(
            uint256(r.totalDeposited),
            uint256(r.balance) + uint256(r.totalPaid) + uint256(r.totalReturned),
            "totalDeposited == balance + totalPaid + totalReturned"
        );
        uint256 pendingSum;
        uint256 pendingCount;
        for (uint256 i = 0; i < r.claimCount; i++) {
            UnlessRetainer.Claim memory c = retainer.claimOf(id, i);
            if (c.status == UnlessRetainer.ClaimStatus.Pending) {
                pendingSum += c.amount;
                pendingCount++;
            }
        }
        assertEq(uint256(r.reserved), pendingSum, "reserved == sum of pending");
        assertEq(uint256(r.pendingClaims), pendingCount, "pendingClaims == count of pending");
        assertLe(uint256(r.reserved), uint256(r.balance), "reserved <= balance");
    }

    // ---------------------------------------------------------------- fuzz

    function testFuzz_fileClaim_neverExceedsAvailable(uint128 deposit, uint128 amount) public {
        uint256 dep = bound(uint256(deposit), 1, 1_000e6);
        uint256 amt = bound(uint256(amount), 1, dep * 2);
        uint256 id = _create(dep.toUint128());

        // Pre-reserve half so that available != balance.
        uint256 pre = dep / 2;
        if (pre > 0) _file(id, pre.toUint128(), "pre");
        uint256 available = dep - pre;
        assertEq(retainer.availableOf(id), available);

        if (amt > available) {
            vm.prank(freelancer);
            vm.expectRevert(UnlessRetainer.InsufficientAvailable.selector);
            retainer.fileClaim(id, amt.toUint128(), "fuzz");
            _assertState(id, dep, pre, dep, 0, 0, pre > 0 ? 1 : 0);
        } else {
            uint64 payableAt = uint64(block.timestamp) + WINDOW;
            uint256 expectedId = pre > 0 ? 1 : 0;
            _expectFiled(id, expectedId, amt.toUint128(), payableAt, "fuzz");
            vm.prank(freelancer);
            uint256 claimId = retainer.fileClaim(id, amt.toUint128(), "fuzz");
            assertEq(claimId, expectedId);
            _assertState(id, dep, pre + amt, dep, 0, 0, pre > 0 ? 2 : 1);
        }
        UnlessRetainer.Retainer memory r = retainer.retainerOf(id);
        assertEq(uint256(r.reserved) + retainer.availableOf(id), uint256(r.balance), "reserved + available == balance");
        assertLe(uint256(r.reserved), uint256(r.balance));
    }

    function testFuzz_payOut_window_boundaries(uint32 window, uint32 offset) public {
        uint32 w = uint32(bound(uint256(window), MIN_WINDOW, MAX_WINDOW));
        uint256 off = bound(uint256(offset), 0, uint256(w) * 2);

        _approve(client, 1e6);
        vm.prank(client);
        uint256 id = retainer.createRetainer(freelancer, w, NOTICE, END, 1e6);
        uint256 claimId = _file(id, 1e6, "fuzz");
        uint256 filedAt = block.timestamp;
        assertEq(uint256(_payableAt(id, claimId)), filedAt + uint256(w));

        vm.warp(filedAt + off);
        if (off < uint256(w)) {
            vm.prank(stranger);
            vm.expectRevert(UnlessRetainer.ObjectionWindowOpen.selector);
            retainer.payOutClaim(id, claimId);
            _assertState(id, 1e6, 1e6, 1e6, 0, 0, 1);
        } else {
            _expectPaid(id, claimId, freelancer, 1e6, UnlessRetainer.PaidVia.PaidOut);
            vm.prank(stranger);
            retainer.payOutClaim(id, claimId);
            _assertState(id, 0, 0, 1e6, 1e6, 0, 0);
            assertEq(usdc.balanceOf(freelancer), START_BALANCE + 1e6);
        }
    }
}
