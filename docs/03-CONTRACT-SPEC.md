# 03 — Contract Specification: `UnlessRetainer`

**Status: normative.** Code must match this document. Where this document says MUST, deviation is a bug. If something here is wrong, fix the document first, then the code, in the same change.

---

## 1. Summary

- Contract name: `UnlessRetainer`
- Solidity: `^0.8.24` (pin the exact version Studio uses; record it in `deployments/*.json`)
- License: MIT
- Dependencies: OpenZeppelin `ReentrancyGuard`, `SafeERC20`, `IERC20` (pin the version Studio installs)
- Inheritance: `ReentrancyGuard` only
- Privileged roles: **none**
- Upgradeability: **none**
- Payable functions: **none**
- `receive()` / `fallback()`: **none**

## 2. Constructor and immutables

```solidity
IERC20 public immutable USDC;

constructor(IERC20 usdc_) {
    if (address(usdc_) == address(0)) revert InvalidToken();
    USDC = usdc_;
}
```

- On Arc testnet and mainnet the argument is `0x3600000000000000000000000000000000000000` (identical on both networks, which is what makes the bytecode-match proof possible — see 07-DEPLOYMENT-RUNBOOK §6).
- In local tests the argument is a `MockUSDC` address.
- The contract MUST NOT call `decimals()`; amounts are always 6-decimal base units.

## 3. Constants

| Name | Value | Rationale |
|---|---|---|
| `MIN_WINDOW` | `60` (seconds) | Allows a credible 5-minute mainnet demo while preventing zero-length windows |
| `MAX_WINDOW` | `30 days` | Sanity bound |
| `MIN_NOTICE` | `60` | Same reasoning as `MIN_WINDOW` |
| `MAX_NOTICE` | `60 days` | Sanity bound |
| `MAX_PENDING_CLAIMS` | `20` | Bounds UI and griefing; not a loop bound (there are no loops) |
| `MAX_TEXT_BYTES` | `280` | Bounds note and reason sizes in events |

All are `uint256 public constant` (or `uint32`/`uint64` where packing helps; types must make comparisons safe).

## 4. Types and storage

### 4.1 Enums

```solidity
enum ClaimStatus { None, Pending, Paid, Objected, Cancelled }
enum PaidVia     { None, ApprovedNow, PaidOut }
```
`None` is the zero value and means "does not exist". It MUST never be written explicitly.

### 4.2 Structs

```solidity
struct Retainer {
    // slot 0
    address client;
    uint32  objectionWindow;   // seconds
    uint32  noticePeriod;      // seconds
    // slot 1
    address freelancer;
    uint64  endTime;           // unix seconds; claims allowed while block.timestamp < endTime
    // slot 2
    uint128 balance;           // USDC (6dp) held for this retainer
    uint128 reserved;          // sum of Pending claim amounts
    // slot 3
    uint128 withdrawalAmount;  // 0 = no pending withdrawal
    uint64  withdrawalReadyAt; // 0 = no pending withdrawal
    uint32  claimCount;        // total claims ever filed; next claimId = claimCount
    uint16  pendingClaims;     // number of Pending claims
    // slot 4
    uint128 totalDeposited;
    uint128 totalPaid;         // to freelancer
    // slot 5
    uint128 totalReturned;     // to client
    uint64  createdAt;
}

struct Claim {
    uint128     amount;
    uint64      filedAt;
    uint64      payableAt;     // filedAt + objectionWindow
    ClaimStatus status;
    PaidVia     paidVia;
    bytes32     noteHash;      // keccak256(bytes(note)); full note is in the ClaimFiled event
}
```

Packing is a recommendation, not a requirement. Correctness and clarity win over gas.

### 4.3 State variables

```solidity
uint256 public nextRetainerId;                                   // starts at 0
mapping(uint256 => Retainer) internal _retainers;
mapping(uint256 => mapping(uint256 => Claim)) internal _claims;  // retainerId => claimId => Claim
mapping(address => uint256[]) internal _clientRetainers;
mapping(address => uint256[]) internal _freelancerRetainers;
mapping(address => uint256) public owed;                         // credit-fallback ledger
uint256 public totalOwed;
```

A retainer exists iff `_retainers[id].client != address(0)`.

## 5. Derived values

```
available(id)   = balance − reserved
isEnded(id)     = block.timestamp ≥ endTime
claimIsPayable  = status == Pending && block.timestamp ≥ payableAt
canObject       = status == Pending && block.timestamp < payableAt
```

