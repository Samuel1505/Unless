// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";

import {UnlessRetainer} from "../UnlessRetainer.sol";
import {UnlessRetainerExtBase} from "./UnlessRetainer.ExtBase.t.sol";

/// @notice 4.9 withdrawal lifecycle: completeWithdrawal (anyone calls, only the client is paid).
contract UnlessRetainerCompleteWithdrawalTest is UnlessRetainerExtBase {
    UnlessRetainer.ClaimStatus internal constant PENDING = UnlessRetainer.ClaimStatus.Pending;
    UnlessRetainer.ClaimStatus internal constant PAID = UnlessRetainer.ClaimStatus.Paid;

    // ---------------------------------------------------------------- notice boundaries

    function test_completeWithdrawal_oneSecondBeforeReadyAt_revertsNoticeNotElapsed() public {
        uint256 id = _create(10e6);
        _request(id, 4e6);
        uint64 readyAt = _readyAt(id);
        vm.warp(uint256(readyAt) - 1);

        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NoticeNotElapsed.selector);
        retainer.completeWithdrawal(id);
        _assertWithdrawal(id, 4e6, readyAt);
    }

    function test_completeWithdrawal_inSameBlockAsRequest_revertsNoticeNotElapsed() public {
        uint256 id = _create(10e6);
        _request(id, 4e6);

        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NoticeNotElapsed.selector);
        retainer.completeWithdrawal(id);
    }

    function test_completeWithdrawal_atReadyAt_succeeds() public {
        uint256 id = _create(10e6);
        _request(id, 4e6);
        vm.warp(_readyAt(id));

        _expectWdCompleted(id, 4e6, 4e6);
        _complete(id);

        _assertNoWithdrawal(id);
        _assertAcct(id, 6e6, 0, 10e6, 0, 4e6, 0);
    }

    function test_completeWithdrawal_oneSecondAfterReadyAt_succeeds() public {
        uint256 id = _create(10e6);
        _request(id, 4e6);
        vm.warp(uint256(_readyAt(id)) + 1);

        _expectWdCompleted(id, 4e6, 4e6);
        _complete(id);

        _assertAcct(id, 6e6, 0, 10e6, 0, 4e6, 0);
    }

    // ---------------------------------------------------------------- payout goes to the client

    function test_completeWithdrawal_byStranger_paysClientAndEmitsFullEvent() public {
        uint256 id = _create(10e6);
        _request(id, 4e6);
        vm.warp(_readyAt(id));
        uint256 clientBefore = usdc.balanceOf(client);
        uint256 strangerBefore = usdc.balanceOf(stranger);

        _expectWdCompleted(id, 4e6, 4e6);
        _expectTransfer(address(retainer), client, 4e6);
        vm.prank(stranger);
        retainer.completeWithdrawal(id);

        assertEq(usdc.balanceOf(client), clientBefore + 4e6, "client received payout");
        assertEq(usdc.balanceOf(stranger), strangerBefore, "stranger unchanged");
        assertEq(usdc.balanceOf(address(retainer)), 6e6, "contract holds the rest");
        _assertNoWithdrawal(id);
        _assertAcct(id, 6e6, 0, 10e6, 0, 4e6, 0);
        assertEq(retainer.owed(client), 0);
        assertEq(retainer.totalOwed(), 0);
        _assertSolvent();
    }

    function test_completeWithdrawal_byFreelancer_paysClientNotCaller() public {
        uint256 id = _create(10e6);
        _request(id, 4e6);
        vm.warp(_readyAt(id));
        uint256 clientBefore = usdc.balanceOf(client);

        _expectWdCompleted(id, 4e6, 4e6);
        vm.prank(freelancer);
        retainer.completeWithdrawal(id);

        assertEq(usdc.balanceOf(freelancer), START_BALANCE, "freelancer unchanged");
        assertEq(usdc.balanceOf(client), clientBefore + 4e6, "client received payout");
    }

    function test_completeWithdrawal_byClient_paysClient() public {
        uint256 id = _create(10e6);
        _request(id, 10e6);
        vm.warp(_readyAt(id));

        _expectWdCompleted(id, 10e6, 10e6);
        vm.prank(client);
        retainer.completeWithdrawal(id);

        assertEq(usdc.balanceOf(client), START_BALANCE);
        _assertAcct(id, 0, 0, 10e6, 0, 10e6, 0);
    }

    function test_completeWithdrawal_calledTwice_secondRevertsNoWithdrawalPending() public {
        uint256 id = _create(10e6);
        _request(id, 4e6);
        vm.warp(_readyAt(id));
        _complete(id);

        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NoWithdrawalPending.selector);
        retainer.completeWithdrawal(id);
    }

    // ---------------------------------------------------------------- notice protection

    function test_completeWithdrawal_requestAllFundsThenClaimFiledDuringNotice_paysRemainder() public {
        // deposit 7, request 7, freelancer files 3 during notice -> client receives 4.
        uint256 id = _create(7e6);
        _request(id, 7e6);
        vm.warp(block.timestamp + 1);
        uint256 claimId = _file(id, 3e6, "during notice");
        vm.warp(_readyAt(id));
        uint256 clientBefore = usdc.balanceOf(client);

        _expectWdCompleted(id, 7e6, 4e6);
        _expectTransfer(address(retainer), client, 4e6);
        _complete(id);

        assertEq(usdc.balanceOf(client), clientBefore + 4e6, "client received 4");
        _assertNoWithdrawal(id);
        _assertAcct(id, 3e6, 3e6, 7e6, 0, 4e6, 1);
        _assertClaimV(id, claimId, 3e6, PENDING, UnlessRetainer.PaidVia.None);
        _assertSolvent();

        // The reserved claim still pays the freelancer afterwards.
        vm.warp(_payableAtV(id, claimId));
        _payOut(id, claimId);
        _assertAcct(id, 0, 0, 7e6, 3e6, 4e6, 0);
        _assertClaimV(id, claimId, 3e6, PAID, UnlessRetainer.PaidVia.PaidOut);
        assertEq(usdc.balanceOf(freelancer), START_BALANCE + 3e6);
    }

    function test_completeWithdrawal_claimExceedsLeftoverDuringNotice_paysOnlyWhatIsStillAvailable() public {
        // deposit 10, request 7, freelancer files 6 -> available 4 -> client receives 4.
        uint256 id = _create(10e6);
        _request(id, 7e6);
        _file(id, 6e6, "big");
        vm.warp(_readyAt(id));

        _expectWdCompleted(id, 7e6, 4e6);
        _complete(id);

        _assertAcct(id, 6e6, 6e6, 10e6, 0, 4e6, 1);
        assertEq(usdc.balanceOf(client), START_BALANCE - 10e6 + 4e6);
    }

    function test_completeWithdrawal_claimLeavesEnoughAvailable_paysFullRequest() public {
        // deposit 10, request 7, freelancer files 3 -> available 7 still covers the request.
        uint256 id = _create(10e6);
        _request(id, 7e6);
        _file(id, 3e6, "small");
        vm.warp(_readyAt(id));

        _expectWdCompleted(id, 7e6, 7e6);
        _complete(id);

        _assertAcct(id, 3e6, 3e6, 10e6, 0, 7e6, 1);
    }

    function test_completeWithdrawal_claimApprovedDuringNotice_paysMinOfRequestedAndAvailable() public {
        // Worked-example shape: request 8 of 10, file 3, approve now -> balance 7, available 7 -> pays 7.
        uint256 id = _create(10e6);
        _request(id, 8e6);
        uint256 claimId = _file(id, 3e6, "approved");
        _approveNow(id, claimId);
        vm.warp(_readyAt(id));

        _expectWdCompleted(id, 8e6, 7e6);
        _complete(id);

        _assertAcct(id, 0, 0, 10e6, 3e6, 7e6, 0);
        assertEq(usdc.balanceOf(address(retainer)), 0);
        _assertSolvent();
    }

    // ---------------------------------------------------------------- zero completion

    function test_completeWithdrawal_allRequestedMoneyClaimedMeanwhile_emitsZeroPaidAndMovesNothing() public {
        uint256 id = _create(5e6);
        _request(id, 5e6);
        uint256 claimId = _file(id, 5e6, "everything");
        vm.warp(_readyAt(id));
        uint256 clientBefore = usdc.balanceOf(client);
        uint256 retainerBefore = usdc.balanceOf(address(retainer));

        vm.recordLogs();
        _expectWdCompleted(id, 5e6, 0);
        _complete(id);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // The `emit` inside the expectEmit helper is itself recorded (emitter == this test): skip it.
        Vm.Log[] memory real = _foreignLogs(logs);
        assertEq(real.length, 1, "no token Transfer and no other event");
        assertEq(real[0].emitter, address(retainer));
        assertEq(real[0].topics[0], UnlessRetainer.WithdrawalCompleted.selector);
        assertEq(usdc.balanceOf(client), clientBefore, "client unchanged");
        assertEq(usdc.balanceOf(address(retainer)), retainerBefore, "contract unchanged");
        _assertNoWithdrawal(id);
        _assertAcct(id, 5e6, 5e6, 5e6, 0, 0, 1);
        _assertClaimV(id, claimId, 5e6, PENDING, UnlessRetainer.PaidVia.None);
        assertEq(retainer.totalOwed(), 0, "no credit created");
    }

    function test_completeWithdrawal_afterZeroCompletion_newRequestAndClaimStillPayable() public {
        uint256 id = _create(5e6);
        _request(id, 5e6);
        uint256 claimId = _file(id, 5e6, "everything");
        vm.warp(_readyAt(id));
        _complete(id);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.InsufficientAvailable.selector);
        retainer.requestWithdrawal(id, 1);

        _payOut(id, claimId);
        _assertAcct(id, 0, 0, 5e6, 5e6, 0, 0);
        assertEq(usdc.balanceOf(freelancer), START_BALANCE + 5e6);
    }

    // ---------------------------------------------------------------- after end

    function test_completeWithdrawal_afterEndTime_succeeds() public {
        uint256 id = _create(10e6);
        _request(id, 4e6);
        vm.warp(uint256(END) + 100);
        assertTrue(_isEnded(id));

        _expectWdCompleted(id, 4e6, 4e6);
        _complete(id);

        _assertAcct(id, 6e6, 0, 10e6, 0, 4e6, 0);
        assertEq(usdc.balanceOf(client), START_BALANCE - 10e6 + 4e6);
    }

    function test_completeWithdrawal_atEndTimeBoundary_succeeds() public {
        uint256 id = _create(10e6);
        vm.warp(uint256(END) - NOTICE); // request lands exactly NOTICE before end -> readyAt == END
        _request(id, 4e6);
        assertEq(uint256(_readyAt(id)), uint256(END));
        vm.warp(END);
        assertTrue(_isEnded(id));

        _expectWdCompleted(id, 4e6, 4e6);
        _complete(id);

        _assertAcct(id, 6e6, 0, 10e6, 0, 4e6, 0);
    }

    // ---------------------------------------------------------------- reverts

    function test_completeWithdrawal_nonePending_revertsNoWithdrawalPending() public {
        uint256 id = _create(10e6);

        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NoWithdrawalPending.selector);
        retainer.completeWithdrawal(id);
    }

    function test_completeWithdrawal_nonePendingLongAfter_revertsNoWithdrawalPending() public {
        uint256 id = _create(10e6);
        vm.warp(uint256(END) + 365 days);

        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NoWithdrawalPending.selector);
        retainer.completeWithdrawal(id);
    }

    function test_completeWithdrawal_cancelledBeforeReadyAt_revertsNoWithdrawalPendingNotNoticeNotElapsed()
        public
    {
        uint256 id = _create(10e6);
        _request(id, 4e6);
        _cancelWd(id);
        // now < the old readyAt: with a request cleared the error must be NoWithdrawalPending.
        vm.warp(block.timestamp + 1);

        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NoWithdrawalPending.selector);
        retainer.completeWithdrawal(id);
    }

    function test_completeWithdrawal_unknownId_revertsRetainerNotFound() public {
        _create(10e6);

        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.RetainerNotFound.selector);
        retainer.completeWithdrawal(1);
    }

    function test_completeWithdrawal_maxId_revertsRetainerNotFound() public {
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.RetainerNotFound.selector);
        retainer.completeWithdrawal(type(uint256).max);
    }
}
