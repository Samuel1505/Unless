// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UnlessRetainer} from "../UnlessRetainer.sol";
import {UnlessRetainerExtBase} from "./UnlessRetainer.ExtBase.t.sol";

/// @notice 04-TEST-PLAN 4.15: replays 03-CONTRACT-SPEC section 14 row by row.
/// After every row the balance / reserved / available columns and every actor's token balance are
/// asserted through the real views and the token. t is measured from the create transaction.
contract UnlessRetainerWorkedExampleTest is UnlessRetainerExtBase {
    uint256 internal constant U = 1e6; // one USDC (6 dp)

    uint256 internal start;
    uint256 internal id;

    // Token balances at the start (before any row).
    uint256 internal c0;
    uint256 internal f0;
    uint256 internal s0;

    /// @dev Asserts the table columns (balance, reserved, available) and pendingClaims / totals
    /// straight from getRetainer, then the four token balances.
    function _row(
        uint256 balance,
        uint256 reserved,
        uint256 pending,
        uint256 totalPaid,
        uint256 totalReturned,
        uint256 clientTok,
        uint256 freelancerTok,
        uint256 strangerTok,
        uint256 retainerTok
    ) internal view {
        (UnlessRetainer.Retainer memory r, uint256 available,) = retainer.getRetainer(id);
        assertEq(uint256(r.balance), balance, "balance");
        assertEq(uint256(r.reserved), reserved, "reserved");
        assertEq(available, balance - reserved, "available");
        assertEq(uint256(r.pendingClaims), pending, "pendingClaims");
        assertEq(uint256(r.totalPaid), totalPaid, "totalPaid");
        assertEq(uint256(r.totalReturned), totalReturned, "totalReturned");
        assertEq(usdc.balanceOf(client), clientTok, "client token balance");
        assertEq(usdc.balanceOf(freelancer), freelancerTok, "freelancer token balance");
        assertEq(usdc.balanceOf(stranger), strangerTok, "stranger token balance");
        assertEq(usdc.balanceOf(address(retainer)), retainerTok, "retainer token balance");
        assertEq(retainer.totalOwed(), 0, "totalOwed");
    }

    function test_workedExample_matchesSpecTable() public {
        c0 = usdc.balanceOf(client);
        f0 = usdc.balanceOf(freelancer);
        s0 = usdc.balanceOf(stranger);
        assertEq(c0, START_BALANCE);

        start = block.timestamp;
        END = uint64(start + 7 days);

        // ---- t = 0: create + deposit 10 -> balance 10, reserved 0, available 10
        _approve(client, 10 * U);
        _expectCreated(0, client, freelancer, WINDOW, NOTICE, END);
        _expectDeposited(0, client, uint128(10 * U), uint128(10 * U));
        vm.prank(client);
        id = retainer.createRetainer(freelancer, WINDOW, NOTICE, END, uint128(10 * U));
        assertEq(id, 0, "first retainer id");
        assertEq(retainer.nextRetainerId(), 1);
        {
            UnlessRetainer.Retainer memory r = _ret(id);
            assertEq(uint256(r.totalDeposited), 10 * U, "totalDeposited");
            assertEq(uint256(r.createdAt), start, "createdAt");
        }
        _row(10 * U, 0, 0, 0, 0, c0 - 10 * U, f0, s0, 10 * U);

        // ---- t = 30: freelancer files claim #0 for 3 -> 10 / 3 / 7, payableAt = 330
        vm.warp(start + 30);
        _expectFiled(id, 0, uint128(3 * U), uint64(start + 330), "claim 0");
        vm.prank(freelancer);
        assertEq(retainer.fileClaim(id, uint128(3 * U), "claim 0"), 0, "claimId 0");
        assertEq(uint256(_claimV(id, 0).payableAt), start + 330, "payableAt #0 == 330");
        assertEq(uint256(_claimV(id, 0).filedAt), start + 30, "filedAt #0");
        _assertClaimV(id, 0, 3 * U, UnlessRetainer.ClaimStatus.Pending, UnlessRetainer.PaidVia.None);
        _row(10 * U, 3 * U, 1, 0, 0, c0 - 10 * U, f0, s0, 10 * U);

        // ---- t = 30..330: the client does nothing. t = 329 is still too early.
        vm.warp(start + 329);
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.ObjectionWindowOpen.selector);
        retainer.payOutClaim(id, 0);

        // ---- t = 330: the STRANGER pays out #0 (silent payout) -> 7 / 0 / 7, freelancer +3
        vm.warp(start + 330);
        _expectPaid(id, 0, freelancer, uint128(3 * U), UnlessRetainer.PaidVia.PaidOut);
        vm.prank(stranger);
        retainer.payOutClaim(id, 0);
        _assertClaimV(id, 0, 3 * U, UnlessRetainer.ClaimStatus.Paid, UnlessRetainer.PaidVia.PaidOut);
        assertEq(usdc.balanceOf(freelancer), f0 + 3 * U, "freelancer +3");
        assertEq(usdc.balanceOf(stranger), s0, "stranger unchanged");
        _row(7 * U, 0, 0, 3 * U, 0, c0 - 10 * U, f0 + 3 * U, s0, 7 * U);

        // ---- t = 360: freelancer files #1 for 2 -> 7 / 2 / 5, payableAt = 660
        vm.warp(start + 360);
        _expectFiled(id, 1, uint128(2 * U), uint64(start + 660), "claim 1");
        vm.prank(freelancer);
        assertEq(retainer.fileClaim(id, uint128(2 * U), "claim 1"), 1, "claimId 1");
        assertEq(uint256(_claimV(id, 1).payableAt), start + 660, "payableAt #1 == 660");
        _row(7 * U, 2 * U, 1, 3 * U, 0, c0 - 10 * U, f0 + 3 * U, s0, 7 * U);

        // ---- t = 400: client objects to #1 -> 7 / 0 / 7, no USDC moves
        vm.warp(start + 400);
        _expectObjected(id, 1, "too much");
        vm.prank(client);
        retainer.objectToClaim(id, 1, "too much");
        _assertClaimV(id, 1, 2 * U, UnlessRetainer.ClaimStatus.Objected, UnlessRetainer.PaidVia.None);
        _row(7 * U, 0, 0, 3 * U, 0, c0 - 10 * U, f0 + 3 * U, s0, 7 * U);

        // ---- t = 420: client requests withdrawal of 7 -> 7 / 0 / 7, readyAt = 720
        vm.warp(start + 420);
        _expectRequested(id, uint128(7 * U), uint64(start + 720));
        vm.prank(client);
        retainer.requestWithdrawal(id, uint128(7 * U));
        _assertWithdrawal(id, 7 * U, start + 720);
        _row(7 * U, 0, 0, 3 * U, 0, c0 - 10 * U, f0 + 3 * U, s0, 7 * U);

        // ---- t = 450: freelancer files #2 for 1 during notice -> 7 / 1 / 6
        vm.warp(start + 450);
        _expectFiled(id, 2, uint128(1 * U), uint64(start + 750), "claim 2");
        vm.prank(freelancer);
        assertEq(retainer.fileClaim(id, uint128(1 * U), "claim 2"), 2, "claimId 2");
        _assertWithdrawal(id, 7 * U, start + 720);
        _row(7 * U, 1 * U, 1, 3 * U, 0, c0 - 10 * U, f0 + 3 * U, s0, 7 * U);

        // ---- t = 460: client approves #2 now -> 6 / 0 / 6, freelancer +1
        vm.warp(start + 460);
        _expectPaid(id, 2, freelancer, uint128(1 * U), UnlessRetainer.PaidVia.ApprovedNow);
        vm.prank(client);
        retainer.approveClaim(id, 2);
        _assertClaimV(id, 2, 1 * U, UnlessRetainer.ClaimStatus.Paid, UnlessRetainer.PaidVia.ApprovedNow);
        assertEq(usdc.balanceOf(freelancer), f0 + 4 * U, "freelancer +1 more");
        _assertWithdrawal(id, 7 * U, start + 720);
        _row(6 * U, 0, 0, 4 * U, 0, c0 - 10 * U, f0 + 4 * U, s0, 6 * U);

        // ---- t = 719 is too early; t = 720: anyone completes -> 0 / 0 / 0, client receives min(7, 6) = 6
        vm.warp(start + 719);
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NoticeNotElapsed.selector);
        retainer.completeWithdrawal(id);

        vm.warp(start + 720);
        _expectWdCompleted(id, uint128(7 * U), uint128(6 * U));
        vm.prank(stranger);
        retainer.completeWithdrawal(id);
        _assertNoWithdrawal(id);
        _row(0, 0, 0, 4 * U, 6 * U, c0 - 4 * U, f0 + 4 * U, s0, 0);

        // ---- Spec check I-4: deposited 10 == balance 0 + paid 4 + returned 6
        UnlessRetainer.Retainer memory f = _ret(id);
        assertEq(uint256(f.totalDeposited), 10 * U, "deposited 10");
        assertEq(uint256(f.balance) + uint256(f.totalPaid) + uint256(f.totalReturned), uint256(f.totalDeposited), "I-4");
        assertEq(uint256(f.balance), 0);
        assertEq(uint256(f.totalPaid), 4 * U);
        assertEq(uint256(f.totalReturned), 6 * U);
        // Final token balances: freelancer +4, client net -4, stranger 0, retainer 0.
        assertEq(usdc.balanceOf(freelancer), f0 + 4 * U, "freelancer +4");
        assertEq(usdc.balanceOf(client), c0 - 4 * U, "client net -4");
        assertEq(usdc.balanceOf(stranger), s0, "stranger unchanged");
        assertEq(usdc.balanceOf(address(retainer)), 0, "retainer empty");
    }
}
