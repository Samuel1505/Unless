// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UnlessRetainer} from "../UnlessRetainer.sol";
import {UnlessRetainerExtBase} from "./UnlessRetainer.ExtBase.t.sol";

/// @notice 4.9 withdrawal lifecycle: requestWithdrawal.
contract UnlessRetainerRequestWithdrawalTest is UnlessRetainerExtBase {
    // ---------------------------------------------------------------- success

    function test_requestWithdrawal_byClient_setsFieldsAndEmits() public {
        uint256 id = _create(10e6);
        uint64 expectedReady = uint64(block.timestamp) + NOTICE;

        _expectRequested(id, 4e6, expectedReady);
        vm.prank(client);
        retainer.requestWithdrawal(id, 4e6);

        _assertWithdrawal(id, 4e6, expectedReady);
        assertEq(uint256(expectedReady), block.timestamp + NOTICE, "readyAt == now + NOTICE");
    }

    function test_requestWithdrawal_atLaterTime_readyAtIsNowPlusNotice() public {
        uint256 id = _create(10e6);
        vm.warp(12_345);

        _expectRequested(id, 1, 12_345 + NOTICE);
        _request(id, 1);

        _assertWithdrawal(id, 1, 12_345 + NOTICE);
    }

    function test_requestWithdrawal_reservesNothing_availableAndBalancesUnchanged() public {
        (uint256 id,) = _setupClaim(10e6, 3e6);
        uint256 availBefore = _avail(id);
        assertEq(availBefore, 7e6);

        _expectRequested(id, 7e6, uint64(block.timestamp) + NOTICE);
        _request(id, 7e6);

        assertEq(_avail(id), availBefore, "available unchanged");
        _assertAcct(id, 10e6, 3e6, 10e6, 0, 0, 1);
        assertEq(usdc.balanceOf(address(retainer)), 10e6, "no tokens moved");
        assertEq(usdc.balanceOf(client), START_BALANCE - 10e6, "client tokens unchanged");
    }

    function test_requestWithdrawal_equalToAvailable_succeeds() public {
        (uint256 id,) = _setupClaim(10e6, 3e6);

        _expectRequested(id, 7e6, uint64(block.timestamp) + NOTICE);
        _request(id, 7e6);

        _assertWithdrawal(id, 7e6, uint64(block.timestamp) + NOTICE);
    }

    function test_requestWithdrawal_afterCancel_newRequestSucceeds() public {
        uint256 id = _create(10e6);
        _request(id, 4e6);
        _cancelWd(id);
        _assertNoWithdrawal(id);

        vm.warp(block.timestamp + 10);
        _expectRequested(id, 6e6, uint64(block.timestamp) + NOTICE);
        _request(id, 6e6);

        _assertWithdrawal(id, 6e6, uint64(block.timestamp) + NOTICE);
    }

    function test_requestWithdrawal_afterCompletion_newRequestSucceeds() public {
        uint256 id = _create(10e6);
        _request(id, 4e6);
        vm.warp(_readyAt(id));
        _complete(id);
        _assertNoWithdrawal(id);

        _expectRequested(id, 6e6, uint64(block.timestamp) + NOTICE);
        _request(id, 6e6);

        _assertWithdrawal(id, 6e6, uint64(block.timestamp) + NOTICE);
        _assertAcct(id, 6e6, 0, 10e6, 0, 4e6, 0);
    }

    function test_requestWithdrawal_requestAgainAfterFirstCompleted_canDrainRemainder() public {
        uint256 id = _create(10e6);
        _request(id, 4e6);
        vm.warp(_readyAt(id));
        _complete(id);
        _request(id, 6e6);
        vm.warp(_readyAt(id));

        _expectWdCompleted(id, 6e6, 6e6);
        _complete(id);

        _assertAcct(id, 0, 0, 10e6, 0, 10e6, 0);
        assertEq(usdc.balanceOf(client), START_BALANCE);
    }

    // ---------------------------------------------------------------- deferred from P3a: fileClaim while pending

    function test_fileClaim_whileWithdrawalPending_succeedsAndReservesFromSameMoney() public {
        uint256 id = _create(10e6);
        _request(id, 7e6);
        uint64 readyAt = _readyAt(id);

        vm.warp(block.timestamp + 1);
        _expectFiled(id, 0, 10e6, uint64(block.timestamp) + WINDOW, "all of it");
        vm.prank(freelancer);
        retainer.fileClaim(id, 10e6, "all of it");

        // The claim reserved money the request had "claimed": request is untouched, available is 0.
        _assertAcct(id, 10e6, 10e6, 10e6, 0, 0, 1);
        _assertWithdrawal(id, 7e6, readyAt);
        assertEq(_avail(id), 0);
    }

    // ---------------------------------------------------------------- reverts

    function test_requestWithdrawal_oneAboveAvailable_revertsInsufficientAvailable() public {
        (uint256 id,) = _setupClaim(10e6, 3e6);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.InsufficientAvailable.selector);
        retainer.requestWithdrawal(id, 7e6 + 1);
        _assertNoWithdrawal(id);
    }

    function test_requestWithdrawal_everythingReserved_revertsInsufficientAvailable() public {
        (uint256 id,) = _setupClaim(10e6, 10e6);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.InsufficientAvailable.selector);
        retainer.requestWithdrawal(id, 1);
    }

    function test_requestWithdrawal_unfundedRetainer_revertsInsufficientAvailable() public {
        uint256 id = _create(0);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.InsufficientAvailable.selector);
        retainer.requestWithdrawal(id, 1);
    }

    function test_requestWithdrawal_zeroAmount_revertsZeroAmount() public {
        uint256 id = _create(10e6);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.ZeroAmount.selector);
        retainer.requestWithdrawal(id, 0);
    }

    function test_requestWithdrawal_zeroAmountOnUnfundedRetainer_revertsZeroAmount() public {
        uint256 id = _create(0);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.ZeroAmount.selector);
        retainer.requestWithdrawal(id, 0);
    }

    function test_requestWithdrawal_whilePending_revertsWithdrawalAlreadyPending() public {
        uint256 id = _create(10e6);
        _request(id, 4e6);
        uint64 readyAt = _readyAt(id);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.WithdrawalAlreadyPending.selector);
        retainer.requestWithdrawal(id, 1e6);
        _assertWithdrawal(id, 4e6, readyAt);
    }

    function test_requestWithdrawal_whilePendingWithZeroAmount_revertsWithdrawalAlreadyPending() public {
        uint256 id = _create(10e6);
        _request(id, 4e6);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.WithdrawalAlreadyPending.selector);
        retainer.requestWithdrawal(id, 0);
    }

    function test_requestWithdrawal_whilePendingWithTooLargeAmount_revertsWithdrawalAlreadyPending() public {
        uint256 id = _create(10e6);
        _request(id, 4e6);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.WithdrawalAlreadyPending.selector);
        retainer.requestWithdrawal(id, 11e6);
    }

    function test_requestWithdrawal_oneSecondBeforeEnd_succeeds() public {
        uint256 id = _create(10e6);
        vm.warp(uint256(END) - 1);

        _expectRequested(id, 10e6, END - 1 + NOTICE);
        _request(id, 10e6);

        _assertWithdrawal(id, 10e6, END - 1 + NOTICE);
    }

    function test_requestWithdrawal_atEndTime_revertsRetainerEnded() public {
        uint256 id = _create(10e6);
        vm.warp(END);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.RetainerEnded.selector);
        retainer.requestWithdrawal(id, 1e6);
    }

    function test_requestWithdrawal_afterEndTime_revertsRetainerEnded() public {
        uint256 id = _create(10e6);
        vm.warp(uint256(END) + 1);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.RetainerEnded.selector);
        retainer.requestWithdrawal(id, 1e6);
    }

    function test_requestWithdrawal_endedAndWithdrawalPending_revertsRetainerEnded() public {
        uint256 id = _create(10e6);
        _request(id, 4e6);
        vm.warp(END);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.RetainerEnded.selector);
        retainer.requestWithdrawal(id, 1e6);
    }

    function test_requestWithdrawal_endedAndZeroAmount_revertsRetainerEnded() public {
        uint256 id = _create(10e6);
        vm.warp(END);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.RetainerEnded.selector);
        retainer.requestWithdrawal(id, 0);
    }

    function test_requestWithdrawal_endedAndTooLarge_revertsRetainerEnded() public {
        uint256 id = _create(10e6);
        vm.warp(END);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.RetainerEnded.selector);
        retainer.requestWithdrawal(id, 11e6);
    }

    function test_requestWithdrawal_byFreelancer_revertsNotClient() public {
        uint256 id = _create(10e6);

        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.requestWithdrawal(id, 1e6);
    }

    function test_requestWithdrawal_byStranger_revertsNotClient() public {
        uint256 id = _create(10e6);

        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.requestWithdrawal(id, 1e6);
    }

    function test_requestWithdrawal_byOtherClient_revertsNotClient() public {
        uint256 id = _create(10e6);

        vm.prank(client2);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.requestWithdrawal(id, 1e6);
    }

    function test_requestWithdrawal_strangerOnEndedRetainer_revertsNotClient() public {
        uint256 id = _create(10e6);
        vm.warp(END + 1);

        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.requestWithdrawal(id, 1e6);
    }

    function test_requestWithdrawal_strangerWithZeroAmount_revertsNotClient() public {
        uint256 id = _create(10e6);

        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.requestWithdrawal(id, 0);
    }

    function test_requestWithdrawal_strangerWhilePending_revertsNotClient() public {
        uint256 id = _create(10e6);
        _request(id, 4e6);

        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.requestWithdrawal(id, 1e6);
    }

    function test_requestWithdrawal_unknownId_revertsRetainerNotFound() public {
        _create(10e6);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.RetainerNotFound.selector);
        retainer.requestWithdrawal(1, 1e6);
    }

    function test_requestWithdrawal_unknownIdByStranger_revertsRetainerNotFound() public {
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.RetainerNotFound.selector);
        retainer.requestWithdrawal(0, 0);
    }

    function test_requestWithdrawal_maxId_revertsRetainerNotFound() public {
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.RetainerNotFound.selector);
        retainer.requestWithdrawal(type(uint256).max, 1);
    }
}
