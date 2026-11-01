// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UnlessRetainer} from "../UnlessRetainer.sol";
import {UnlessRetainerExtBase} from "./UnlessRetainer.ExtBase.t.sol";

/// @notice 4.11 extendEndTime.
contract UnlessRetainerExtendTest is UnlessRetainerExtBase {
    function _extend(uint256 id, uint64 newEnd) internal {
        vm.prank(client);
        retainer.extendEndTime(id, newEnd);
    }

    // ---------------------------------------------------------------- success

    function test_extendEndTime_toLaterTime_updatesEndAndEmits() public {
        uint256 id = _create(10e6);

        _expectExtended(id, END, END + 1 days);
        _extend(id, END + 1 days);

        assertEq(uint256(_ret(id).endTime), uint256(END) + 1 days);
    }

    function test_extendEndTime_byOneSecond_succeeds() public {
        uint256 id = _create(10e6);

        _expectExtended(id, END, END + 1);
        _extend(id, END + 1);

        assertEq(uint256(_ret(id).endTime), uint256(END) + 1);
    }

    function test_extendEndTime_toMaxUint64_succeedsThenFurtherExtensionReverts() public {
        uint256 id = _create(10e6);

        _expectExtended(id, END, type(uint64).max);
        _extend(id, type(uint64).max);
        assertEq(uint256(_ret(id).endTime), uint256(type(uint64).max));

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.EndTimeNotLater.selector);
        retainer.extendEndTime(id, type(uint64).max);
    }

    function test_extendEndTime_changesNothingElse() public {
        uint256 id = _create(10e6);
        uint256 claimId = _file(id, 3e6, "c");
        _request(id, 4e6);
        UnlessRetainer.Retainer memory b = _ret(id);
        UnlessRetainer.Claim memory cb = _claimV(id, claimId);
        uint256 availBefore = _avail(id);

        _extend(id, END + 3 days);

        UnlessRetainer.Retainer memory a = _ret(id);
        assertEq(uint256(a.endTime), uint256(END) + 3 days, "endTime");
        assertEq(a.client, b.client, "client");
        assertEq(a.freelancer, b.freelancer, "freelancer");
        assertEq(uint256(a.objectionWindow), uint256(b.objectionWindow), "objectionWindow");
        assertEq(uint256(a.noticePeriod), uint256(b.noticePeriod), "noticePeriod");
        assertEq(uint256(a.balance), uint256(b.balance), "balance");
        assertEq(uint256(a.reserved), uint256(b.reserved), "reserved");
        assertEq(uint256(a.withdrawalAmount), uint256(b.withdrawalAmount), "withdrawalAmount");
        assertEq(uint256(a.withdrawalReadyAt), uint256(b.withdrawalReadyAt), "withdrawalReadyAt");
        assertEq(uint256(a.claimCount), uint256(b.claimCount), "claimCount");
        assertEq(uint256(a.pendingClaims), uint256(b.pendingClaims), "pendingClaims");
        assertEq(uint256(a.totalDeposited), uint256(b.totalDeposited), "totalDeposited");
        assertEq(uint256(a.totalPaid), uint256(b.totalPaid), "totalPaid");
        assertEq(uint256(a.totalReturned), uint256(b.totalReturned), "totalReturned");
        assertEq(uint256(a.createdAt), uint256(b.createdAt), "createdAt");
        assertEq(_avail(id), availBefore, "available");
        assertEq(keccak256(abi.encode(_claimV(id, claimId))), keccak256(abi.encode(cb)), "claim");
        assertEq(usdc.balanceOf(address(retainer)), 10e6, "no tokens moved");
    }

    function test_extendEndTime_multipleExtensions_endTimeOnlyIncreases() public {
        uint256 id = _create(10e6);
        uint64 prev = END;
        uint64[3] memory ends = [END + 10, END + 1 days, END + 30 days];

        for (uint256 i = 0; i < ends.length; i++) {
            _expectExtended(id, prev, ends[i]);
            _extend(id, ends[i]);
            assertEq(uint256(_ret(id).endTime), uint256(ends[i]));
            assertGt(uint256(ends[i]), uint256(prev));

            // Going back (to the previous value) is rejected and leaves the end untouched.
            vm.prank(client);
            vm.expectRevert(UnlessRetainer.EndTimeNotLater.selector);
            retainer.extendEndTime(id, prev);
            assertEq(uint256(_ret(id).endTime), uint256(ends[i]));
            prev = ends[i];
        }
    }

    // ---------------------------------------------------------------- reopening after end

    function test_extendEndTime_afterEnd_toFutureTime_reEnablesFileClaim() public {
        uint256 id = _create(10e6);
        vm.warp(uint256(END) + 100);
        assertTrue(_isEnded(id));
        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.RetainerEnded.selector);
        retainer.fileClaim(id, 1e6, "late");

        uint64 newEnd = uint64(block.timestamp) + 1 days;
        _expectExtended(id, END, newEnd);
        _extend(id, newEnd);

        assertFalse(_isEnded(id));
        _expectFiled(id, 0, 1e6, uint64(block.timestamp) + WINDOW, "reopened");
        vm.prank(freelancer);
        retainer.fileClaim(id, 1e6, "reopened");
        _assertAcct(id, 10e6, 1e6, 10e6, 0, 0, 1);
    }

    function test_extendEndTime_afterEnd_toFutureTime_reEnablesDeposit() public {
        uint256 id = _create(10e6);
        vm.warp(uint256(END) + 100);
        _approve(client, 2e6);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.RetainerEnded.selector);
        retainer.deposit(id, 2e6);

        _extend(id, uint64(block.timestamp) + 1 days);

        _expectDeposited(id, client, 2e6, 12e6);
        vm.prank(client);
        retainer.deposit(id, 2e6);
        _assertAcct(id, 12e6, 0, 12e6, 0, 0, 0);
    }

    function test_extendEndTime_afterEnd_reEnablesRequestWithdrawal() public {
        uint256 id = _create(10e6);
        vm.warp(uint256(END) + 100);
        _extend(id, uint64(block.timestamp) + 1 days);

        _expectRequested(id, 5e6, uint64(block.timestamp) + NOTICE);
        _request(id, 5e6);

        _assertWithdrawal(id, 5e6, uint64(block.timestamp) + NOTICE);
    }

    function test_extendEndTime_afterEnd_toStillPastTime_keepsRetainerEnded() public {
        uint256 id = _create(10e6);
        vm.warp(uint256(END) + 1000);
        uint64 stillPast = END + 500;

        _expectExtended(id, END, stillPast);
        _extend(id, stillPast);

        assertEq(uint256(_ret(id).endTime), uint256(stillPast));
        assertTrue(_isEnded(id), "still ended");
        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.RetainerEnded.selector);
        retainer.fileClaim(id, 1e6, "x");
        _approve(client, 1e6);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.RetainerEnded.selector);
        retainer.deposit(id, 1e6);
    }

    function test_extendEndTime_afterEnd_toExactlyNow_keepsRetainerEnded() public {
        uint256 id = _create(10e6);
        vm.warp(uint256(END) + 1000);

        _extend(id, uint64(block.timestamp));

        assertTrue(_isEnded(id), "t >= endTime is ended");
        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.RetainerEnded.selector);
        retainer.fileClaim(id, 1e6, "x");
    }

    function test_extendEndTime_afterEnd_toNowPlusOne_reopens() public {
        uint256 id = _create(10e6);
        vm.warp(uint256(END) + 1000);

        _extend(id, uint64(block.timestamp) + 1);

        assertFalse(_isEnded(id));
        vm.prank(freelancer);
        retainer.fileClaim(id, 1e6, "x");
    }

    // ---------------------------------------------------------------- reverts

    function test_extendEndTime_equalToCurrent_revertsEndTimeNotLater() public {
        uint256 id = _create(10e6);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.EndTimeNotLater.selector);
        retainer.extendEndTime(id, END);
    }

    function test_extendEndTime_oneSecondEarlier_revertsEndTimeNotLater() public {
        uint256 id = _create(10e6);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.EndTimeNotLater.selector);
        retainer.extendEndTime(id, END - 1);
        assertEq(uint256(_ret(id).endTime), uint256(END));
    }

    function test_extendEndTime_toZero_revertsEndTimeNotLater() public {
        uint256 id = _create(10e6);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.EndTimeNotLater.selector);
        retainer.extendEndTime(id, 0);
    }

    function test_extendEndTime_byFreelancer_revertsNotClient() public {
        uint256 id = _create(10e6);

        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.extendEndTime(id, END + 1 days);
    }

    function test_extendEndTime_byStranger_revertsNotClient() public {
        uint256 id = _create(10e6);

        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.extendEndTime(id, END + 1 days);
    }

    function test_extendEndTime_byStrangerWithInvalidEnd_revertsNotClientBeforeEndTimeNotLater() public {
        uint256 id = _create(10e6);

        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.extendEndTime(id, END);
    }

    function test_extendEndTime_byOtherClient_revertsNotClient() public {
        uint256 id = _create(10e6);

        vm.prank(client2);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.extendEndTime(id, END + 1 days);
    }

    function test_extendEndTime_unknownId_revertsRetainerNotFound() public {
        _create(10e6);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.RetainerNotFound.selector);
        retainer.extendEndTime(1, END + 1 days);
    }

    function test_extendEndTime_unknownIdByStranger_revertsRetainerNotFound() public {
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.RetainerNotFound.selector);
        retainer.extendEndTime(type(uint256).max, END);
    }
}