The boundary is **exclusive for objection, inclusive for execution**. At `t == payableAt` the claim is payable and can no longer be objected to. The two conditions are disjoint and exhaustive for a pending claim.

## 6. External functions

Notation: **Who** = authorized caller; **Pre** = checks in order (first failing check determines the error); **Effects** = state changes in order; **Interactions** = external calls after effects; **Emits** = events.

All state-changing functions are `external nonReentrant`.

### 6.1 `createRetainer`

```solidity
function createRetainer(
    address freelancer,
    uint32  objectionWindow,
    uint32  noticePeriod,
    uint64  endTime,
    uint128 initialDeposit
) external returns (uint256 id);
```
- **Who:** anyone (caller becomes client)
- **Pre:**
  1. `freelancer != address(0)` else `InvalidFreelancer`
  2. `freelancer != msg.sender` else `InvalidFreelancer`
  3. `MIN_WINDOW ≤ objectionWindow ≤ MAX_WINDOW` else `WindowOutOfRange`
  4. `MIN_NOTICE ≤ noticePeriod ≤ MAX_NOTICE` else `NoticeOutOfRange`
  5. `endTime > block.timestamp + noticePeriod` else `EndTimeTooSoon`
- **Effects:** `id = nextRetainerId++`; write retainer with `client = msg.sender`, `createdAt = now`; push `id` to `_clientRetainers[msg.sender]` and `_freelancerRetainers[freelancer]`.
- **Interactions:** if `initialDeposit > 0`, perform the deposit routine (§6.3) for `initialDeposit`.
- **Emits:** `RetainerCreated(id, client, freelancer, objectionWindow, noticePeriod, endTime)`, then `Deposited(...)` if a deposit occurred.

> Note: the deposit routine mutates `balance` after a token interaction. That is acceptable because `transferFrom` into this contract is the interaction being accounted for and USDC has no callbacks; see §6.3 for the exact sequence.

### 6.2 `deposit`

```solidity
function deposit(uint256 id, uint128 amount) external;
```
- **Who:** client only (`NotClient`)
- **Pre:** retainer exists (`RetainerNotFound`); `amount > 0` (`ZeroAmount`); `!isEnded` (`RetainerEnded`)
- **Effects / interactions:** deposit routine.
- **Emits:** `Deposited(id, msg.sender, amount, newBalance)`

### 6.3 Deposit routine (internal)

```
before = USDC.balanceOf(address(this))
USDC.safeTransferFrom(msg.sender, address(this), amount)
received = USDC.balanceOf(address(this)) − before
if received != amount → revert DepositMismatch
r.balance += amount
r.totalDeposited += amount
```
The balance-delta check is defensive (USDC on Arc has no transfer fee); it guarantees the ledger never exceeds actual holdings.

### 6.4 Outbound payment routine `_send(address to, uint256 amount)` (internal)

```
(bool ok, bytes memory ret) = address(USDC).call(
    abi.encodeCall(IERC20.transfer, (to, amount))
);
bool success = ok && (ret.length == 0 || (ret.length == 32 && abi.decode(ret, (uint256)) == 1));
if (!success) {
    owed[to] += amount;
    totalOwed += amount;
    emit PayoutDeferred(to, amount);
}
```
- MUST be called only after all state effects for the action are written.
- MUST NOT revert on recipient failure. This is what prevents a blocklisted address from freezing a retainer (ADR-006).
- Guard: if `ret.length` is nonzero but not 32 bytes, treat as failure (do not let `abi.decode` revert).
- The return word is decoded as `uint256` and compared to `1` (the SafeERC20 convention), not decoded as `bool`: a `bool` decode reverts on a 32-byte value other than 0 or 1, which would break the MUST-NOT-revert rule above. Ruled 2026-10-25; see ADR-012.
- No code-length check on `USDC` (see ADR-013).

### 6.5 `fileClaim`

```solidity
function fileClaim(uint256 id, uint128 amount, string calldata note)
    external returns (uint256 claimId);
```
- **Who:** freelancer only (`NotFreelancer`)
- **Pre (in order):** exists; `!isEnded` (`RetainerEnded`); `amount > 0` (`ZeroAmount`); `bytes(note).length ≤ MAX_TEXT_BYTES` (`TextTooLong`); `pendingClaims < MAX_PENDING_CLAIMS` (`TooManyPendingClaims`); `amount ≤ available` (`InsufficientAvailable`)
- **Effects:** `claimId = claimCount++`; write claim `{amount, filedAt: now, payableAt: now + objectionWindow, status: Pending, paidVia: None, noteHash: keccak256(bytes(note))}`; `reserved += amount`; `pendingClaims++`.
- **Emits:** `ClaimFiled(id, claimId, amount, payableAt, note)`

