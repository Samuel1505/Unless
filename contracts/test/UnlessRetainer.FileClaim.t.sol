// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UnlessRetainer} from "../UnlessRetainer.sol";
import {UnlessRetainerBase} from "./UnlessRetainer.Base.t.sol";

/// @notice Unit tests: fileClaim (4.4).
contract UnlessRetainerFileClaimTest is UnlessRetainerBase {
    // ---------------------------------------------------------------- success

    function test_fileClaim_happyPath_storesClaimReservesAndEmits() public {
        uint256 id = _create(10e6);
        uint64 t0 = uint64(block.timestamp);
        string memory note = "invoice #1: landing page";

        _expectFiled(id, 0, 3e6, t0 + WINDOW, note);
        vm.prank(freelancer);
        uint256 claimId = retainer.fileClaim(id, 3e6, note);

        assertEq(claimId, 0, "returned claimId");
        UnlessRetainer.Claim memory c = retainer.claimOf(id, 0);
        assertEq(uint256(c.amount), 3e6);
        assertEq(uint256(c.filedAt), uint256(t0));
        assertEq(uint256(c.payableAt), uint256(t0) + uint256(WINDOW), "payableAt == now + WINDOW");
        assertEq(uint256(c.status), uint256(UnlessRetainer.ClaimStatus.Pending));
        assertEq(uint256(c.paidVia), uint256(UnlessRetainer.PaidVia.None));
        assertEq(c.noteHash, keccak256(bytes(note)));

        _assertState(id, 10e6, 3e6, 10e6, 0, 0, 1);
        assertEq(uint256(retainer.retainerOf(id).claimCount), 1);
        assertEq(retainer.availableOf(id), 7e6);
        // No tokens move on filing.
        assertEq(usdc.balanceOf(address(retainer)), 10e6);
        assertEq(usdc.balanceOf(freelancer), START_BALANCE);
    }

    function test_fileClaim_secondClaim_getsNextIdAndOwnPayableAt() public {
        uint256 id = _create(10e6);
        _file(id, 1e6, "a");
        vm.warp(block.timestamp + 40);
        uint64 t1 = uint64(block.timestamp);

        _expectFiled(id, 1, 2e6, t1 + WINDOW, "b");
        vm.prank(freelancer);
        uint256 claimId = retainer.fileClaim(id, 2e6, "b");

        assertEq(claimId, 1);
        assertEq(uint256(retainer.claimOf(id, 1).payableAt), uint256(t1) + uint256(WINDOW));
        assertEq(uint256(retainer.claimOf(id, 1).filedAt), uint256(t1));
        _assertState(id, 10e6, 3e6, 10e6, 0, 0, 2);
        assertEq(uint256(retainer.retainerOf(id).claimCount), 2);
    }

    function test_fileClaim_emptyNote_succeedsWithEmptyNoteHash() public {
        uint256 id = _create(1e6);
        uint64 t0 = uint64(block.timestamp);
        _expectFiled(id, 0, 1e6, t0 + WINDOW, "");
        vm.prank(freelancer);
        retainer.fileClaim(id, 1e6, "");
        assertEq(retainer.claimOf(id, 0).noteHash, keccak256(""));
    }

    function test_fileClaim_amountEqualsAvailable_succeeds() public {
        uint256 id = _create(10e6);
        uint64 t0 = uint64(block.timestamp);
        _expectFiled(id, 0, 10e6, t0 + WINDOW, "all");
        vm.prank(freelancer);
        retainer.fileClaim(id, 10e6, "all");
        _assertState(id, 10e6, 10e6, 10e6, 0, 0, 1);
        assertEq(retainer.availableOf(id), 0);
    }

    function test_fileClaim_amountAboveAvailableByOne_revertsInsufficientAvailable() public {
        uint256 id = _create(10e6);
        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.InsufficientAvailable.selector);
        retainer.fileClaim(id, 10e6 + 1, "too much");
        _assertState(id, 10e6, 0, 10e6, 0, 0, 0);
    }

    function test_fileClaim_unfundedRetainer_revertsInsufficientAvailable() public {
        uint256 id = _create(0);
        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.InsufficientAvailable.selector);
        retainer.fileClaim(id, 1, "x");
    }

    function test_fileClaim_secondClaimCannotUseReservedMoney_revertsInsufficientAvailable() public {
        uint256 id = _create(10e6);
        _file(id, 6e6, "first");
        assertEq(retainer.availableOf(id), 4e6, "available shrank");

        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.InsufficientAvailable.selector);
        retainer.fileClaim(id, 4e6 + 1, "second");

        uint64 t0 = uint64(block.timestamp);
        _expectFiled(id, 1, 4e6, t0 + WINDOW, "second");
        vm.prank(freelancer);
        retainer.fileClaim(id, 4e6, "second");
        _assertState(id, 10e6, 10e6, 10e6, 0, 0, 2);
        assertEq(retainer.availableOf(id), 0);
    }

    // ---------------------------------------------------------------- note length

    function test_fileClaim_note280Bytes_succeeds() public {
        uint256 id = _create(1e6);
        string memory note = _str(MAX_TEXT);
        uint64 t0 = uint64(block.timestamp);
        _expectFiled(id, 0, 1e6, t0 + WINDOW, note);
        vm.prank(freelancer);
        retainer.fileClaim(id, 1e6, note);
        assertEq(retainer.claimOf(id, 0).noteHash, keccak256(bytes(note)));
    }

    function test_fileClaim_note281Bytes_revertsTextTooLong() public {
        uint256 id = _create(1e6);
        string memory note = _str(MAX_TEXT + 1);
        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.TextTooLong.selector);
        retainer.fileClaim(id, 1e6, note);
    }

    // ---------------------------------------------------------------- pending cap

    function _fileMany(uint256 id, uint256 n) internal {
        for (uint256 i = 0; i < n; i++) {
            _file(id, 1e6, "n");
        }
    }

    function test_fileClaim_twentyPending_succeedsAnd21stRevertsTooManyPendingClaims() public {
        uint256 id = _create(21e6);
        _fileMany(id, MAX_PENDING);
        _assertState(id, 21e6, 20e6, 21e6, 0, 0, 20);
        assertEq(uint256(retainer.retainerOf(id).claimCount), 20);

        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.TooManyPendingClaims.selector);
        retainer.fileClaim(id, 1e6, "21st");
        _assertState(id, 21e6, 20e6, 21e6, 0, 0, 20);
    }

    function test_fileClaim_afterCancellingOneOfTwentyPending_succeedsAgain() public {
        uint256 id = _create(21e6);
        _fileMany(id, MAX_PENDING);
        _cancel(id, 7);

        uint64 t0 = uint64(block.timestamp);
        _expectFiled(id, 20, 1e6, t0 + WINDOW, "again");
        vm.prank(freelancer);
        uint256 claimId = retainer.fileClaim(id, 1e6, "again");
        assertEq(claimId, 20, "claimId keeps counting past cancelled ones");
        _assertState(id, 21e6, 20e6, 21e6, 0, 0, 20);

        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.TooManyPendingClaims.selector);
        retainer.fileClaim(id, 1e6, "over");
    }

    function test_fileClaim_afterPayingOutOneOfTwentyPending_succeedsAgain() public {
        uint256 id = _create(21e6);
        _fileMany(id, MAX_PENDING);
        vm.warp(_payableAt(id, 0));
        _payOut(id, 0);
        // All 20 share the same payableAt, so the remaining 19 are payable too, but still pending.
        assertEq(uint256(retainer.retainerOf(id).pendingClaims), 19);
        _file(id, 1e6, "again");
        assertEq(uint256(retainer.retainerOf(id).pendingClaims), 20);
    }

    function test_fileClaim_twentyPendingAndNoMoneyLeft_revertsTooManyPendingClaims() public {
        uint256 id = _create(20e6);
        _fileMany(id, MAX_PENDING);
        assertEq(retainer.availableOf(id), 0);
        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.TooManyPendingClaims.selector);
        retainer.fileClaim(id, 1, "x");
    }

    // ---------------------------------------------------------------- endTime boundary

    function test_fileClaim_oneSecondBeforeEnd_succeeds() public {
        uint256 id = _create(1e6);
        vm.warp(uint256(END) - 1);
        uint64 t = uint64(block.timestamp);
        _expectFiled(id, 0, 1e6, t + WINDOW, "last second");
        vm.prank(freelancer);
        retainer.fileClaim(id, 1e6, "last second");
        _assertState(id, 1e6, 1e6, 1e6, 0, 0, 1);
    }

    function test_fileClaim_atEndTime_revertsRetainerEnded() public {
        uint256 id = _create(1e6);
        vm.warp(END);
        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.RetainerEnded.selector);
        retainer.fileClaim(id, 1e6, "late");
    }

    function test_fileClaim_afterEndTime_revertsRetainerEnded() public {
        uint256 id = _create(1e6);
        vm.warp(uint256(END) + 1);
        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.RetainerEnded.selector);
        retainer.fileClaim(id, 1e6, "late");
    }

    // ---------------------------------------------------------------- reverts

    function test_fileClaim_byClient_revertsNotFreelancer() public {
        uint256 id = _create(1e6);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.NotFreelancer.selector);
        retainer.fileClaim(id, 1e6, "x");
    }

    function test_fileClaim_byStranger_revertsNotFreelancer() public {
        uint256 id = _create(1e6);
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NotFreelancer.selector);
        retainer.fileClaim(id, 1e6, "x");
    }

    function test_fileClaim_unknownId_revertsRetainerNotFound() public {
        _create(1e6);
        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.RetainerNotFound.selector);
        retainer.fileClaim(1, 1e6, "x");
    }

    function test_fileClaim_zeroAmount_revertsZeroAmount() public {
        uint256 id = _create(1e6);
        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.ZeroAmount.selector);
        retainer.fileClaim(id, 0, "x");
    }

    function test_fileClaim_freelancerOfOtherRetainer_revertsNotFreelancer() public {
        _create(1e6);
        uint256 b = _createFor(client2, freelancer2, 1e6);
        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.NotFreelancer.selector);
        retainer.fileClaim(b, 1e6, "x");
    }

    // ---------------------------------------------------------------- check order

    function test_fileClaim_unknownIdByStranger_revertsRetainerNotFound() public {
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.RetainerNotFound.selector);
        retainer.fileClaim(0, 0, _str(MAX_TEXT + 1));
    }

    function test_fileClaim_strangerOnEndedRetainer_revertsNotFreelancer() public {
        uint256 id = _create(1e6);
        vm.warp(END);
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NotFreelancer.selector);
        retainer.fileClaim(id, 1e6, "x");
    }

    function test_fileClaim_endedAndZeroAmount_revertsRetainerEnded() public {
        uint256 id = _create(1e6);
        vm.warp(END);
        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.RetainerEnded.selector);
        retainer.fileClaim(id, 0, "x");
    }

    function test_fileClaim_zeroAmountAnd281ByteNote_revertsZeroAmount() public {
        uint256 id = _create(1e6);
        string memory note = _str(MAX_TEXT + 1);
        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.ZeroAmount.selector);
        retainer.fileClaim(id, 0, note);
    }

    function test_fileClaim_281ByteNoteWith20Pending_revertsTextTooLong() public {
        uint256 id = _create(21e6);
        _fileMany(id, MAX_PENDING);
        string memory note = _str(MAX_TEXT + 1);
        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.TextTooLong.selector);
        retainer.fileClaim(id, 1e6, note);
    }

    function test_fileClaim_20PendingAndAmountAboveAvailable_revertsTooManyPendingClaims() public {
        uint256 id = _create(21e6);
        _fileMany(id, MAX_PENDING);
        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.TooManyPendingClaims.selector);
        retainer.fileClaim(id, 100e6, "x");
    }

    function test_fileClaim_281ByteNoteAndAmountAboveAvailable_revertsTextTooLong() public {
        uint256 id = _create(1e6);
        string memory note = _str(MAX_TEXT + 1);
        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.TextTooLong.selector);
        retainer.fileClaim(id, 100e6, note);
    }
}
