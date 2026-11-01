// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {UnlessRetainer} from "../UnlessRetainer.sol";
import {UnlessRetainerExtBase} from "./UnlessRetainer.ExtBase.t.sol";
import {BlocklistUSDC} from "./mocks/BlocklistUSDC.sol";
import {FalseReturnUSDC} from "./mocks/FalseReturnUSDC.sol";

/// @notice 4.9 (deferred from P3a) + 4.12: completeWithdrawal credit fallback and the withdrawOwed
/// pull cycle. Scenarios are shared; the concrete contracts below plug in the blocklisting token.
abstract contract UnlessRetainerOwedScenarios is UnlessRetainerExtBase {
    function _setBlocked(address account, bool isBlocked) internal virtual;

    /// @dev Arms the exact revert a failing `withdrawOwed` produces for `recipient` with this token.
    function _expectStillBlockedRevert(address recipient) internal virtual;

    /// @dev Retainer 0: client deposits 10 and requests 4. Client gets blocked, the notice elapses
    /// and a stranger completes. Returns the retainer id. Credit: owed[client] == 4.
    function _blockedClientCompleted() internal returns (uint256 id) {
        id = _create(10e6);
        _request(id, 4e6);
        _setBlocked(client, true);
        vm.warp(_readyAt(id));
        _complete(id);
    }

    function _withdrawOwedAs(address who) internal {
        vm.prank(who);
        retainer.withdrawOwed();
    }

    // ---------------------------------------------------------------- completeWithdrawal credit

    function test_completeWithdrawal_blockedClient_succeedsAndCreditsOwed() public {
        uint256 id = _create(10e6);
        _request(id, 4e6);
        _setBlocked(client, true);
        vm.warp(_readyAt(id));
        uint256 clientTokens = usdc.balanceOf(client);

        vm.recordLogs();
        _expectWdCompleted(id, 4e6, 4e6);
        _expectDeferred(client, 4e6);
        _complete(id);
        bytes32[] memory topics0 = _topics0(vm.getRecordedLogs());

        assertEq(topics0.length, 2, "WithdrawalCompleted + PayoutDeferred only");
        assertEq(topics0[0], UnlessRetainer.WithdrawalCompleted.selector, "completed first");
        assertEq(topics0[1], UnlessRetainer.PayoutDeferred.selector, "deferred second");
        assertEq(retainer.owed(client), 4e6, "owed[client]");
        assertEq(retainer.totalOwed(), 4e6, "totalOwed");
        assertEq(usdc.balanceOf(client), clientTokens, "client token balance unchanged");
        assertEq(usdc.balanceOf(address(retainer)), 10e6, "tokens stay in the contract");
        _assertNoWithdrawal(id);
        _assertAcct(id, 6e6, 0, 10e6, 0, 4e6, 0);
        _assertSolvent();
    }

    function test_completeWithdrawal_blockedClient_retainerAccountingIdenticalToNormalCompletion() public {
        uint256 blockedId = _createFor(client, freelancer, 10e6);
        uint256 normalId = _createFor(client2, freelancer2, 10e6);
        _request(blockedId, 4e6);
        vm.prank(client2);
        retainer.requestWithdrawal(normalId, 4e6);
        _setBlocked(client, true);
        vm.warp(_readyAt(blockedId));

        _complete(blockedId); // deferred
        _complete(normalId); // normal

        UnlessRetainer.Retainer memory b = _ret(blockedId);
        UnlessRetainer.Retainer memory n = _ret(normalId);
        assertEq(uint256(b.balance), uint256(n.balance), "balance");
        assertEq(uint256(b.reserved), uint256(n.reserved), "reserved");
        assertEq(uint256(b.totalDeposited), uint256(n.totalDeposited), "totalDeposited");
        assertEq(uint256(b.totalPaid), uint256(n.totalPaid), "totalPaid");
        assertEq(uint256(b.totalReturned), uint256(n.totalReturned), "totalReturned");
        assertEq(uint256(b.pendingClaims), uint256(n.pendingClaims), "pendingClaims");
        assertEq(uint256(b.claimCount), uint256(n.claimCount), "claimCount");
        assertEq(uint256(b.withdrawalAmount), uint256(n.withdrawalAmount), "withdrawalAmount");
        assertEq(uint256(b.withdrawalReadyAt), uint256(n.withdrawalReadyAt), "withdrawalReadyAt");
        assertEq(retainer.owed(client), 4e6, "blocked client credited");
        assertEq(retainer.owed(client2), 0, "normal client paid directly");
        assertEq(usdc.balanceOf(client2), START_BALANCE - 10e6 + 4e6, "normal client received tokens");
        _assertSolvent();
    }

    function test_completeWithdrawal_blockedClientOnOneRetainer_leavesOtherRetainerUntouched() public {
        uint256 idA = _createFor(client, freelancer, 10e6);
        uint256 idB = _createFor(client2, freelancer2, 10e6);
        _request(idA, 4e6);
        vm.prank(client2);
        retainer.requestWithdrawal(idB, 6e6);
        _setBlocked(client, true);
        vm.warp(_readyAt(idA));
        bytes32 fpB = _fingerprint(idB);

        _complete(idA);

        assertEq(_fingerprint(idB), fpB, "retainer B untouched");
        assertEq(retainer.owed(client2), 0, "no credit for other client");
        assertEq(retainer.owed(client), 4e6);
        _assertSolvent();

        // The other client's withdrawal still pays normally and the credit is unaffected.
        _expectWdCompleted(idB, 6e6, 6e6);
        _complete(idB);
        assertEq(usdc.balanceOf(client2), START_BALANCE - 10e6 + 6e6);
        assertEq(retainer.owed(client), 4e6);
        assertEq(retainer.totalOwed(), 4e6);
        _assertSolvent();
        vm.prank(client2);
        vm.expectRevert(UnlessRetainer.NothingOwed.selector);
        retainer.withdrawOwed();
    }

    function test_completeWithdrawal_twoDeferredCompletions_accumulateOwed() public {
        uint256 id = _blockedClientCompleted();
        _request(id, 2e6);
        vm.warp(_readyAt(id));

        _expectWdCompleted(id, 2e6, 2e6);
        _expectDeferred(client, 2e6);
        _complete(id);

        assertEq(retainer.owed(client), 6e6, "owed accumulates");
        assertEq(retainer.totalOwed(), 6e6);
        _assertAcct(id, 4e6, 0, 10e6, 0, 6e6, 0);
        _assertSolvent();

        _setBlocked(client, false);
        uint256 before = usdc.balanceOf(client);
        _expectTransfer(address(retainer), client, 6e6);
        _expectOwedWithdrawn(client, 6e6);
        _withdrawOwedAs(client);
        assertEq(usdc.balanceOf(client), before + 6e6);
        assertEq(retainer.totalOwed(), 0);
        _assertSolvent();
    }

    // ---------------------------------------------------------------- withdrawOwed: client credit

    function test_withdrawOwed_blockedClientAfterUnblock_transfersAndZeroesCredit() public {
        uint256 id = _blockedClientCompleted();
        _assertSolvent();
        _setBlocked(client, false);
        uint256 before = usdc.balanceOf(client);

        _expectTransfer(address(retainer), client, 4e6);
        _expectOwedWithdrawn(client, 4e6);
        _withdrawOwedAs(client);

        assertEq(usdc.balanceOf(client), before + 4e6, "recipient received exactly the credit");
        assertEq(retainer.owed(client), 0, "owed zeroed");
        assertEq(retainer.totalOwed(), 0, "totalOwed zeroed");
        assertEq(usdc.balanceOf(address(retainer)), 6e6, "contract keeps retainer funds");
        _assertAcct(id, 6e6, 0, 10e6, 0, 4e6, 0);
        _assertSolvent();
    }

    function test_withdrawOwed_calledTwice_secondRevertsNothingOwed() public {
        _blockedClientCompleted();
        _setBlocked(client, false);
        _withdrawOwedAs(client);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.NothingOwed.selector);
        retainer.withdrawOwed();
        _assertSolvent();
    }

    function test_withdrawOwed_clientStillBlocked_revertsAndPreservesCredit() public {
        uint256 id = _blockedClientCompleted();
        uint256 clientTokens = usdc.balanceOf(client);

        vm.prank(client);
        _expectStillBlockedRevert(client);
        retainer.withdrawOwed();

        assertEq(retainer.owed(client), 4e6, "owed preserved");
        assertEq(retainer.totalOwed(), 4e6, "totalOwed preserved");
        assertEq(usdc.balanceOf(client), clientTokens);
        assertEq(usdc.balanceOf(address(retainer)), 10e6);
        _assertAcct(id, 6e6, 0, 10e6, 0, 4e6, 0);
        _assertSolvent();

        // After unblocking, the preserved credit is claimable in full.
        _setBlocked(client, false);
        _withdrawOwedAs(client);
        assertEq(usdc.balanceOf(client), clientTokens + 4e6);
    }

    function test_withdrawOwed_noCredit_revertsNothingOwed() public {
        _blockedClientCompleted();

        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NothingOwed.selector);
        retainer.withdrawOwed();

        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.NothingOwed.selector);
        retainer.withdrawOwed();

        assertEq(retainer.owed(client), 4e6, "client credit untouched");
        assertEq(retainer.totalOwed(), 4e6);
    }

    function test_withdrawOwed_freshContract_revertsNothingOwed() public {
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.NothingOwed.selector);
        retainer.withdrawOwed();
    }

    // ---------------------------------------------------------------- withdrawOwed: freelancer credit

    /// @dev Retainer 0: deposit 10, freelancer claim 3 filed, freelancer blocked, claim paid out.
    function _blockedFreelancerPaidOut() internal returns (uint256 id, uint256 claimId) {
        (id, claimId) = _setupClaim(10e6, 3e6);
        _setBlocked(freelancer, true);
        vm.warp(_payableAtV(id, claimId));
        _payOut(id, claimId);
    }

    function test_withdrawOwed_blockedFreelancerAfterUnblock_transfersAndZeroesCredit() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        _setBlocked(freelancer, true);
        vm.warp(_payableAtV(id, claimId));
        uint256 freelancerTokens = usdc.balanceOf(freelancer);

        _expectPaid(id, claimId, freelancer, 3e6, UnlessRetainer.PaidVia.PaidOut);
        _expectDeferred(freelancer, 3e6);
        _payOut(id, claimId);

        assertEq(retainer.owed(freelancer), 3e6, "owed[freelancer]");
        assertEq(retainer.totalOwed(), 3e6);
        assertEq(usdc.balanceOf(freelancer), freelancerTokens, "tokens unchanged");
        _assertAcct(id, 7e6, 0, 10e6, 3e6, 0, 0);
        _assertSolvent();

        _setBlocked(freelancer, false);
        _expectTransfer(address(retainer), freelancer, 3e6);
        _expectOwedWithdrawn(freelancer, 3e6);
        _withdrawOwedAs(freelancer);

        assertEq(usdc.balanceOf(freelancer), freelancerTokens + 3e6, "received exactly the credit");
        assertEq(retainer.owed(freelancer), 0);
        assertEq(retainer.totalOwed(), 0);
        _assertAcct(id, 7e6, 0, 10e6, 3e6, 0, 0);
        _assertSolvent();

        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.NothingOwed.selector);
        retainer.withdrawOwed();
    }

    function test_withdrawOwed_freelancerStillBlocked_revertsAndPreservesCredit() public {
        (uint256 id,) = _blockedFreelancerPaidOut();
        uint256 freelancerTokens = usdc.balanceOf(freelancer);

        vm.prank(freelancer);
        _expectStillBlockedRevert(freelancer);
        retainer.withdrawOwed();

        assertEq(retainer.owed(freelancer), 3e6, "owed preserved");
        assertEq(retainer.totalOwed(), 3e6, "totalOwed preserved");
        assertEq(usdc.balanceOf(freelancer), freelancerTokens);
        _assertAcct(id, 7e6, 0, 10e6, 3e6, 0, 0);
        _assertSolvent();
    }

    function test_withdrawOwed_freelancerCredit_cannotBeWithdrawnByClientOrStranger() public {
        _blockedFreelancerPaidOut();
        _setBlocked(freelancer, false);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.NothingOwed.selector);
        retainer.withdrawOwed();

        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NothingOwed.selector);
        retainer.withdrawOwed();

        assertEq(retainer.owed(freelancer), 3e6);
        assertEq(retainer.totalOwed(), 3e6);
    }

    function test_withdrawOwed_bothPartiesCredited_unblockedOneWithdrawsOtherPreserved() public {
        uint256 id = _create(10e6);
        uint256 claimId = _file(id, 3e6, "c");
        _request(id, 4e6);
        _setBlocked(client, true);
        _setBlocked(freelancer, true);
        vm.warp(_readyAt(id)); // readyAt (t0 + 300) == payableAt (t0 + 300)
        _payOut(id, claimId);
        _complete(id);

        assertEq(retainer.owed(freelancer), 3e6);
        assertEq(retainer.owed(client), 4e6);
        assertEq(retainer.totalOwed(), 7e6);
        _assertAcct(id, 3e6, 0, 10e6, 3e6, 4e6, 0);
        _assertSolvent();

        _setBlocked(client, false);
        _expectOwedWithdrawn(client, 4e6);
        _withdrawOwedAs(client);

        assertEq(retainer.owed(client), 0);
        assertEq(retainer.owed(freelancer), 3e6, "freelancer credit preserved");
        assertEq(retainer.totalOwed(), 3e6);
        _assertSolvent();

        vm.prank(freelancer);
        _expectStillBlockedRevert(freelancer);
        retainer.withdrawOwed();
        assertEq(retainer.totalOwed(), 3e6);
        _assertSolvent();
    }

    // ---------------------------------------------------------------- 4.10: remainder credit

    function test_withdrawRemainder_blockedClient_succeedsAndCreditsOwed() public {
        uint256 id = _create(10e6);
        _setBlocked(client, true);
        vm.warp(END);
        uint256 clientTokens = usdc.balanceOf(client);

        vm.recordLogs();
        _expectRemainder(id, 10e6);
        _expectDeferred(client, 10e6);
        vm.prank(client);
        retainer.withdrawRemainder(id);
        bytes32[] memory topics0 = _topics0(vm.getRecordedLogs());

        assertEq(topics0.length, 2);
        assertEq(topics0[0], UnlessRetainer.RemainderWithdrawn.selector);
        assertEq(topics0[1], UnlessRetainer.PayoutDeferred.selector);
        assertEq(retainer.owed(client), 10e6);
        assertEq(retainer.totalOwed(), 10e6);
        assertEq(usdc.balanceOf(client), clientTokens, "client tokens unchanged");
        _assertAcct(id, 0, 0, 10e6, 0, 10e6, 0);
        _assertSolvent();

        _setBlocked(client, false);
        _expectOwedWithdrawn(client, 10e6);
        _withdrawOwedAs(client);
        assertEq(usdc.balanceOf(client), clientTokens + 10e6);
        _assertSolvent();
    }
}

/// @notice BlocklistUSDC variant: a blocked recipient makes transfer revert with Blocked(account).
contract UnlessRetainerOwedBlocklistTest is UnlessRetainerOwedScenarios {
    function setUp() public override {
        _initActors();
        _deploy(new BlocklistUSDC());
    }

    function _setBlocked(address account, bool isBlocked) internal override {
        BlocklistUSDC(address(usdc)).setBlocked(account, isBlocked);
    }

    function _expectStillBlockedRevert(address recipient) internal override {
        vm.expectRevert(abi.encodeWithSelector(BlocklistUSDC.Blocked.selector, recipient));
    }
}

/// @notice FalseReturnUSDC variant: transfer returns false, so SafeERC20 reverts with
/// SafeERC20FailedOperation(token) on the pull path.
contract UnlessRetainerOwedFalseReturnTest is UnlessRetainerOwedScenarios {
    function setUp() public override {
        _initActors();
        _deploy(new FalseReturnUSDC());
    }

    function _setBlocked(address account, bool isBlocked) internal override {
        FalseReturnUSDC(address(usdc)).setBlocked(account, isBlocked);
    }

    function _expectStillBlockedRevert(address) internal override {
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(usdc)));
    }
}