Filing during a pending withdrawal is allowed. That is the purpose of the notice period.

### 6.6 `approveClaim`

```solidity
function approveClaim(uint256 id, uint256 claimId) external;
```
- **Who:** client only
- **Pre:** retainer exists (`RetainerNotFound`); claim exists, `claimId < claimCount` (`ClaimNotFound`); claim `status == Pending` (`ClaimNotPending`)
- **Effects:** payout routine with `PaidVia.ApprovedNow`
- Allowed at any time while pending, including after `payableAt`.

### 6.7 `objectToClaim`

```solidity
function objectToClaim(uint256 id, uint256 claimId, string calldata reason) external;
```
- **Who:** client only
- **Pre:** retainer exists (`RetainerNotFound`); claim exists (`ClaimNotFound`); `Pending` (`ClaimNotPending`); `block.timestamp < payableAt` (`ObjectionWindowClosed`); `bytes(reason).length ≤ MAX_TEXT_BYTES` (`TextTooLong`)
- **Effects:** `status = Objected`; `reserved −= amount`; `pendingClaims−−`
- **Emits:** `ClaimObjected(id, claimId, reason)`
- No USDC moves.

### 6.8 `cancelClaim`

```solidity
function cancelClaim(uint256 id, uint256 claimId) external;
```
- **Who:** freelancer only
- **Pre:** retainer exists (`RetainerNotFound`); claim exists (`ClaimNotFound`); `Pending` (`ClaimNotPending`)
- **Effects:** `status = Cancelled`; `reserved −= amount`; `pendingClaims−−`
- **Emits:** `ClaimCancelled(id, claimId)`

### 6.9 `payOutClaim`

```solidity
function payOutClaim(uint256 id, uint256 claimId) external;
```
- **Who:** anyone
- **Pre:** retainer exists (`RetainerNotFound`); claim exists (`ClaimNotFound`); `Pending` (`ClaimNotPending`); `block.timestamp ≥ payableAt` (`ObjectionWindowOpen`)
- **Effects:** payout routine with `PaidVia.PaidOut`

### 6.10 Payout routine (internal)

```
c.status = Paid
c.paidVia = via
r.reserved −= c.amount
r.balance  −= c.amount
r.totalPaid += c.amount
r.pendingClaims −= 1
emit ClaimPaid(id, claimId, r.freelancer, c.amount, via)
_send(r.freelancer, c.amount)
```
Event before `_send` is deliberate: if `_send` defers, both `ClaimPaid` and `PayoutDeferred` appear, and the UI shows "paid, awaiting recipient withdrawal".

### 6.11 `requestWithdrawal`

```solidity
function requestWithdrawal(uint256 id, uint128 amount) external;
```
- **Who:** client only
- **Pre:** exists; `!isEnded` (`RetainerEnded` — after end, use `withdrawRemainder`); `withdrawalReadyAt == 0` (`WithdrawalAlreadyPending`); `amount > 0` (`ZeroAmount`); `amount ≤ available` (`InsufficientAvailable`)
- **Effects:** `withdrawalAmount = amount`; `withdrawalReadyAt = now + noticePeriod`
- **Emits:** `WithdrawalRequested(id, amount, readyAt)`
- **Does not reserve.** Claims filed during notice may consume the same money; that is intended (T2).

### 6.12 `cancelWithdrawal`

- **Who:** client only. **Pre:** exists; pending (`NoWithdrawalPending`).
- **Effects:** clear both withdrawal fields. **Emits:** `WithdrawalCancelled(id)`

### 6.13 `completeWithdrawal`

```solidity
function completeWithdrawal(uint256 id) external;
```
- **Who:** anyone (money only ever goes to client)
- **Pre:** exists; pending (`NoWithdrawalPending`); `block.timestamp ≥ withdrawalReadyAt` (`NoticeNotElapsed`)
- **Effects:**
  ```
  requested = withdrawalAmount
  payout = min(requested, available)
  clear withdrawal fields
  balance −= payout
  totalReturned += payout
  ```
