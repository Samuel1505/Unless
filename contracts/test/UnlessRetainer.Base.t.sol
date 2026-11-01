// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {UnlessRetainer} from "../UnlessRetainer.sol";
import {UnlessRetainerHarness} from "./harness/UnlessRetainerHarness.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

/// @notice Shared fixtures and helpers. Fixtures follow docs/04-TEST-PLAN.md sections 2.2 and 2.3.
/// Holds no test, fuzz or invariant functions: every category file inherits it.
abstract contract UnlessRetainerBase is Test {
    // ---------------------------------------------------------------- actors (2.2)
    address internal client;
    address internal freelancer;
    address internal stranger;
    address internal client2;
    address internal freelancer2;

    // ---------------------------------------------------------------- defaults (2.3)
    uint32 internal constant WINDOW = 300; // 5 minutes, matches demo
    uint32 internal constant NOTICE = 300;
    uint64 internal END;

    uint32 internal constant MIN_WINDOW = 60;
    uint32 internal constant MAX_WINDOW = 30 days;
    uint32 internal constant MIN_NOTICE = 60;
    uint32 internal constant MAX_NOTICE = 60 days;
    uint256 internal constant MAX_PENDING = 20;
    uint256 internal constant MAX_TEXT = 280;

    uint256 internal constant START_BALANCE = 1_000e6;

    MockUSDC internal usdc;
    UnlessRetainerHarness internal retainer;

    function setUp() public virtual {
        _initActors();
        _deploy(new MockUSDC());
    }

    function _initActors() internal {
        client = makeAddr("client");
        freelancer = makeAddr("freelancer");
        stranger = makeAddr("stranger");
        client2 = makeAddr("client2");
        freelancer2 = makeAddr("freelancer2");
        END = uint64(block.timestamp + 7 days);
    }

    /// @dev Binds `usdc`/`retainer` to a fresh token + harness and mints 1,000 USDC to every actor.
    /// Approvals are exact and happen inside each test.
    function _deploy(MockUSDC token) internal {
        usdc = token;
        retainer = new UnlessRetainerHarness(IERC20(address(token)));
        usdc.mint(client, START_BALANCE);
        usdc.mint(freelancer, START_BALANCE);
        usdc.mint(stranger, START_BALANCE);
        usdc.mint(client2, START_BALANCE);
        usdc.mint(freelancer2, START_BALANCE);
    }

    // ---------------------------------------------------------------- action helpers

    function _approve(address actor, uint256 amount) internal {
        vm.prank(actor);
        usdc.approve(address(retainer), amount);
    }

    /// @dev client -> freelancer retainer with default terms; approves exactly `dep`.
    function _create(uint128 dep) internal returns (uint256) {
        return _createFor(client, freelancer, dep);
    }

    function _createFor(address c, address f, uint128 dep) internal returns (uint256 id) {
        if (dep > 0) _approve(c, dep);
        vm.prank(c);
        id = retainer.createRetainer(f, WINDOW, NOTICE, END, dep);
    }

    function _file(uint256 id, uint128 amount, string memory note) internal returns (uint256 claimId) {
        vm.prank(freelancer);
        claimId = retainer.fileClaim(id, amount, note);
    }

    /// @dev Retainer 0 with `dep` deposited and a claim 0 for `amount` filed. Returns (id, claimId).
    function _setupClaim(uint128 dep, uint128 amount) internal returns (uint256 id, uint256 claimId) {
        id = _create(dep);
        claimId = _file(id, amount, "note");
    }

    function _payableAt(uint256 id, uint256 claimId) internal view returns (uint64) {
        return retainer.claimOf(id, claimId).payableAt;
    }

    function _payOut(uint256 id, uint256 claimId) internal {
        vm.prank(stranger);
        retainer.payOutClaim(id, claimId);
    }

    function _approveNow(uint256 id, uint256 claimId) internal {
        vm.prank(client);
        retainer.approveClaim(id, claimId);
    }

    function _object(uint256 id, uint256 claimId) internal {
        vm.prank(client);
        retainer.objectToClaim(id, claimId, "no");
    }

    function _cancel(uint256 id, uint256 claimId) internal {
        vm.prank(freelancer);
        retainer.cancelClaim(id, claimId);
    }

    /// @dev A string of exactly `n` bytes.
    function _str(uint256 n) internal pure returns (string memory) {
        bytes memory b = new bytes(n);
        for (uint256 i = 0; i < n; i++) {
            b[i] = "a";
        }
        return string(b);
    }

    // ---------------------------------------------------------------- state assertions

    function _assertState(
        uint256 id,
        uint256 balance,
        uint256 reserved,
        uint256 totalDeposited,
        uint256 totalPaid,
        uint256 totalReturned,
        uint256 pendingClaims
    ) internal view {
        UnlessRetainer.Retainer memory r = retainer.retainerOf(id);
        assertEq(uint256(r.balance), balance, "balance");
        assertEq(uint256(r.reserved), reserved, "reserved");
        assertEq(uint256(r.totalDeposited), totalDeposited, "totalDeposited");
        assertEq(uint256(r.totalPaid), totalPaid, "totalPaid");
        assertEq(uint256(r.totalReturned), totalReturned, "totalReturned");
        assertEq(uint256(r.pendingClaims), pendingClaims, "pendingClaims");
        assertEq(retainer.availableOf(id), balance - reserved, "available");
    }

    function _assertClaim(
        uint256 id,
        uint256 claimId,
        uint256 amount,
        UnlessRetainer.ClaimStatus status,
        UnlessRetainer.PaidVia via
    ) internal view {
        UnlessRetainer.Claim memory c = retainer.claimOf(id, claimId);
        assertEq(uint256(c.amount), amount, "claim amount");
        assertEq(uint256(c.status), uint256(status), "claim status");
        assertEq(uint256(c.paidVia), uint256(via), "claim paidVia");
    }

    // ---------------------------------------------------------------- event expectations
    // All emitted by the retainer address, all four checks on.

    function _expectCreated(uint256 id, address c, address f, uint32 w, uint32 n, uint64 e) internal {
        vm.expectEmit(true, true, true, true, address(retainer));
        emit UnlessRetainer.RetainerCreated(id, c, f, w, n, e);
    }

    function _expectDeposited(uint256 id, address from, uint128 amount, uint128 newBalance) internal {
        vm.expectEmit(true, true, true, true, address(retainer));
        emit UnlessRetainer.Deposited(id, from, amount, newBalance);
    }

    function _expectFiled(uint256 id, uint256 claimId, uint128 amount, uint64 payableAt, string memory note)
        internal
    {
        vm.expectEmit(true, true, true, true, address(retainer));
        emit UnlessRetainer.ClaimFiled(id, claimId, amount, payableAt, note);
    }

    function _expectPaid(uint256 id, uint256 claimId, address to, uint128 amount, UnlessRetainer.PaidVia via)
        internal
    {
        vm.expectEmit(true, true, true, true, address(retainer));
        emit UnlessRetainer.ClaimPaid(id, claimId, to, amount, via);
    }

    function _expectObjected(uint256 id, uint256 claimId, string memory reason) internal {
        vm.expectEmit(true, true, true, true, address(retainer));
        emit UnlessRetainer.ClaimObjected(id, claimId, reason);
    }

    function _expectCancelled(uint256 id, uint256 claimId) internal {
        vm.expectEmit(true, true, true, true, address(retainer));
        emit UnlessRetainer.ClaimCancelled(id, claimId);
    }

    /// @dev Only the logs emitted by the retainer contract, in emission order.
    function _retainerLogs(Vm.Log[] memory logs) internal view returns (Vm.Log[] memory out) {
        uint256 n;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(retainer)) n++;
        }
        out = new Vm.Log[](n);
        uint256 j;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(retainer)) out[j++] = logs[i];
        }
    }
}
