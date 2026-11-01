// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {UnlessRetainer} from "../UnlessRetainer.sol";
import {UnlessRetainerBase} from "./UnlessRetainer.Base.t.sol";

/// @notice Extends the shared base with helpers that read state ONLY through the real public view
/// functions (getRetainer, getClaim, getClaims, owed, totalOwed, nextRetainerId), plus the event
/// expectations for the withdrawal / remainder / extension / credit events.
/// Holds no test, fuzz or invariant functions.
abstract contract UnlessRetainerExtBase is UnlessRetainerBase {
    // ---------------------------------------------------------------- view-based readers

    function _ret(uint256 id) internal view returns (UnlessRetainer.Retainer memory r) {
        (r,,) = retainer.getRetainer(id);
    }

    function _avail(uint256 id) internal view returns (uint256 a) {
        (, a,) = retainer.getRetainer(id);
    }

    function _isEnded(uint256 id) internal view returns (bool e) {
        (,, e) = retainer.getRetainer(id);
    }

    function _claimV(uint256 id, uint256 claimId) internal view returns (UnlessRetainer.Claim memory) {
        return retainer.getClaim(id, claimId);
    }

    /// @dev Same shape as the base `_assertState` but reads through getRetainer.
    function _assertAcct(
        uint256 id,
        uint256 balance,
        uint256 reserved,
        uint256 totalDeposited,
        uint256 totalPaid,
        uint256 totalReturned,
        uint256 pendingClaims
    ) internal view {
        (UnlessRetainer.Retainer memory r, uint256 available,) = retainer.getRetainer(id);
        assertEq(uint256(r.balance), balance, "balance");
        assertEq(uint256(r.reserved), reserved, "reserved");
        assertEq(uint256(r.totalDeposited), totalDeposited, "totalDeposited");
        assertEq(uint256(r.totalPaid), totalPaid, "totalPaid");
        assertEq(uint256(r.totalReturned), totalReturned, "totalReturned");
        assertEq(uint256(r.pendingClaims), pendingClaims, "pendingClaims");
        assertEq(available, balance - reserved, "available");
        // I-4: balance == totalDeposited - totalPaid - totalReturned
        assertEq(uint256(r.balance), uint256(r.totalDeposited) - r.totalPaid - r.totalReturned, "I-4");
    }

    function _assertClaimV(
        uint256 id,
        uint256 claimId,
        uint256 amount,
        UnlessRetainer.ClaimStatus status,
        UnlessRetainer.PaidVia via
    ) internal view {
        UnlessRetainer.Claim memory c = retainer.getClaim(id, claimId);
        assertEq(uint256(c.amount), amount, "claim amount");
        assertEq(uint256(c.status), uint256(status), "claim status");
        assertEq(uint256(c.paidVia), uint256(via), "claim paidVia");
    }

    function _assertWithdrawal(uint256 id, uint256 amount, uint256 readyAt) internal view {
        UnlessRetainer.Retainer memory r = _ret(id);
        assertEq(uint256(r.withdrawalAmount), amount, "withdrawalAmount");
        assertEq(uint256(r.withdrawalReadyAt), readyAt, "withdrawalReadyAt");
    }

    function _assertNoWithdrawal(uint256 id) internal view {
        _assertWithdrawal(id, 0, 0);
    }

    /// @dev Token solvency: tokens held == sum of every retainer balance + totalOwed.
    function _assertSolvent() internal view {
        uint256 sum;
        uint256 n = retainer.nextRetainerId();
        for (uint256 i = 0; i < n; i++) {
            sum += _ret(i).balance;
        }
        assertEq(usdc.balanceOf(address(retainer)), sum + retainer.totalOwed(), "solvency");
    }

    /// @dev Hash of everything observable about a retainer: struct, available, ended and all claims.
    function _fingerprint(uint256 id) internal view returns (bytes32) {
        (UnlessRetainer.Retainer memory r, uint256 a, bool e) = retainer.getRetainer(id);
        return keccak256(abi.encode(r, a, e, retainer.getClaims(id, 0, type(uint256).max)));
    }

    // ---------------------------------------------------------------- action helpers

    function _createEnding(address c, address f, uint128 dep, uint64 endTime) internal returns (uint256 id) {
        if (dep > 0) _approve(c, dep);
        vm.prank(c);
        id = retainer.createRetainer(f, WINDOW, NOTICE, endTime, dep);
    }

    function _request(uint256 id, uint128 amount) internal {
        vm.prank(client);
        retainer.requestWithdrawal(id, amount);
    }

    function _cancelWd(uint256 id) internal {
        vm.prank(client);
        retainer.cancelWithdrawal(id);
    }

    function _complete(uint256 id) internal {
        vm.prank(stranger);
        retainer.completeWithdrawal(id);
    }

    function _payableAtV(uint256 id, uint256 claimId) internal view returns (uint64) {
        return retainer.getClaim(id, claimId).payableAt;
    }

    function _readyAt(uint256 id) internal view returns (uint64) {
        return _ret(id).withdrawalReadyAt;
    }

    // ---------------------------------------------------------------- event expectations

    function _expectRequested(uint256 id, uint128 amount, uint64 readyAt) internal {
        vm.expectEmit(true, true, true, true, address(retainer));
        emit UnlessRetainer.WithdrawalRequested(id, amount, readyAt);
    }

    function _expectWdCancelled(uint256 id) internal {
        vm.expectEmit(true, true, true, true, address(retainer));
        emit UnlessRetainer.WithdrawalCancelled(id);
    }

    function _expectWdCompleted(uint256 id, uint128 requested, uint128 paid) internal {
        vm.expectEmit(true, true, true, true, address(retainer));
        emit UnlessRetainer.WithdrawalCompleted(id, requested, paid);
    }

    function _expectRemainder(uint256 id, uint128 amount) internal {
        vm.expectEmit(true, true, true, true, address(retainer));
        emit UnlessRetainer.RemainderWithdrawn(id, amount);
    }

    function _expectExtended(uint256 id, uint64 oldEnd, uint64 newEnd) internal {
        vm.expectEmit(true, true, true, true, address(retainer));
        emit UnlessRetainer.EndTimeExtended(id, oldEnd, newEnd);
    }

    function _expectDeferred(address to, uint256 amount) internal {
        vm.expectEmit(true, true, true, true, address(retainer));
        emit UnlessRetainer.PayoutDeferred(to, amount);
    }

    function _expectOwedWithdrawn(address to, uint256 amount) internal {
        vm.expectEmit(true, true, true, true, address(retainer));
        emit UnlessRetainer.OwedWithdrawn(to, amount);
    }

    /// @dev ERC-20 Transfer emitted by the token (indexed from, indexed to, data value).
    function _expectTransfer(address from, address to, uint256 amount) internal {
        vm.expectEmit(true, true, false, true, address(usdc));
        emit IERC20.Transfer(from, to, amount);
    }

    /// @dev Logs not emitted by the test contract itself (expectEmit's `emit` lines are recorded too).
    function _foreignLogs(Vm.Log[] memory logs) internal view returns (Vm.Log[] memory out) {
        uint256 n;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != address(this)) n++;
        }
        out = new Vm.Log[](n);
        uint256 j;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != address(this)) out[j++] = logs[i];
        }
    }

    /// @dev topic0 of each retainer-emitted log, in emission order.
    function _topics0(Vm.Log[] memory all) internal view returns (bytes32[] memory out) {
        Vm.Log[] memory logs = _retainerLogs(all);
        out = new bytes32[](logs.length);
        for (uint256 i = 0; i < logs.length; i++) {
            out[i] = logs[i].topics[0];
        }
    }
}