- **Emits:** `WithdrawalCompleted(id, requested, payout)`
- **Interactions:** if `payout > 0`, `_send(client, payout)`.
- A completion with `payout == 0` is valid and clears the request.
- Completion is allowed even after `endTime` (a request made before end can complete after end).

### 6.14 `withdrawRemainder`

```solidity
function withdrawRemainder(uint256 id) external;
```
- **Who:** client only
- **Pre:** exists; `isEnded` (`RetainerNotEnded`); `available > 0` (`ZeroAmount`)
- **Effects:** clear any pending withdrawal; `payout = available`; `balance −= payout`; `totalReturned += payout`
- **Emits:** `RemainderWithdrawn(id, payout)` (and `WithdrawalCancelled` first if one was pending)
- **Interactions:** `_send(client, payout)`
- Pending claims remain reserved and resolvable after end.

### 6.15 `extendEndTime`

- **Who:** client only. **Pre:** exists; `newEndTime > endTime` (`EndTimeNotLater`).
- Allowed even after end (re-opens the retainer for claims). **Emits:** `EndTimeExtended(id, oldEnd, newEnd)`

### 6.16 `withdrawOwed`

```solidity
function withdrawOwed() external;
```
- **Who:** anyone with `owed[msg.sender] > 0` (`NothingOwed`)
- **Effects:** `amount = owed[msg.sender]`; `owed[msg.sender] = 0`; `totalOwed −= amount`
- **Interactions:** `USDC.safeTransfer(msg.sender, amount)` — **this one reverts on failure** (the caller is the recipient; reverting restores their credit).
- **Emits:** `OwedWithdrawn(msg.sender, amount)`

## 7. View functions

```solidity
function getRetainer(uint256 id) external view returns (Retainer memory r, uint256 available, bool ended);
function getClaim(uint256 id, uint256 claimId) external view returns (Claim memory);
function getClaims(uint256 id, uint256 offset, uint256 limit) external view returns (Claim[] memory);
function retainersOfClient(address a) external view returns (uint256[] memory);
function retainersOfFreelancer(address a) external view returns (uint256[] memory);
```
- `getRetainer` and `getClaim` revert `RetainerNotFound` for unknown ids. `getClaim` reverts `ClaimNotFound` for `claimId ≥ claimCount`.
- `getClaims` clamps `limit` to available claims; returns an empty array when `offset ≥ claimCount`.
- View functions may loop (bounded by `limit`); they are never called by state-changing code.

## 8. Invariants

These MUST hold after every transaction. The invariant test suite (04-TEST-PLAN §3) encodes each one.

- **I-1 Reservation bound:** for every retainer, `reserved ≤ balance`.
- **I-2 Reservation exactness:** for every retainer, `reserved == Σ amount of its Pending claims`, and `pendingClaims == count of its Pending claims`.
- **I-3 Solvency:** `USDC.balanceOf(contract) ≥ Σ balance (all retainers) + totalOwed`. (Equality holds unless someone transfers USDC to the contract directly.)
- **I-4 Conservation:** for every retainer, `totalDeposited == balance + totalPaid + totalReturned`.
- **I-5 Destination safety:** USDC leaves the contract only to a retainer's `client`, that retainer's `freelancer`, or an address withdrawing its own `owed` credit.
- **I-6 Terminality:** `Paid`, `Objected`, `Cancelled` are terminal. No transition leaves them.
- **I-7 Time ordering:** for every claim, `payableAt == filedAt + objectionWindow` and `filedAt < endTime` at filing.
- **I-8 Immutability of terms:** `client`, `freelancer`, `objectionWindow`, `noticePeriod` never change after creation; `endTime` only increases.

## 9. State machines

### 9.1 Claim

```
               fileClaim
   (none) ─────────────────▶ Pending
                               │
     ┌─────────────────────────┼─────────────────────────────┐
     │ objectToClaim           │ approveClaim                │ payOutClaim
     │ (client, t < payableAt) │ (client, any t)             │ (anyone, t ≥ payableAt)
     ▼                         ▼                             ▼
  Objected                   Paid (ApprovedNow)           Paid (PaidOut)
                               ▲
     cancelClaim (freelancer, any t) ──▶ Cancelled
```

### 9.2 Withdrawal

