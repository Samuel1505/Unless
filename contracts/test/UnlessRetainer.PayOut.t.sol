// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";

import {UnlessRetainer} from "../UnlessRetainer.sol";
import {UnlessRetainerBase} from "./UnlessRetainer.Base.t.sol";

/// @notice Unit tests: payOutClaim (4.8).
contract UnlessRetainerPayOutTest is UnlessRetainerBase {
    UnlessRetainer.ClaimStatus internal constant PAID = UnlessRetainer.ClaimStatus.Paid;
    UnlessRetainer.PaidVia internal constant PAID_OUT = UnlessRetainer.PaidVia.PaidOut;

    // ---------------------------------------------------------------- window boundary

    function test_payOutClaim_oneSecondBeforePayableAt_revertsObjectionWindowOpen() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        vm.warp(uint256(_payableAt(id, claimId)) - 1);
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.ObjectionWindowOpen.selector);
        retainer.payOutClaim(id, claimId);
        _assertState(id, 10e6, 3e6, 10e6, 0, 0, 1);
    }

    function test_payOutClaim_atPayableAt_succeeds() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        vm.warp(_payableAt(id, claimId));
        _expectPaid(id, claimId, freelancer, 3e6, PAID_OUT);
        vm.prank(stranger);
        retainer.payOutClaim(id, claimId);
        _assertState(id, 7e6, 0, 10e6, 3e6, 0, 0);
        _assertClaim(id, claimId, 3e6, PAID, PAID_OUT);
    }

    function test_payOutClaim_oneSecondAfterPayableAt_succeeds() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        vm.warp(uint256(_payableAt(id, claimId)) + 1);
        _expectPaid(id, claimId, freelancer, 3e6, PAID_OUT);
        vm.prank(stranger);
        retainer.payOutClaim(id, claimId);
        _assertState(id, 7e6, 0, 10e6, 3e6, 0, 0);
        _assertClaim(id, claimId, 3e6, PAID, PAID_OUT);
    }

    function test_payOutClaim_longAfterPayableAndAfterRetainerEnd_succeeds() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        vm.warp(uint256(END) + 365 days);
        _expectPaid(id, claimId, freelancer, 3e6, PAID_OUT);
        vm.prank(stranger);
        retainer.payOutClaim(id, claimId);
        assertEq(usdc.balanceOf(freelancer), START_BALANCE + 3e6);
    }

    // ---------------------------------------------------------------- who pays out

    function test_payOutClaim_byStranger_paysFreelancerAndStrangerReceivesNothing() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        vm.warp(_payableAt(id, claimId));

        _expectPaid(id, claimId, freelancer, 3e6, PAID_OUT);
        vm.prank(stranger);
        retainer.payOutClaim(id, claimId);

        assertEq(usdc.balanceOf(stranger), START_BALANCE, "stranger unchanged");
        assertEq(usdc.balanceOf(freelancer), START_BALANCE + 3e6, "freelancer paid");
        assertEq(usdc.balanceOf(client), START_BALANCE - 10e6, "client unchanged");
        assertEq(usdc.balanceOf(address(retainer)), 7e6, "retainer paid out");
        assertEq(retainer.owed(freelancer), 0);
        assertEq(retainer.owed(stranger), 0);
        assertEq(retainer.totalOwed(), 0);
    }

    function test_payOutClaim_byClientAfterPayableAt_succeeds() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        vm.warp(_payableAt(id, claimId));
        _expectPaid(id, claimId, freelancer, 3e6, PAID_OUT);
        vm.prank(client);
        retainer.payOutClaim(id, claimId);
        assertEq(usdc.balanceOf(client), START_BALANCE - 10e6, "client receives nothing");
        assertEq(usdc.balanceOf(freelancer), START_BALANCE + 3e6);
    }

    function test_payOutClaim_byFreelancerAfterPayableAt_succeeds() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        vm.warp(_payableAt(id, claimId));
        _expectPaid(id, claimId, freelancer, 3e6, PAID_OUT);
        vm.prank(freelancer);
        retainer.payOutClaim(id, claimId);
        assertEq(usdc.balanceOf(freelancer), START_BALANCE + 3e6);
    }

    function test_payOutClaim_byClientBeforePayableAt_revertsObjectionWindowOpen() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.ObjectionWindowOpen.selector);
        retainer.payOutClaim(id, claimId);
    }

    function test_payOutClaim_byFreelancerBeforePayableAt_revertsObjectionWindowOpen() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.ObjectionWindowOpen.selector);
        retainer.payOutClaim(id, claimId);
    }

    // ---------------------------------------------------------------- effects

    function test_payOutClaim_accounting_updatesAllFieldsAndEmitsNoDeferral() public {
        uint256 id = _create(10e6);
        _file(id, 3e6, "a");
        _file(id, 2e6, "b");
        vm.warp(_payableAt(id, 0));

        vm.recordLogs();
        _expectPaid(id, 0, freelancer, 3e6, PAID_OUT);
        _payOut(id, 0);

        _assertState(id, 7e6, 2e6, 10e6, 3e6, 0, 1);
        _assertClaim(id, 0, 3e6, PAID, PAID_OUT);
        _assertClaim(id, 1, 2e6, UnlessRetainer.ClaimStatus.Pending, UnlessRetainer.PaidVia.None);

        Vm.Log[] memory logs = _retainerLogs(vm.getRecordedLogs());
        assertEq(logs.length, 1, "only ClaimPaid from the retainer");
        assertEq(logs[0].topics[0], UnlessRetainer.ClaimPaid.selector);
    }

    // ---------------------------------------------------------------- reverts

    function test_payOutClaim_doublePayout_revertsClaimNotPending() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        vm.warp(_payableAt(id, claimId));
        _payOut(id, claimId);

        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.ClaimNotPending.selector);
        retainer.payOutClaim(id, claimId);
        _assertState(id, 7e6, 0, 10e6, 3e6, 0, 0);
        assertEq(usdc.balanceOf(freelancer), START_BALANCE + 3e6, "paid exactly once");
    }

    function test_payOutClaim_afterApproveNow_revertsClaimNotPending() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        _approveNow(id, claimId);
        vm.warp(_payableAt(id, claimId));
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.ClaimNotPending.selector);
        retainer.payOutClaim(id, claimId);
    }

    function test_payOutClaim_afterObjection_revertsClaimNotPending() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        _object(id, claimId);
        vm.warp(_payableAt(id, claimId));
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.ClaimNotPending.selector);
        retainer.payOutClaim(id, claimId);
        _assertState(id, 10e6, 0, 10e6, 0, 0, 0);
    }

    function test_payOutClaim_afterCancel_revertsClaimNotPending() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        _cancel(id, claimId);
        vm.warp(_payableAt(id, claimId));
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.ClaimNotPending.selector);
        retainer.payOutClaim(id, claimId);
        _assertState(id, 10e6, 0, 10e6, 0, 0, 0);
    }

    function test_payOutClaim_objectedClaimBeforePayableAt_revertsClaimNotPendingBeforeObjectionWindowOpen() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        _object(id, claimId);
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.ClaimNotPending.selector);
        retainer.payOutClaim(id, claimId);
    }

    function test_payOutClaim_unknownClaimId_revertsClaimNotFound() public {
        (uint256 id,) = _setupClaim(10e6, 3e6);
        vm.warp(uint256(END) - 1);
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.ClaimNotFound.selector);
        retainer.payOutClaim(id, 1);
    }

    function test_payOutClaim_unknownRetainerId_revertsRetainerNotFound() public {
        _setupClaim(10e6, 3e6);
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.RetainerNotFound.selector);
        retainer.payOutClaim(1, 0);
    }

    function test_payOutClaim_claimIdOfOtherRetainer_revertsClaimNotFound() public {
        _setupClaim(10e6, 3e6);
        uint256 b = _createFor(client2, freelancer2, 5e6);
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.ClaimNotFound.selector);
        retainer.payOutClaim(b, 0);
    }
}
