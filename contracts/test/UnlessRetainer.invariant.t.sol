// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {UnlessRetainer} from "../UnlessRetainer.sol";
import {BlocklistUSDC} from "./mocks/BlocklistUSDC.sol";

/// @notice 04-TEST-PLAN section 3.1. State-changing wrapper around the real UnlessRetainer and the
/// ONLY fuzz target. Actions are bounded so that nearly every call is valid; calls that would revert
/// are skipped (not attempted). Every call to the retainer goes through a low-level call so that an
/// unexpected revert of a call the handler considered valid is recorded (`unexpectedReverts`) instead
/// of being swallowed by `fail_on_revert = false`.
contract UnlessHandler is Test {
    enum Action {
        Create,
        Deposit,
        FileClaim,
        Approve,
        Object,
        Cancel,
        PayOut,
        RequestWithdrawal,
        CancelWithdrawal,
        CompleteWithdrawal,
        WithdrawRemainder,
        ExtendEnd,
        Warp,
        ToggleBlocklist,
        WithdrawOwed
    }

    uint256 internal constant N_ACTIONS = 15;
    uint256 public constant MAX_RETAINERS = 3;
    uint256 public constant MINT = 1_000_000_000e6;

    enum Need { Any, CanDeposit, CanFile, CanRequest, HasWd, WdReady, EndedAvail }
    enum Pick { AnyPending, Objectable, Payable }

    struct Terms {
        address client;
        address freelancer;
        uint32 objectionWindow;
        uint32 noticePeriod;
    }

    struct Filing {
        bool recorded;
        uint64 filedAt;
        uint64 endTimeAtFiling;
    }

    struct Transition {
        uint256 id;
        uint256 claimId;
        UnlessRetainer.ClaimStatus from;
        UnlessRetainer.ClaimStatus to;
    }

    BlocklistUSDC public immutable token;
    UnlessRetainer public immutable retainer;

    /// @dev 0,1 = clients; 2,3 = freelancers; 4 = stranger.
    address[5] public actors;

    uint256 public retainerCount;
    mapping(uint256 => Terms) internal _terms;
    mapping(uint256 => uint64) public lastEnd;
    mapping(uint256 => uint256[]) internal _claimIds;
    mapping(uint256 => uint256) public seenClaims;
    mapping(uint256 => mapping(uint256 => UnlessRetainer.ClaimStatus)) public lastStatus;
    mapping(uint256 => mapping(uint256 => Filing)) internal _filing;
    Transition[] internal _transitions;

    // ---- ghosts
    mapping(uint256 => uint256) public ghostDeposited;
    mapping(uint256 => uint256) public ghostPaidToFreelancer;
    mapping(uint256 => uint256) public ghostReturnedToClient;
    mapping(address => uint256) public ghostReceived;
    mapping(address => uint256) public ghostOwed;
    uint256 public ghostOwedTotal;

    // ---- model-violation flags (all must stay false / zero)
    bool public endDecreased;
    bool public endMismatch;
    bool public negativeDelta;
    bool public payoutMismatch;
    uint256 public unexpectedReverts;
    uint256 public firstBadAction;
    bytes4 public firstBadSelector;

    // ---- call accounting
    uint256[15] public valid;
    uint256[15] public skipped;
    uint256[15] public reverted;

    constructor() {
        token = new BlocklistUSDC();
        retainer = new UnlessRetainer(IERC20(address(token)));
        actors[0] = makeAddr("hClient0");
        actors[1] = makeAddr("hClient1");
        actors[2] = makeAddr("hFreelancer0");
        actors[3] = makeAddr("hFreelancer1");
        actors[4] = makeAddr("hStranger");
        for (uint256 i = 0; i < 5; i++) {
            token.mint(actors[i], MINT);
        }
    }

    // ================================================================ views for the invariants

    function termsOf(uint256 id) external view returns (Terms memory) {
        return _terms[id];
    }

    function claimIdsOf(uint256 id) external view returns (uint256[] memory) {
        return _claimIds[id];
    }

    function filingOf(uint256 id, uint256 claimId) external view returns (Filing memory) {
        return _filing[id][claimId];
    }

    function transitionCount() external view returns (uint256) {
        return _transitions.length;
    }

    function transitionAt(uint256 i) external view returns (Transition memory) {
        return _transitions[i];
    }

    function callSummary()
        public
        view
        returns (uint256 totalValid, uint256 totalSkipped, uint256 totalReverted)
    {
        for (uint256 i = 0; i < N_ACTIONS; i++) {
            totalValid += valid[i];
            totalSkipped += skipped[i];
            totalReverted += reverted[i];
        }
    }

    function actionName(uint256 i) public pure returns (string memory) {
        string[15] memory names = [
            "create", "deposit", "fileClaim", "approve", "object", "cancel", "payOut",
            "requestWithdrawal", "cancelWithdrawal", "completeWithdrawal", "withdrawRemainder",
            "extendEnd", "warp", "toggleBlocklist", "withdrawOwed"
        ];
        return names[i];
    }

    /// @dev Called once after seeding the initial retainer so the seed is not counted as a fuzz call.
    function resetStats() external {
        for (uint256 i = 0; i < N_ACTIONS; i++) {
            delete valid[i];
            delete skipped[i];
            delete reverted[i];
        }
    }

    function logSummary() external view {
        for (uint256 i = 0; i < N_ACTIONS; i++) {
            console.log(actionName(i), valid[i], skipped[i]);
        }
        (uint256 v, uint256 s, uint256 r) = callSummary();
        console.log("SUMMARY valid/skipped/reverted:", v, s, r);
    }

    // ================================================================ actions

    uint256 public tickNonce;

    /// @dev Time passes between transactions: every non-warp action first advances the clock by a
    /// pseudo-random 1..30 seconds (deterministic in the call count), as a block would.
    modifier ticks() {
        tickNonce++;
        vm.warp(block.timestamp + 1 + uint256(keccak256(abi.encode(tickNonce))) % 30);
        _;
    }

    function create(uint256 sparties, uint256 sw, uint256 sn, uint256 se, uint256 sd) external ticks {
        if (retainerCount >= MAX_RETAINERS) {
            _skip(Action.Create);
            return;
        }
        Terms memory t = Terms({
            client: actors[sparties % 2],
            freelancer: actors[2 + (sparties / 2) % 2],
            objectionWindow: uint32(bound(sw, 60, 300)),
            noticePeriod: uint32(bound(sn, 60, 150))
        });
        uint64 end = uint64(block.timestamp + t.noticePeriod + bound(se, 900, 7000));
        uint128 dep = uint128(bound(sd, 0, 100e6));
        if (token.blocked(t.client)) dep = 0; // a blocked client cannot fund; create unfunded instead
        _doCreate(t, end, dep);
    }

    function _doCreate(Terms memory t, uint64 end, uint128 dep) internal {
        if (dep > 0) _approveExact(t.client, dep);
        (bool ok, bytes memory ret) = _as(
            t.client, abi.encodeCall(UnlessRetainer.createRetainer, (t.freelancer, t.objectionWindow, t.noticePeriod, end, dep))
        );
        if (!ok) {
            _bad(Action.Create, ret);
            return;
        }
        uint256 id = abi.decode(ret, (uint256));
        _terms[id] = t;
        retainerCount = id + 1;
        ghostDeposited[id] += dep;
        _sync(id);
        _ok(Action.Create);
    }

    function deposit(uint256 sid, uint256 samt) external ticks {
        (bool f, uint256 id) = _find(sid, Need.CanDeposit);
        if (!f) {
            _skip(Action.Deposit);
            return;
        }
        uint128 amt = uint128(bound(samt, 1, 50e6));
        address c = _terms[id].client;
        _approveExact(c, amt);
        (bool ok, bytes memory ret) = _as(c, abi.encodeCall(UnlessRetainer.deposit, (id, amt)));
        if (!ok) {
            _bad(Action.Deposit, ret);
            return;
        }
        ghostDeposited[id] += amt;
        _sync(id);
        _ok(Action.Deposit);
    }

    /// @dev Files 1..12 claims (`scount`) on one retainer, each for at most a quarter of what is available.
    function fileClaim(uint256 sid, uint256 samt, uint256 snote, uint256 scount) external ticks {
        (bool f, uint256 id) = _find(sid, Need.CanFile);
        if (!f) {
            _skip(Action.FileClaim);
            return;
        }
        uint256 k = 1 + scount % 12;
        for (uint256 j = 0; j < k; j++) {
            if (j > 0 && !_eligible(id, Need.CanFile)) break;
            if (!_fileOne(id, uint256(keccak256(abi.encode(samt, j))), uint256(keccak256(abi.encode(snote, j))))) return;
        }
        _ok(Action.FileClaim);
    }

    function _fileOne(uint256 id, uint256 samt, uint256 snote) internal returns (bool) {
        (, uint256 avail,) = retainer.getRetainer(id);
        uint128 amt = uint128(bound(samt, 1, (avail + 3) / 4));
        string memory note = _note(snote);
        (bool ok, bytes memory ret) =
            _as(_terms[id].freelancer, abi.encodeCall(UnlessRetainer.fileClaim, (id, amt, note)));
        if (!ok) {
            _bad(Action.FileClaim, ret);
            return false;
        }
        uint256 claimId = abi.decode(ret, (uint256));
        _claimIds[id].push(claimId);
        (UnlessRetainer.Retainer memory r,,) = retainer.getRetainer(id);
        _filing[id][claimId] = Filing({recorded: true, filedAt: uint64(block.timestamp), endTimeAtFiling: r.endTime});
        _sync(id);
        return true;
    }

    function approve(uint256 sid, uint256 sclaim) external ticks {
        (bool f, uint256 id, uint256 claimId) = _findClaim(sid, sclaim, Pick.AnyPending);
        if (!f) {
            _skip(Action.Approve);
            return;
        }
        _settleClaim(Action.Approve, id, claimId, _terms[id].client, abi.encodeCall(UnlessRetainer.approveClaim, (id, claimId)));
    }

    function payOut(uint256 sid, uint256 sclaim, uint256 scaller) external ticks {
        (bool f, uint256 id, uint256 claimId) = _findClaim(sid, sclaim, Pick.Payable);
        if (!f) {
            _skip(Action.PayOut);
            return;
        }
        // Permissionless: any actor (the stranger most of the time) may trigger it.
        address caller = scaller % 3 == 0 ? actors[(scaller / 3) % 5] : actors[4];
        _settleClaim(Action.PayOut, id, claimId, caller, abi.encodeCall(UnlessRetainer.payOutClaim, (id, claimId)));
    }

    function _settleClaim(Action a, uint256 id, uint256 claimId, address caller, bytes memory data) internal {
        uint128 amount = retainer.getClaim(id, claimId).amount;
        uint256[5] memory before = _bals();
        (bool ok, bytes memory ret) = _as(caller, data);
        if (!ok) {
            _bad(a, ret);
            return;
        }
        ghostPaidToFreelancer[id] += amount;
        _afterPayout(before, _terms[id].freelancer, amount);
        _sync(id);
        _ok(a);
    }

    function object(uint256 sid, uint256 sclaim) external ticks {
        (bool f, uint256 id, uint256 claimId) = _findClaim(sid, sclaim, Pick.Objectable);
        if (!f) {
            _skip(Action.Object);
            return;
        }
        (bool ok, bytes memory ret) =
            _as(_terms[id].client, abi.encodeCall(UnlessRetainer.objectToClaim, (id, claimId, "objection")));
        if (!ok) {
            _bad(Action.Object, ret);
            return;
        }
        _sync(id);
        _ok(Action.Object);
    }

    function cancel(uint256 sid, uint256 sclaim) external ticks {
        (bool f, uint256 id, uint256 claimId) = _findClaim(sid, sclaim, Pick.AnyPending);
        if (!f) {
            _skip(Action.Cancel);
            return;
        }
        (bool ok, bytes memory ret) =
            _as(_terms[id].freelancer, abi.encodeCall(UnlessRetainer.cancelClaim, (id, claimId)));
        if (!ok) {
            _bad(Action.Cancel, ret);
            return;
        }
        _sync(id);
        _ok(Action.Cancel);
    }

    function requestWithdrawal(uint256 sid, uint256 samt) external ticks {
        (bool f, uint256 id) = _find(sid, Need.CanRequest);
        if (!f) {
            _skip(Action.RequestWithdrawal);
            return;
        }
        (, uint256 avail,) = retainer.getRetainer(id);
        uint128 amt = uint128(bound(samt, 1, avail));
        (bool ok, bytes memory ret) =
            _as(_terms[id].client, abi.encodeCall(UnlessRetainer.requestWithdrawal, (id, amt)));
        if (!ok) {
            _bad(Action.RequestWithdrawal, ret);
            return;
        }
        _sync(id);
        _ok(Action.RequestWithdrawal);
    }

    function cancelWithdrawal(uint256 sid) external ticks {
        (bool f, uint256 id) = _find(sid, Need.HasWd);
        if (!f) {
            _skip(Action.CancelWithdrawal);
            return;
        }
        (bool ok, bytes memory ret) = _as(_terms[id].client, abi.encodeCall(UnlessRetainer.cancelWithdrawal, (id)));
        if (!ok) {
            _bad(Action.CancelWithdrawal, ret);
            return;
        }
        _sync(id);
        _ok(Action.CancelWithdrawal);
    }

    function completeWithdrawal(uint256 sid, uint256 scaller) external ticks {
        (bool f, uint256 id) = _find(sid, Need.WdReady);
        if (!f) {
            _skip(Action.CompleteWithdrawal);
            return;
        }
        (UnlessRetainer.Retainer memory r, uint256 avail,) = retainer.getRetainer(id);
        uint256 expected = r.withdrawalAmount < avail ? r.withdrawalAmount : avail;
        uint256[5] memory before = _bals();
        address caller = scaller % 3 == 0 ? actors[(scaller / 3) % 5] : actors[4];
        (bool ok, bytes memory ret) = _as(caller, abi.encodeCall(UnlessRetainer.completeWithdrawal, (id)));
        if (!ok) {
            _bad(Action.CompleteWithdrawal, ret);
            return;
        }
        ghostReturnedToClient[id] += expected;
        _afterPayout(before, r.client, expected);
        _sync(id);
        _ok(Action.CompleteWithdrawal);
    }

    function withdrawRemainder(uint256 sid) external ticks {
        (bool f, uint256 id) = _find(sid, Need.EndedAvail);
        if (!f) {
            _skip(Action.WithdrawRemainder);
            return;
        }
        (UnlessRetainer.Retainer memory r, uint256 avail,) = retainer.getRetainer(id);
        uint256[5] memory before = _bals();
        (bool ok, bytes memory ret) = _as(r.client, abi.encodeCall(UnlessRetainer.withdrawRemainder, (id)));
        if (!ok) {
            _bad(Action.WithdrawRemainder, ret);
            return;
        }
        ghostReturnedToClient[id] += avail;
        _afterPayout(before, r.client, avail);
        _sync(id);
        _ok(Action.WithdrawRemainder);
    }

    function extendEnd(uint256 sid, uint256 sdelta) external ticks {
        (bool f, uint256 id) = _find(sid, Need.Any);
        if (!f) {
            _skip(Action.ExtendEnd);
            return;
        }
        (UnlessRetainer.Retainer memory r,,) = retainer.getRetainer(id);
        uint64 newEnd = uint64(uint256(r.endTime) + bound(sdelta, 1, 12000));
        (bool ok, bytes memory ret) = _as(r.client, abi.encodeCall(UnlessRetainer.extendEndTime, (id, newEnd)));
        if (!ok) {
            _bad(Action.ExtendEnd, ret);
            return;
        }
        (UnlessRetainer.Retainer memory after_,,) = retainer.getRetainer(id);
        if (after_.endTime != newEnd) endMismatch = true;
        _sync(id);
        _ok(Action.ExtendEnd);
    }

    /// @dev Moves time forward. Modes (by `sjump % 6`): 0..2 a few windows (1..600 s); 3 exactly to the next
    /// payableAt of any pending claim; 4 exactly to the next withdrawalReadyAt; 5 to just past (0..4 s)
    /// the end of one retainer. Modes 3..5 fall back to a plain forward step when there is no such target,
    /// so the call is always valid. Landing exactly on a boundary exercises the inclusive/exclusive edges.
    function warp(uint256 sd, uint256 sjump, uint256 sid) external {
        uint256 mode = sjump % 6;
        uint256 target = 0;
        if (mode == 3) target = _nextPayableAt();
        else if (mode == 4) target = _nextReadyAt();
        else if (mode == 5 && retainerCount > 0) {
            (UnlessRetainer.Retainer memory r,,) = retainer.getRetainer(sid % retainerCount);
            if (r.endTime >= block.timestamp) target = uint256(r.endTime) + (sjump / 6) % 5;
        }
        if (target > block.timestamp) vm.warp(target);
        else vm.warp(block.timestamp + bound(sd, 1, 600));
        _ok(Action.Warp);
    }

    function _nextPayableAt() internal view returns (uint256 best) {
        for (uint256 id = 0; id < retainerCount; id++) {
            UnlessRetainer.Claim[] memory cl = retainer.getClaims(id, 0, type(uint256).max);
            for (uint256 i = 0; i < cl.length; i++) {
                if (cl[i].status != UnlessRetainer.ClaimStatus.Pending || cl[i].payableAt <= block.timestamp) continue;
                if (best == 0 || cl[i].payableAt < best) best = cl[i].payableAt;
            }
        }
    }

    function _nextReadyAt() internal view returns (uint256 best) {
        for (uint256 id = 0; id < retainerCount; id++) {
            (UnlessRetainer.Retainer memory r,,) = retainer.getRetainer(id);
            if (r.withdrawalReadyAt <= block.timestamp) continue;
            if (best == 0 || r.withdrawalReadyAt < best) best = r.withdrawalReadyAt;
        }
    }

    /// @dev Flips the blocklist flag of one of the five actors. The retainer contract is never blocked.
    function toggleBlocklist(uint256 sa) external ticks {
        uint256 i = sa % 5;
        if (i == 4 && (sa / 5) % 2 == 0) i = 2 + (sa / 10) % 2; // the stranger is blocked less often than the parties
        address a = actors[i];
        token.setBlocked(a, !token.blocked(a));
        _ok(Action.ToggleBlocklist);
    }

    function withdrawOwed(uint256 sa) external ticks {
        address who;
        for (uint256 k = 0; k < 5; k++) {
            address a = actors[(sa % 5 + k) % 5];
            if (retainer.owed(a) > 0 && !token.blocked(a)) {
                who = a;
                break;
            }
        }
        if (who == address(0)) {
            _skip(Action.WithdrawOwed);
            return;
        }
        uint256 amount = retainer.owed(who);
        uint256[5] memory before = _bals();
        (bool ok, bytes memory ret) = _as(who, abi.encodeCall(UnlessRetainer.withdrawOwed, ()));
        if (!ok) {
            _bad(Action.WithdrawOwed, ret);
            return;
        }
        _recordDeltas(before);
        if (token.balanceOf(who) - before[_idx(who)] != amount) payoutMismatch = true;
        ghostOwed[who] -= amount;
        ghostOwedTotal -= amount;
        _ok(Action.WithdrawOwed);
    }

    // ================================================================ internals

    function _ok(Action a) internal {
        valid[uint256(a)]++;
    }

    function _skip(Action a) internal {
        skipped[uint256(a)]++;
    }

    function _bad(Action a, bytes memory ret) internal {
        reverted[uint256(a)]++;
        if (unexpectedReverts++ == 0) {
            firstBadAction = uint256(a);
            firstBadSelector = ret.length >= 4 ? bytes4(ret) : bytes4(0);
        }
    }

    function _as(address who, bytes memory data) internal returns (bool ok, bytes memory ret) {
        vm.prank(who);
        (ok, ret) = address(retainer).call(data);
    }

    function _approveExact(address who, uint256 amount) internal {
        vm.prank(who);
        token.approve(address(retainer), amount);
    }

    function _note(uint256 seed) internal pure returns (string memory) {
        uint256 len = seed % 4 == 0 ? seed % 281 : 4;
        bytes memory b = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            b[i] = "n";
        }
        return string(b);
    }

    function _idx(address a) internal view returns (uint256) {
        for (uint256 i = 0; i < 5; i++) {
            if (actors[i] == a) return i;
        }
        revert("not an actor");
    }

    function _bals() internal view returns (uint256[5] memory b) {
        for (uint256 i = 0; i < 5; i++) {
            b[i] = token.balanceOf(actors[i]);
        }
    }

    /// @dev Records real balance deltas of every actor; no actor may lose tokens in a payout action.
    function _recordDeltas(uint256[5] memory before) internal {
        for (uint256 i = 0; i < 5; i++) {
            uint256 nowBal = token.balanceOf(actors[i]);
            if (nowBal > before[i]) ghostReceived[actors[i]] += nowBal - before[i];
            else if (nowBal < before[i]) negativeDelta = true;
        }
    }

    /// @dev Independent model of `_send`: a blocked recipient receives nothing and is credited in
    /// `owed`; any other recipient receives the full amount.
    function _afterPayout(uint256[5] memory before, address to, uint256 expected) internal {
        bool toBlocked = token.blocked(to);
        _recordDeltas(before);
        uint256 got = token.balanceOf(to) - before[_idx(to)];
        if (expected == 0) {
            if (got != 0) payoutMismatch = true;
        } else if (toBlocked) {
            if (got != 0) payoutMismatch = true;
            ghostOwed[to] += expected;
            ghostOwedTotal += expected;
        } else if (got != expected) {
            payoutMismatch = true;
        }
    }

    function _eligible(uint256 id, Need need) internal view returns (bool) {
        (UnlessRetainer.Retainer memory r, uint256 avail, bool ended) = retainer.getRetainer(id);
        if (need == Need.Any) return true;
        if (need == Need.CanDeposit) return !ended && !token.blocked(r.client);
        if (need == Need.CanFile) return !ended && r.pendingClaims < 20 && avail > 0;
        if (need == Need.CanRequest) return !ended && r.withdrawalReadyAt == 0 && avail > 0;
        if (need == Need.HasWd) return r.withdrawalReadyAt != 0;
        if (need == Need.WdReady) return r.withdrawalReadyAt != 0 && block.timestamp >= r.withdrawalReadyAt;
        return ended && avail > 0; // EndedAvail
    }

    function _find(uint256 sid, Need need) internal view returns (bool, uint256) {
        uint256 n = retainerCount;
        for (uint256 k = 0; k < n; k++) {
            uint256 id = ((sid % n) + k) % n;
            if (_eligible(id, need)) return (true, id);
        }
        return (false, 0);
    }

    function _collect(uint256 id, Pick mode) internal view returns (uint256[] memory list) {
        UnlessRetainer.Claim[] memory cl = retainer.getClaims(id, 0, type(uint256).max);
        list = new uint256[](cl.length);
        uint256 m;
        for (uint256 i = 0; i < cl.length; i++) {
            if (cl[i].status != UnlessRetainer.ClaimStatus.Pending) continue;
            if (mode == Pick.Objectable && block.timestamp >= cl[i].payableAt) continue;
            if (mode == Pick.Payable && block.timestamp < cl[i].payableAt) continue;
            list[m++] = i;
        }
        assembly ("memory-safe") {
            mstore(list, m)
        }
    }

    function _findClaim(uint256 sid, uint256 sclaim, Pick mode) internal view returns (bool, uint256, uint256) {
        uint256 n = retainerCount;
        for (uint256 k = 0; k < n; k++) {
            uint256 id = ((sid % n) + k) % n;
            uint256[] memory list = _collect(id, mode);
            if (list.length > 0) return (true, id, list[sclaim % list.length]);
        }
        return (false, 0, 0);
    }

    /// @dev Reads every claim of `id` through the views, logs each status transition and records the
    /// last seen endTime.
    function _sync(uint256 id) internal {
        (UnlessRetainer.Retainer memory r,,) = retainer.getRetainer(id);
        if (r.endTime < lastEnd[id]) endDecreased = true;
        lastEnd[id] = r.endTime;
        UnlessRetainer.Claim[] memory cl = retainer.getClaims(id, 0, type(uint256).max);
        for (uint256 i = 0; i < cl.length; i++) {
            UnlessRetainer.ClaimStatus prev =
                i < seenClaims[id] ? lastStatus[id][i] : UnlessRetainer.ClaimStatus.None;
            if (prev != cl[i].status) {
                _transitions.push(Transition({id: id, claimId: i, from: prev, to: cl[i].status}));
                lastStatus[id][i] = cl[i].status;
            }
        }
        seenClaims[id] = cl.length;
    }
}

