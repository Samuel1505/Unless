// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";

import {UnlessRetainer} from "../UnlessRetainer.sol";
import {UnlessRetainerBase} from "./UnlessRetainer.Base.t.sol";
import {BlocklistUSDC} from "./mocks/BlocklistUSDC.sol";
import {FalseReturnUSDC} from "./mocks/FalseReturnUSDC.sol";

/// @notice Credit fallback (4.12), the part reachable without withdrawOwed / completeWithdrawal.
/// Shared scenarios; the concrete contracts below plug in the blocklisting token.
abstract contract UnlessRetainerFallbackScenarios is UnlessRetainerBase {
    UnlessRetainer.ClaimStatus internal constant PAID = UnlessRetainer.ClaimStatus.Paid;

    function _setBlocked(address account, bool isBlocked) internal virtual;

    /// @dev Retainer 0 (client -> freelancer, blocked) and retainer 1 (client2 -> freelancer2, normal),
    /// both funded with 10 and holding a claim of 3. Returns once both claims are payable.
    function _twoRetainersWithClaims() internal {
        _createFor(client, freelancer, 10e6);
        _createFor(client2, freelancer2, 10e6);
        _file(0, 3e6, "blocked");
        vm.prank(freelancer2);
        retainer.fileClaim(1, 3e6, "normal");
        vm.warp(_payableAt(0, 0));
        assertEq(uint256(_payableAt(1, 0)), uint256(_payableAt(0, 0)), "same payableAt");
    }

    function _assertDeferredPayout(uint256 id, UnlessRetainer.PaidVia via) internal view {
        _assertState(id, 7e6, 0, 10e6, 3e6, 0, 0);
        _assertClaim(id, 0, 3e6, PAID, via);
        assertEq(retainer.owed(freelancer), 3e6, "owed[freelancer]");
        assertEq(retainer.totalOwed(), 3e6, "totalOwed");
        assertEq(usdc.balanceOf(freelancer), START_BALANCE, "freelancer token balance unchanged");
        assertEq(usdc.balanceOf(address(retainer)), 10e6, "tokens stay in the contract");
        // Solvency: tokens held == retainer balances + totalOwed.
        assertEq(usdc.balanceOf(address(retainer)), retainer.retainerOf(id).balance + retainer.totalOwed());
    }

    function _assertLogOrderPaidThenDeferred(Vm.Log[] memory all) internal view {
        Vm.Log[] memory logs = _retainerLogs(all);
        assertEq(logs.length, 2, "ClaimPaid + PayoutDeferred only");
        assertEq(logs[0].topics[0], UnlessRetainer.ClaimPaid.selector, "ClaimPaid first");
        assertEq(logs[1].topics[0], UnlessRetainer.PayoutDeferred.selector, "PayoutDeferred second");
    }

    function test_payOutClaim_blockedFreelancer_succeedsAndCreditsOwed() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        _setBlocked(freelancer, true);
        vm.warp(_payableAt(id, claimId));

        vm.recordLogs();
        _expectPaid(id, claimId, freelancer, 3e6, UnlessRetainer.PaidVia.PaidOut);
        vm.expectEmit(true, true, true, true, address(retainer));
        emit UnlessRetainer.PayoutDeferred(freelancer, 3e6);
        vm.prank(stranger);
        retainer.payOutClaim(id, claimId);

        _assertDeferredPayout(id, UnlessRetainer.PaidVia.PaidOut);
        _assertLogOrderPaidThenDeferred(vm.getRecordedLogs());
        assertEq(usdc.balanceOf(stranger), START_BALANCE, "stranger unchanged");
    }

    function test_approveClaim_blockedFreelancer_succeedsAndCreditsOwed() public {
        (uint256 id, uint256 claimId) = _setupClaim(10e6, 3e6);
        _setBlocked(freelancer, true);

        vm.recordLogs();
        _expectPaid(id, claimId, freelancer, 3e6, UnlessRetainer.PaidVia.ApprovedNow);
        vm.expectEmit(true, true, true, true, address(retainer));
        emit UnlessRetainer.PayoutDeferred(freelancer, 3e6);
        vm.prank(client);
        retainer.approveClaim(id, claimId);

        _assertDeferredPayout(id, UnlessRetainer.PaidVia.ApprovedNow);
        _assertLogOrderPaidThenDeferred(vm.getRecordedLogs());
    }

    function test_payOutClaim_blockedFreelancer_retainerAccountingIdenticalToNormalPayout() public {
        _twoRetainersWithClaims();
        _setBlocked(freelancer, true);

        _payOut(0, 0); // deferred
        _payOut(1, 0); // normal

        UnlessRetainer.Retainer memory blockedR = retainer.retainerOf(0);
        UnlessRetainer.Retainer memory normalR = retainer.retainerOf(1);
        assertEq(uint256(blockedR.balance), uint256(normalR.balance), "balance");
        assertEq(uint256(blockedR.reserved), uint256(normalR.reserved), "reserved");
        assertEq(uint256(blockedR.totalDeposited), uint256(normalR.totalDeposited), "totalDeposited");
        assertEq(uint256(blockedR.totalPaid), uint256(normalR.totalPaid), "totalPaid");
        assertEq(uint256(blockedR.totalReturned), uint256(normalR.totalReturned), "totalReturned");
        assertEq(uint256(blockedR.pendingClaims), uint256(normalR.pendingClaims), "pendingClaims");
        assertEq(uint256(blockedR.claimCount), uint256(normalR.claimCount), "claimCount");
        UnlessRetainer.Claim memory blockedC = retainer.claimOf(0, 0);
        UnlessRetainer.Claim memory normalC = retainer.claimOf(1, 0);
        assertEq(uint256(blockedC.status), uint256(normalC.status), "claim status");
        assertEq(uint256(blockedC.paidVia), uint256(normalC.paidVia), "claim paidVia");
        assertEq(uint256(blockedC.amount), uint256(normalC.amount), "claim amount");

        // Only the token delivery differs.
        assertEq(usdc.balanceOf(freelancer), START_BALANCE, "blocked freelancer got nothing");
        assertEq(usdc.balanceOf(freelancer2), START_BALANCE + 3e6, "normal freelancer paid");
        assertEq(retainer.owed(freelancer), 3e6);
        assertEq(retainer.owed(freelancer2), 0);
        assertEq(retainer.totalOwed(), 3e6);
        // Solvency across both retainers: 7 + 7 + owed 3 == 17 held.
        assertEq(usdc.balanceOf(address(retainer)), 7e6 + 7e6 + retainer.totalOwed());
    }

    function test_payOutClaim_blockedFreelancer_doesNotBlockOtherClaimsOfSameRetainer() public {
        uint256 id = _create(10e6);
        _file(id, 3e6, "a");
        _file(id, 2e6, "b");
        _setBlocked(freelancer, true);
        vm.warp(_payableAt(id, 0));

        _payOut(id, 0);
        _payOut(id, 1);

        _assertState(id, 5e6, 0, 10e6, 5e6, 0, 0);
        assertEq(retainer.owed(freelancer), 5e6, "credits accumulate");
        assertEq(retainer.totalOwed(), 5e6);
        assertEq(usdc.balanceOf(address(retainer)), 10e6);
    }

    function test_payOutClaim_blockedThenUnblockedFreelancer_laterPayoutIsDirect() public {
        uint256 id = _create(10e6);
        _file(id, 3e6, "a");
        _file(id, 2e6, "b");
        vm.warp(_payableAt(id, 0));

        _setBlocked(freelancer, true);
        _payOut(id, 0); // deferred
        _setBlocked(freelancer, false);
        _payOut(id, 1); // direct

        assertEq(retainer.owed(freelancer), 3e6, "only the first payout was deferred");
        assertEq(usdc.balanceOf(freelancer), START_BALANCE + 2e6);
        _assertState(id, 5e6, 0, 10e6, 5e6, 0, 0);
    }

    function test_approveClaim_blockedFreelancerOnOneRetainer_leavesOtherRetainerUntouched() public {
        _twoRetainersWithClaims();
        _setBlocked(freelancer, true);
        UnlessRetainer.Retainer memory before2 = retainer.retainerOf(1);
        UnlessRetainer.Claim memory beforeC2 = retainer.claimOf(1, 0);

        _approveNow(0, 0);

        assertEq(keccak256(abi.encode(retainer.retainerOf(1))), keccak256(abi.encode(before2)));
        assertEq(keccak256(abi.encode(retainer.claimOf(1, 0))), keccak256(abi.encode(beforeC2)));
        assertEq(usdc.balanceOf(freelancer2), START_BALANCE);
    }
}

/// @notice BlocklistUSDC variant: the token reverts when the recipient is blocked.
contract UnlessRetainerBlocklistFallbackTest is UnlessRetainerFallbackScenarios {
    function setUp() public override {
        _initActors();
        _deploy(new BlocklistUSDC());
    }

    function _setBlocked(address account, bool isBlocked) internal override {
        BlocklistUSDC(address(usdc)).setBlocked(account, isBlocked);
    }
}

/// @notice FalseReturnUSDC variant: the token returns false when the recipient is blocked.
contract UnlessRetainerFalseReturnFallbackTest is UnlessRetainerFallbackScenarios {
    function setUp() public override {
        _initActors();
        _deploy(new FalseReturnUSDC());
    }

    function _setBlocked(address account, bool isBlocked) internal override {
        FalseReturnUSDC(address(usdc)).setBlocked(account, isBlocked);
    }
}