```
  none ──requestWithdrawal──▶ pending(amount, readyAt)
  pending ──cancelWithdrawal──▶ none
  pending ──completeWithdrawal (t ≥ readyAt)──▶ none   [pays min(amount, available)]
  pending ──withdrawRemainder (after end)──▶ none      [pays all available]
```

### 9.3 Retainer phase (derived, not stored)

```
  Active (t < endTime) ──time──▶ Ended (t ≥ endTime) ──extendEndTime──▶ Active
```

## 10. Events

```solidity
event RetainerCreated(uint256 indexed id, address indexed client, address indexed freelancer,
                      uint32 objectionWindow, uint32 noticePeriod, uint64 endTime);
event Deposited(uint256 indexed id, address indexed from, uint128 amount, uint128 newBalance);
event ClaimFiled(uint256 indexed id, uint256 indexed claimId, uint128 amount, uint64 payableAt, string note);
event ClaimObjected(uint256 indexed id, uint256 indexed claimId, string reason);
event ClaimCancelled(uint256 indexed id, uint256 indexed claimId);
event ClaimPaid(uint256 indexed id, uint256 indexed claimId, address indexed to, uint128 amount, PaidVia via);
event WithdrawalRequested(uint256 indexed id, uint128 amount, uint64 readyAt);
event WithdrawalCancelled(uint256 indexed id);
event WithdrawalCompleted(uint256 indexed id, uint128 requested, uint128 paid);
event RemainderWithdrawn(uint256 indexed id, uint128 amount);
event EndTimeExtended(uint256 indexed id, uint64 oldEndTime, uint64 newEndTime);
event PayoutDeferred(address indexed to, uint256 amount);
event OwedWithdrawn(address indexed to, uint256 amount);
```

## 11. Errors

```solidity
error InvalidToken();
error InvalidFreelancer();
error WindowOutOfRange();
error NoticeOutOfRange();
error EndTimeTooSoon();
error EndTimeNotLater();
error RetainerNotFound();
error ClaimNotFound();
error NotClient();
error NotFreelancer();
error RetainerEnded();
error RetainerNotEnded();
error ZeroAmount();
error TextTooLong();
error TooManyPendingClaims();
error InsufficientAvailable();
error ClaimNotPending();
error ObjectionWindowClosed();
error ObjectionWindowOpen();
error WithdrawalAlreadyPending();
error NoWithdrawalPending();
error NoticeNotElapsed();
error NothingOwed();
error DepositMismatch();
```

Every error MUST appear in the frontend error map (05-FRONTEND-SPEC §7).

## 12. Check ordering convention

For every function: **existence → authorization → phase (ended/not ended) → argument validity → state preconditions → balance checks**. Tests assert the exact error, so ordering is part of the interface.

**Exceptions (ruled 2026-10-25):** where a function's own **Pre** list orders checks differently, the Pre list wins and tests follow it. Known cases: `deposit` (`ZeroAmount` before `RetainerEnded`), `requestWithdrawal` (`WithdrawalAlreadyPending` before `ZeroAmount`), `objectToClaim` (`ObjectionWindowClosed` before `TextTooLong`).

## 13. Gas and size notes

- No function loops in state-changing code; gas is O(1) per call.
- Strings are `calldata` and only hashed or emitted, never stored.
- Expected contract size well under the 24 KB limit; if not, something has been added that the spec does not contain.

## 14. Worked example (matches the demo script)

Window 300 s, notice 300 s, end in 7 days. Amounts in USDC (6 dp).

| t (s) | Action | balance | reserved | available | Notes |
|---|---|---|---|---|---|
| 0 | create + deposit 10 | 10 | 0 | 10 | |
| 30 | freelancer files claim #0 for 3 | 10 | 3 | 7 | payableAt = 330 |
| 330 | anyone pays out #0 | 7 | 0 | 7 | **silent payout**: freelancer +3 |
| 360 | freelancer files claim #1 for 2 | 7 | 2 | 5 | payableAt = 660 |
| 400 | client objects to #1 | 7 | 0 | 7 | no USDC moves |
| 420 | client requests withdrawal of 7 | 7 | 0 | 7 | readyAt = 720 |
| 450 | freelancer files claim #2 for 1 | 7 | 1 | 6 | allowed during notice |
| 460 | client approves #2 now | 6 | 0 | 6 | freelancer +1 |
| 720 | anyone completes withdrawal | 0 | 0 | 0 | client receives min(7, 6) = 6 |

Check I-4: deposited 10 = balance 0 + paid 4 + returned 6. ✓