/// @notice 04-TEST-PLAN section 3.2. The handler is the only target; every check reads state through
/// the contract's real views (getRetainer, getClaims, owed, totalOwed, nextRetainerId).
contract UnlessRetainerInvariantTest is StdInvariant, Test {
    UnlessHandler internal handler;
    UnlessRetainer internal retainer;
    BlocklistUSDC internal token;

    function setUp() public {
        handler = new UnlessHandler();
        retainer = handler.retainer();
        token = handler.token();

        // One funded retainer exists from the start so early calls are not starved; not counted.
        handler.create(0, 240, 240, 9000, 60e6);
        handler.resetStats();

        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](15);
        selectors[0] = UnlessHandler.create.selector;
        selectors[1] = UnlessHandler.deposit.selector;
        selectors[2] = UnlessHandler.fileClaim.selector;
        selectors[3] = UnlessHandler.approve.selector;
        selectors[4] = UnlessHandler.object.selector;
        selectors[5] = UnlessHandler.cancel.selector;
        selectors[6] = UnlessHandler.payOut.selector;
        selectors[7] = UnlessHandler.requestWithdrawal.selector;
        selectors[8] = UnlessHandler.cancelWithdrawal.selector;
        selectors[9] = UnlessHandler.completeWithdrawal.selector;
        selectors[10] = UnlessHandler.withdrawRemainder.selector;
        selectors[11] = UnlessHandler.extendEnd.selector;
        selectors[12] = UnlessHandler.warp.selector;
        selectors[13] = UnlessHandler.toggleBlocklist.selector;
        selectors[14] = UnlessHandler.withdrawOwed.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // ================================================================ helpers

    function _n() internal view returns (uint256) {
        return retainer.nextRetainerId();
    }

    function _r(uint256 id) internal view returns (UnlessRetainer.Retainer memory r) {
        (r,,) = retainer.getRetainer(id);
    }

    function _claims(uint256 id) internal view returns (UnlessRetainer.Claim[] memory) {
        return retainer.getClaims(id, 0, type(uint256).max);
    }

    // ================================================================ invariants (04-TEST-PLAN 3.2)

    function invariant_I1_reservedLeBalance() public view {
        for (uint256 id = 0; id < _n(); id++) {
            UnlessRetainer.Retainer memory r = _r(id);
            assertLe(uint256(r.reserved), uint256(r.balance), "I-1 reserved <= balance");
        }
    }

    function invariant_I2_reservedMatchesPending() public view {
        for (uint256 id = 0; id < _n(); id++) {
            UnlessRetainer.Claim[] memory cl = _claims(id);
            uint256 sum;
            uint256 count;
            for (uint256 i = 0; i < cl.length; i++) {
                if (cl[i].status == UnlessRetainer.ClaimStatus.Pending) {
                    sum += cl[i].amount;
                    count++;
                }
            }
            UnlessRetainer.Retainer memory r = _r(id);
            assertEq(uint256(r.reserved), sum, "I-2 reserved == sum(pending)");
            assertEq(uint256(r.pendingClaims), count, "I-2 pendingClaims == count(pending)");
            assertEq(uint256(r.claimCount), cl.length, "claimCount == claims listed");
        }
    }

    function invariant_I3_solvency() public view {
        uint256 sum;
        for (uint256 id = 0; id < _n(); id++) {
            sum += _r(id).balance;
        }
        assertGe(token.balanceOf(address(retainer)), sum + retainer.totalOwed(), "I-3 solvency");
    }

    /// @dev Nobody ever sends tokens to the contract directly, so solvency holds with equality.
    function invariant_I3b_solvencyIsExact() public view {
        uint256 sum;
        for (uint256 id = 0; id < _n(); id++) {
            sum += _r(id).balance;
        }
        assertEq(token.balanceOf(address(retainer)), sum + retainer.totalOwed(), "tokens == balances + owed");
    }

    function invariant_I4_conservation() public view {
        for (uint256 id = 0; id < _n(); id++) {
            UnlessRetainer.Retainer memory r = _r(id);
            assertEq(
                uint256(r.totalDeposited),
                uint256(r.balance) + uint256(r.totalPaid) + uint256(r.totalReturned),
                "I-4 deposited == balance + paid + returned"
            );
        }
    }

    function invariant_I5_destinationSafety() public view {
        address stranger = handler.actors(4);
        assertEq(handler.ghostReceived(stranger), 0, "I-5 stranger received nothing");
        assertEq(retainer.owed(stranger), 0, "I-5 stranger is owed nothing");
        assertEq(token.balanceOf(stranger), handler.MINT(), "I-5 stranger token balance untouched");
        assertFalse(handler.negativeDelta(), "no actor loses tokens in a payout action");

        for (uint256 i = 0; i < 5; i++) {
            address a = handler.actors(i);
            uint256 entitled; // what the retainers' accounting says went to `a`
            uint256 deposited; // what `a` put in as a client
            for (uint256 id = 0; id < _n(); id++) {
                UnlessRetainer.Retainer memory r = _r(id);
                if (r.freelancer == a) entitled += r.totalPaid;
                if (r.client == a) {
                    entitled += r.totalReturned;
                    deposited += r.totalDeposited;
                }
            }
            // Every gain is explained by a retainer role or by pulling own credit; nothing else.
            assertEq(handler.ghostReceived(a) + retainer.owed(a), entitled, "I-5 received + owed == entitled");
            // Full token flow of the address.
            assertEq(token.balanceOf(a), handler.MINT() - deposited + handler.ghostReceived(a), "token flow");
        }
    }

    function invariant_I6_terminality() public view {
        UnlessHandler h = handler;
        for (uint256 i = 0; i < h.transitionCount(); i++) {
            UnlessHandler.Transition memory t = h.transitionAt(i);
            assertTrue(
                t.from != UnlessRetainer.ClaimStatus.Paid && t.from != UnlessRetainer.ClaimStatus.Objected
                    && t.from != UnlessRetainer.ClaimStatus.Cancelled,
                "I-6 transition out of a terminal state"
            );
            // Only legal edges: None -> Pending, Pending -> {Paid, Objected, Cancelled}.
            if (t.from == UnlessRetainer.ClaimStatus.None) {
                assertEq(uint256(t.to), uint256(UnlessRetainer.ClaimStatus.Pending), "None -> Pending only");
            } else {
                assertTrue(t.to != UnlessRetainer.ClaimStatus.None && t.to != UnlessRetainer.ClaimStatus.Pending);
            }
        }
        // Terminal statuses recorded by the handler are still the live statuses.
        for (uint256 id = 0; id < _n(); id++) {
            UnlessRetainer.Claim[] memory cl = _claims(id);
            for (uint256 c = 0; c < cl.length; c++) {
                UnlessRetainer.ClaimStatus last = h.lastStatus(id, c);
                if (last == UnlessRetainer.ClaimStatus.Paid || last == UnlessRetainer.ClaimStatus.Objected
                        || last == UnlessRetainer.ClaimStatus.Cancelled) {
                    assertEq(uint256(cl[c].status), uint256(last), "terminal status unchanged");
                }
            }
        }
    }

    function invariant_I7_timeOrdering() public view {
        for (uint256 id = 0; id < _n(); id++) {
            UnlessHandler.Terms memory t = handler.termsOf(id);
            uint64 end = _r(id).endTime;
            UnlessRetainer.Claim[] memory cl = _claims(id);
            for (uint256 c = 0; c < cl.length; c++) {
                UnlessHandler.Filing memory f = handler.filingOf(id, c);
                assertTrue(f.recorded, "filing recorded");
                assertEq(uint256(cl[c].payableAt), uint256(cl[c].filedAt) + t.objectionWindow, "I-7 payableAt");
                assertEq(uint256(cl[c].filedAt), uint256(f.filedAt), "filedAt == filing block time");
                assertLt(uint256(f.filedAt), uint256(f.endTimeAtFiling), "I-7 filedAt < endTime at filing");
                assertLe(uint256(f.endTimeAtFiling), uint256(end), "endTime only grows");
                assertLt(uint256(cl[c].filedAt), uint256(end), "filedAt < current endTime");
            }
        }
    }

    function invariant_I8_termsImmutable() public view {
        assertFalse(handler.endDecreased(), "I-8 endTime never decreased");
        assertFalse(handler.endMismatch(), "extendEndTime set the requested endTime");
        for (uint256 id = 0; id < _n(); id++) {
            UnlessHandler.Terms memory t = handler.termsOf(id);
            UnlessRetainer.Retainer memory r = _r(id);
            assertEq(r.client, t.client, "I-8 client");
            assertEq(r.freelancer, t.freelancer, "I-8 freelancer");
            assertEq(uint256(r.objectionWindow), uint256(t.objectionWindow), "I-8 objectionWindow");
            assertEq(uint256(r.noticePeriod), uint256(t.noticePeriod), "I-8 noticePeriod");
            assertGe(uint256(r.endTime), uint256(handler.lastEnd(id)), "I-8 endTime non-decreasing");
        }
    }

    function invariant_ghostsMatchContract() public view {
        assertEq(handler.retainerCount(), _n(), "handler tracks every retainer");
        for (uint256 id = 0; id < _n(); id++) {
            UnlessRetainer.Retainer memory r = _r(id);
            assertEq(handler.ghostDeposited(id), uint256(r.totalDeposited), "ghostDeposited");
            assertEq(handler.ghostPaidToFreelancer(id), uint256(r.totalPaid), "ghostPaidToFreelancer");
            assertEq(handler.ghostReturnedToClient(id), uint256(r.totalReturned), "ghostReturnedToClient");
            assertEq(handler.claimIdsOf(id).length, uint256(r.claimCount), "claim id list");
        }
        uint256 owedSum;
        for (uint256 i = 0; i < 5; i++) {
            address a = handler.actors(i);
            assertEq(handler.ghostOwed(a), retainer.owed(a), "handler-tracked owed == owed");
            owedSum += retainer.owed(a);
        }
        assertEq(handler.ghostOwedTotal(), retainer.totalOwed(), "handler-tracked owed == totalOwed");
        assertEq(owedSum, retainer.totalOwed(), "totalOwed == sum of per-actor owed");
        assertFalse(handler.payoutMismatch(), "payout/deferral matched the independent model");
    }

    /// @dev A call the handler considered valid must never revert in the contract.
    function invariant_validCallsNeverRevert() public view {
        assertEq(handler.unexpectedReverts(), 0, "a valid handler call reverted in the contract");
    }

    /// @dev Call accounting is consistent and the handler's valid share is meaningful.
    function invariant_callSummary() public view {
        (uint256 v, uint256 s, uint256 r) = handler.callSummary();
        assertEq(r, handler.unexpectedReverts(), "reverted counters agree");
        assertGe(v + s + r, v, "totals");
    }

    /// @dev Logs the per-action summary of the last run and a cumulative valid/skipped tally over all
    /// runs so far (kept in process env vars, because EVM state is reverted between runs; when several
    /// invariants run in parallel the tally is approximate).
    function afterInvariant() public {
        handler.logSummary();
        (uint256 v, uint256 s, uint256 r) = handler.callSummary();
        uint256 cv = vm.envOr("UNLESS_INV_VALID", uint256(0)) + v;
        uint256 ct = vm.envOr("UNLESS_INV_TOTAL", uint256(0)) + v + s + r;
        vm.setEnv("UNLESS_INV_VALID", vm.toString(cv));
        vm.setEnv("UNLESS_INV_TOTAL", vm.toString(ct));
        for (uint256 i = 0; i < 15; i++) {
            string memory kv = string.concat("UNLESS_INV_V", vm.toString(i));
            string memory ks = string.concat("UNLESS_INV_S", vm.toString(i));
            uint256 av = vm.envOr(kv, uint256(0)) + handler.valid(i);
            uint256 as_ = vm.envOr(ks, uint256(0)) + handler.skipped(i);
            vm.setEnv(kv, vm.toString(av));
            vm.setEnv(ks, vm.toString(as_));
            console.log(string.concat("CUMULATIVE ", handler.actionName(i), " valid/skipped:"), av, as_);
        }
        console.log("CUMULATIVE valid / total handler calls:", cv, ct);
    }

    // ================================================================ sanity: every action can succeed

    function test_handler_everyActionSucceeds() public {
        UnlessHandler h = handler;

        // setUp already seeded retainer 0 (not touched here); the walk-through below drives retainer 1.
        h.create(0, 240, 240, 3000, 100e6); // retainer 1: client0 -> freelancer0, window 240, notice 240
        h.create(1, 100, 100, 1500, 0); // retainer 2, unfunded
        h.deposit(1, 5e6);
        h.fileClaim(1, 10e6, 4, 0); // claim 0
        h.fileClaim(1, 10e6, 4, 0); // claim 1
        h.fileClaim(1, 10e6, 4, 0); // claim 2
        h.fileClaim(1, 10e6, 4, 0); // claim 3
        h.object(1, 0); // claim 0 objected
        h.approve(1, 0); // claim 1 approved now
        h.cancel(1, 0); // claim 2 cancelled
        h.warp(300, 1, 1); // 300s >= window
        h.payOut(1, 0, 1); // claim 3 paid out
        h.requestWithdrawal(1, 20e6);
        h.cancelWithdrawal(1);
        h.requestWithdrawal(1, 20e6);
        h.warp(300, 1, 1);
        h.completeWithdrawal(1, 1);
        h.extendEnd(1, 1000);

        // credit fallback: block freelancer0, pay out, unblock, pull.
        h.toggleBlocklist(2);
        h.fileClaim(1, 1e6, 4, 0);
        h.warp(300, 1, 1);
        h.payOut(1, 0, 1);
        assertEq(retainer.owed(h.actors(2)), retainer.getClaim(1, 4).amount, "payout deferred to owed");
        assertGt(retainer.owed(h.actors(2)), 0, "something was deferred");
        h.toggleBlocklist(2);
        h.withdrawOwed(2);
        assertEq(retainer.owed(h.actors(2)), 0, "owed pulled");

        // jump past the end and take the remainder back.
        h.warp(1, 5, 1); // mode 5: exactly to the retainer end
        h.withdrawRemainder(1);

        for (uint256 i = 0; i < 15; i++) {
            assertGe(h.valid(i), 1, h.actionName(i));
            assertEq(h.skipped(i), 0, h.actionName(i));
        }
        assertEq(h.unexpectedReverts(), 0);

        invariant_I1_reservedLeBalance();
        invariant_I2_reservedMatchesPending();
        invariant_I3_solvency();
        invariant_I3b_solvencyIsExact();
        invariant_I4_conservation();
        invariant_I5_destinationSafety();
        invariant_I6_terminality();
        invariant_I7_timeOrdering();
        invariant_I8_termsImmutable();
        invariant_ghostsMatchContract();
        invariant_validCallsNeverRevert();
        // 5 claims filed (None -> Pending) and 5 settled (object, approve, cancel, 2 pay-outs).
        assertEq(h.transitionCount(), 10, "transition log length");
    }
}
