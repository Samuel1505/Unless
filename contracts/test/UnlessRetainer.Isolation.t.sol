// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UnlessRetainer} from "../UnlessRetainer.sol";
import {UnlessRetainerExtBase} from "./UnlessRetainer.ExtBase.t.sol";

/// @notice 4.13 isolation. Retainer A (id 0): client -> freelancer, funded 10, ends at END.
/// Retainer B (id 1): client2 -> freelancer2, funded 10, ends 30 days after END, with two pending
/// claims (2 and 1) and a pending withdrawal of 5. B's full observable state is fingerprinted in setUp.
contract UnlessRetainerIsolationTest is UnlessRetainerExtBase {
    uint256 internal constant A = 0;
    uint256 internal constant B = 1;

    bytes32 internal fpB;
    bytes32 internal fpA;
    uint256 internal client2Tokens;
    uint256 internal freelancer2Tokens;

    function setUp() public override {
        super.setUp();
        _createEnding(client, freelancer, 10e6, END);
        _createEnding(client2, freelancer2, 10e6, END + 30 days);
        vm.startPrank(freelancer2);
        retainer.fileClaim(B, 2e6, "b0");
        retainer.fileClaim(B, 1e6, "b1");
        vm.stopPrank();
        vm.prank(client2);
        retainer.requestWithdrawal(B, 5e6);

        fpB = _fingerprint(B);
        fpA = _fingerprint(A);
        client2Tokens = usdc.balanceOf(client2);
        freelancer2Tokens = usdc.balanceOf(freelancer2);
    }

    function _assertBUntouched() internal view {
        assertEq(_fingerprint(B), fpB, "retainer B changed");
        assertEq(usdc.balanceOf(client2), client2Tokens, "client2 tokens");
        assertEq(usdc.balanceOf(freelancer2), freelancer2Tokens, "freelancer2 tokens");
        assertEq(uint256(_ret(B).balance), 10e6, "B balance");
        assertEq(_avail(B), 7e6, "B available");
        _assertSolvent();
    }

    function _assertAUntouched() internal view {
        assertEq(_fingerprint(A), fpA, "retainer A changed");
        _assertSolvent();
    }

    // ---------------------------------------------------------------- actions on A never touch B

    function test_isolation_depositOnA_leavesBUntouched() public {
        _approve(client, 4e6);
        _expectDeposited(A, client, 4e6, 14e6);
        vm.prank(client);
        retainer.deposit(A, 4e6);

        _assertAcct(A, 14e6, 0, 14e6, 0, 0, 0);
        _assertBUntouched();
    }

    function test_isolation_fileClaimOnA_leavesBUntouched() public {
        _file(A, 10e6, "all of A");

        _assertAcct(A, 10e6, 10e6, 10e6, 0, 0, 1);
        _assertBUntouched();
    }

    function test_isolation_approveClaimOnA_leavesBUntouched() public {
        uint256 claimId = _file(A, 3e6, "a");
        _approveNow(A, claimId);

        _assertAcct(A, 7e6, 0, 10e6, 3e6, 0, 0);
        _assertBUntouched();
    }

    function test_isolation_objectToClaimOnA_leavesBUntouched() public {
        uint256 claimId = _file(A, 3e6, "a");
        _object(A, claimId);

        _assertAcct(A, 10e6, 0, 10e6, 0, 0, 0);
        _assertBUntouched();
    }

    function test_isolation_cancelClaimOnA_leavesBUntouched() public {
        uint256 claimId = _file(A, 3e6, "a");
        _cancel(A, claimId);

        _assertAcct(A, 10e6, 0, 10e6, 0, 0, 0);
        _assertBUntouched();
    }

    function test_isolation_payOutClaimOnA_leavesBUntouched() public {
        uint256 claimId = _file(A, 3e6, "a");
        vm.warp(_payableAtV(A, claimId));
        _payOut(A, claimId);

        _assertAcct(A, 7e6, 0, 10e6, 3e6, 0, 0);
        _assertBUntouched();
    }

    function test_isolation_withdrawalLifecycleOnA_leavesBUntouched() public {
        _request(A, 6e6);
        _assertBUntouched();
        _cancelWd(A);
        _assertBUntouched();
        _request(A, 6e6);
        vm.warp(_readyAt(A));
        _complete(A);

        _assertAcct(A, 4e6, 0, 10e6, 0, 6e6, 0);
        _assertBUntouched();
    }

    function test_isolation_completeWithdrawalOnA_paysOnlyClientOfA() public {
        _request(A, 6e6);
        vm.warp(_readyAt(A));
        uint256 clientBefore = usdc.balanceOf(client);

        _expectWdCompleted(A, 6e6, 6e6);
        _complete(A);

        assertEq(usdc.balanceOf(client), clientBefore + 6e6);
        _assertBUntouched();
    }

    function test_isolation_withdrawalOnA_doesNotAffectBAvailable() public {
        assertEq(_avail(B), 7e6);
        _request(A, 10e6);
        assertEq(_avail(B), 7e6, "B available unchanged by A's request");
        assertEq(_avail(A), 10e6, "request reserves nothing on A either");
        _assertBUntouched();
    }

    function test_isolation_withdrawRemainderOnA_leavesBUntouched() public {
        vm.warp(END);
        vm.prank(client);
        retainer.withdrawRemainder(A);

        _assertAcct(A, 0, 0, 10e6, 0, 10e6, 0);
        assertFalse(_isEnded(B));
        _assertBUntouched();
    }

    function test_isolation_extendEndTimeOnA_leavesBUntouched() public {
        vm.prank(client);
        retainer.extendEndTime(A, END + 1 days);

        assertEq(uint256(_ret(A).endTime), uint256(END) + 1 days);
        _assertBUntouched();
    }

    // ---------------------------------------------------------------- and the other way round

    function test_isolation_actionsOnB_leaveAUntouched() public {
        // Claim 0 of B: approve; claim 1 of B: object; then complete B's withdrawal; then extend.
        vm.startPrank(client2);
        retainer.approveClaim(B, 0);
        retainer.objectToClaim(B, 1, "no");
        vm.stopPrank();
        _assertAUntouched();

        vm.warp(_readyAt(B));
        _complete(B);
        _assertAUntouched();

        vm.prank(client2);
        retainer.extendEndTime(B, END + 31 days);
        _assertAUntouched();
        _assertAcct(B, 3e6, 0, 10e6, 2e6, 5e6, 0);
    }

    // ---------------------------------------------------------------- cross-party authorization

    function test_isolation_freelancerOfA_cannotFileOnB() public {
        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.NotFreelancer.selector);
        retainer.fileClaim(B, 1e6, "x");
        _assertBUntouched();
    }

    function test_isolation_freelancerOfA_cannotCancelClaimOnB() public {
        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.NotFreelancer.selector);
        retainer.cancelClaim(B, 0);
        _assertBUntouched();
    }

    function test_isolation_freelancerOfB_cannotFileOnA() public {
        vm.prank(freelancer2);
        vm.expectRevert(UnlessRetainer.NotFreelancer.selector);
        retainer.fileClaim(A, 1e6, "x");
        _assertAUntouched();
    }

    function test_isolation_clientOfA_cannotApproveClaimOnB() public {
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.approveClaim(B, 0);
        _assertBUntouched();
    }

    function test_isolation_clientOfA_cannotObjectToClaimOnB() public {
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.objectToClaim(B, 0, "no");
        _assertBUntouched();
    }

    function test_isolation_clientOfA_cannotRequestWithdrawalOnB() public {
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.requestWithdrawal(B, 1e6);
        _assertBUntouched();
    }

    function test_isolation_clientOfA_cannotCancelWithdrawalOnB() public {
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.cancelWithdrawal(B);
        _assertBUntouched();
    }

    function test_isolation_clientOfA_cannotDepositOnB() public {
        _approve(client, 1e6);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.deposit(B, 1e6);
        _assertBUntouched();
    }

    function test_isolation_clientOfA_cannotExtendB() public {
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.extendEndTime(B, END + 365 days);
        _assertBUntouched();
    }

    function test_isolation_clientOfA_cannotWithdrawRemainderOfB() public {
        vm.warp(uint256(END) + 31 days);
        assertTrue(_isEnded(B));

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.withdrawRemainder(B);
        assertEq(uint256(_ret(B).balance), 10e6);
    }

    function test_isolation_clientOfB_cannotActOnA() public {
        uint256 claimId = _file(A, 3e6, "a");
        fpA = _fingerprint(A);

        vm.startPrank(client2);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.approveClaim(A, claimId);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.objectToClaim(A, claimId, "no");
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.requestWithdrawal(A, 1e6);
        vm.stopPrank();

        _assertAUntouched();
    }
}
