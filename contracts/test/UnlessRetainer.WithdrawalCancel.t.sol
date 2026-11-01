// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UnlessRetainer} from "../UnlessRetainer.sol";
import {UnlessRetainerExtBase} from "./UnlessRetainer.ExtBase.t.sol";

/// @notice 4.9 withdrawal lifecycle: cancelWithdrawal.
contract UnlessRetainerCancelWithdrawalTest is UnlessRetainerExtBase {
    function test_cancelWithdrawal_byClient_clearsBothFieldsAndEmits() public {
        (uint256 id,) = _setupClaim(10e6, 3e6);
        _request(id, 7e6);
        _assertWithdrawal(id, 7e6, uint64(block.timestamp) + NOTICE);

        _expectWdCancelled(id);
        vm.prank(client);
        retainer.cancelWithdrawal(id);

        _assertNoWithdrawal(id);
        _assertAcct(id, 10e6, 3e6, 10e6, 0, 0, 1);
        assertEq(usdc.balanceOf(address(retainer)), 10e6, "no tokens moved");
        assertEq(usdc.balanceOf(client), START_BALANCE - 10e6, "client tokens unchanged");
    }

    function test_cancelWithdrawal_afterNoticeElapsedButBeforeCompletion_succeeds() public {
        uint256 id = _create(10e6);
        _request(id, 7e6);
        vm.warp(_readyAt(id) + 1);

        _expectWdCancelled(id);
        _cancelWd(id);

        _assertNoWithdrawal(id);
    }

    function test_cancelWithdrawal_afterEndTime_succeeds() public {
        uint256 id = _create(10e6);
        _request(id, 7e6);
        vm.warp(uint256(END) + 1);

        _expectWdCancelled(id);
        _cancelWd(id);

        _assertNoWithdrawal(id);
    }

    function test_cancelWithdrawal_thenComplete_revertsNoWithdrawalPending() public {
        uint256 id = _create(10e6);
        _request(id, 7e6);
        uint64 readyAt = _readyAt(id);
        _cancelWd(id);
        vm.warp(readyAt);

        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NoWithdrawalPending.selector);
        retainer.completeWithdrawal(id);
    }

    function test_cancelWithdrawal_thenNewRequest_succeeds() public {
        uint256 id = _create(10e6);
        _request(id, 7e6);
        _cancelWd(id);

        _expectRequested(id, 2e6, uint64(block.timestamp) + NOTICE);
        _request(id, 2e6);

        _assertWithdrawal(id, 2e6, uint64(block.timestamp) + NOTICE);
    }

    function test_cancelWithdrawal_nonePending_revertsNoWithdrawalPending() public {
        uint256 id = _create(10e6);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.NoWithdrawalPending.selector);
        retainer.cancelWithdrawal(id);
    }

    function test_cancelWithdrawal_calledTwice_secondRevertsNoWithdrawalPending() public {
        uint256 id = _create(10e6);
        _request(id, 7e6);
        _cancelWd(id);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.NoWithdrawalPending.selector);
        retainer.cancelWithdrawal(id);
    }

    function test_cancelWithdrawal_afterCompletion_revertsNoWithdrawalPending() public {
        uint256 id = _create(10e6);
        _request(id, 7e6);
        vm.warp(_readyAt(id));
        _complete(id);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.NoWithdrawalPending.selector);
        retainer.cancelWithdrawal(id);
    }

    function test_cancelWithdrawal_byFreelancer_revertsNotClient() public {
        uint256 id = _create(10e6);
        _request(id, 7e6);

        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.cancelWithdrawal(id);
        _assertWithdrawal(id, 7e6, uint64(block.timestamp) + NOTICE);
    }

    function test_cancelWithdrawal_byStranger_revertsNotClient() public {
        uint256 id = _create(10e6);
        _request(id, 7e6);

        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.cancelWithdrawal(id);
    }

    function test_cancelWithdrawal_byOtherClient_revertsNotClient() public {
        uint256 id = _create(10e6);
        _request(id, 7e6);

        vm.prank(client2);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.cancelWithdrawal(id);
    }

    function test_cancelWithdrawal_strangerWhenNonePending_revertsNotClient() public {
        uint256 id = _create(10e6);

        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.cancelWithdrawal(id);
    }

    function test_cancelWithdrawal_unknownId_revertsRetainerNotFound() public {
        _create(10e6);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.RetainerNotFound.selector);
        retainer.cancelWithdrawal(1);
    }

    function test_cancelWithdrawal_unknownIdByStranger_revertsRetainerNotFound() public {
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.RetainerNotFound.selector);
        retainer.cancelWithdrawal(type(uint256).max);
    }
}
