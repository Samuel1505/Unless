# 04 — Test Plan

Tests are part of the grant's Studio criterion ("contracts, testing, and app") and the only real defense for a contract that holds other people's money with no admin key. They are written in Studio, run in Studio's terminal, and their output is captured as evidence.

## 1. Test layers

| Layer | File | Runs where | Purpose |
|---|---|---|---|
| Unit | `test/UnlessRetainer.t.sol` | Studio terminal, local | Every function × every precondition × every effect |
| Invariant (stateful fuzz) | `test/UnlessRetainer.invariant.t.sol` | Studio terminal, local | The eight invariants of 03-CONTRACT-SPEC §8 under random call sequences |
| Fork | `test/UnlessRetainer.fork.t.sol` | Wherever Arc RPC is reachable | Real Arc USDC at `0x3600…0000`: approve, transferFrom, transfer, decimals behavior |
| Manual testnet | `evidence/testnet-runbook.md` | Arc testnet via Studio preview | Every product flow F1–F13 with real wallets |

## 2. Fixtures and conventions

### 2.1 Mocks (`test/mocks/`)

- **`MockUSDC`**: ERC-20, `decimals() == 6`, public `mint(address,uint256)`. Standard `transfer`/`transferFrom` returning `true`.
- **`BlocklistUSDC is MockUSDC`**: `setBlocked(address,bool)`; `transfer` and `transferFrom` **revert** when sender or recipient is blocked (mirrors Arc's blocklist behavior of reverting at runtime).
- **`FalseReturnUSDC is MockUSDC`** (optional): `transfer` returns `false` instead of reverting for blocked recipients, to exercise the `ret` decoding branch.

### 2.2 Actors

```
client     = makeAddr("client")
freelancer = makeAddr("freelancer")
stranger   = makeAddr("stranger")
client2, freelancer2  // for cross-retainer isolation tests
```
Each actor is minted 1,000 USDC (`1_000e6`) and approves the retainer contract for exact amounts per test.

### 2.3 Default parameters

```
WINDOW = 300        // 5 minutes, matches demo
NOTICE = 300
END    = block.timestamp + 7 days
```

### 2.4 Naming

`test_<function>_<condition>_<expectedOutcome>`
e.g. `test_payOutClaim_beforePayableAt_revertsObjectionWindowOpen`.

Fuzz tests: `testFuzz_<function>_<property>`. Invariants: `invariant_<I-n>_<name>`.

### 2.5 Assertions on errors

Always assert the **exact** selector: `vm.expectRevert(UnlessRetainer.ObjectionWindowOpen.selector)`. Never bare `vm.expectRevert()`.

### 2.6 Assertions on events

For every successful state-changing call, assert the event with `vm.expectEmit(true, true, true, true)` and the full argument list.

### 2.7 Time

Use `vm.warp`. Boundary tests MUST test `payableAt − 1`, `payableAt`, and `payableAt + 1` (and the same for `withdrawalReadyAt` and `endTime`).

## 3. Invariant suite

### 3.1 Handler design

`UnlessHandler` wraps the contract and is the only target of the fuzzer. It:

- Maintains a small fixed set of actors (2 clients, 2 freelancers, 1 stranger) and up to 3 retainers.
- Exposes bounded actions: `create`, `deposit`, `fileClaim`, `approve`, `object`, `cancel`, `payOut`, `requestWithdrawal`, `cancelWithdrawal`, `completeWithdrawal`, `withdrawRemainder`, `extendEnd`, `warp(seconds)`, `toggleBlocklist(actor)` (when using `BlocklistUSDC`), `withdrawOwed`.
- Bounds inputs with `bound()` so most calls are *valid* (target ≥ 70% non-reverting); calls that would revert are skipped, not attempted, to keep depth useful.
- Keeps **ghost variables**: per retainer `ghostDeposited`, `ghostPaidToFreelancer`, `ghostReturnedToClient`; a per-address `ghostReceived`; and a list of pending claim ids per retainer for I-2.

### 3.2 Invariants

| Test | Encodes |
|---|---|
| `invariant_I1_reservedLeBalance` | `reserved ≤ balance` for every retainer |
| `invariant_I2_reservedMatchesPending` | `reserved == Σ pending amounts` and `pendingClaims == count(pending)` |
| `invariant_I3_solvency` | `token.balanceOf(retainer) ≥ Σ balance + totalOwed` |
| `invariant_I4_conservation` | `totalDeposited == balance + totalPaid + totalReturned` |
| `invariant_I5_destinationSafety` | Σ `ghostReceived` over non-parties == 0 (stranger never receives) |
| `invariant_I6_terminality` | Ghost log of status transitions contains no transition out of a terminal state |
| `invariant_I8_termsImmutable` | client, freelancer, window, notice unchanged; endTime non-decreasing |
| `invariant_ghostsMatchContract` | ghost totals equal contract totals |

### 3.3 Configuration

```toml
[invariant]
runs = 256
depth = 128
fail_on_revert = false
```
If Studio's environment is slow, reduce `runs` but never below 64; record the values used in the evidence.

## 4. Unit test catalogue

Each row is at least one test. "×" columns mean one test per listed condition.

### 4.1 Constructor
- reverts `InvalidToken` for zero address
- sets `USDC` immutable

### 4.2 `createRetainer`
- happy path: ids increment from 0; storage fields correct; both index arrays updated; events emitted
- with `initialDeposit == 0`: no transfer, no `Deposited`
- with deposit: balance, totalDeposited, token balances
- × reverts: zero freelancer; freelancer == caller; window `MIN−1`, `MAX+1`; notice `MIN−1`, `MAX+1`; `endTime == now + notice` (`EndTimeTooSoon`); insufficient allowance (SafeERC20 revert)
- boundary success: window == `MIN_WINDOW`, == `MAX_WINDOW`; notice likewise; `endTime == now + notice + 1`

### 4.3 `deposit`
- happy path; multiple deposits accumulate
- × reverts: not client; unknown id; zero amount; after end
- `DepositMismatch` using a fee-on-transfer mock (proves the defensive check)

### 4.4 `fileClaim`
- happy path: claim fields, `payableAt == now + WINDOW`, `reserved`, `pendingClaims`, noteHash, event carries full note
- amount == available succeeds; amount == available + 1 reverts `InsufficientAvailable`
- note of exactly 280 bytes succeeds; 281 reverts `TextTooLong`
- 20 pending succeed; 21st reverts `TooManyPendingClaims`; after resolving one, filing succeeds again
- × reverts: not freelancer (client, stranger); unknown id; after end (`t == endTime` reverts, `t == endTime − 1` succeeds); zero amount
- allowed while a withdrawal is pending

### 4.5 `approveClaim`
- pays freelancer immediately; status Paid, paidVia ApprovedNow; accounting
- succeeds after `payableAt` (still pending)
- × reverts: not client; not pending (paid, objected, cancelled); unknown claim

### 4.6 `objectToClaim`
- unreserves, no token movement, reason in event
- at `payableAt − 1` succeeds; at `payableAt` reverts `ObjectionWindowClosed`
- reason 281 bytes reverts
- × reverts: not client; not pending

### 4.7 `cancelClaim`
- freelancer cancels; unreserves
- × reverts: not freelancer; not pending

### 4.8 `payOutClaim`
- at `payableAt − 1` reverts `ObjectionWindowOpen`; at `payableAt` succeeds; called by stranger succeeds and stranger receives nothing
- double payout reverts `ClaimNotPending`
- paidVia == PaidOut

### 4.9 Withdrawal lifecycle
- request: fields set, readyAt == now + NOTICE
- second request while pending reverts `WithdrawalAlreadyPending`
- request > available reverts; request after end reverts `RetainerEnded`
- complete at `readyAt − 1` reverts `NoticeNotElapsed`; at `readyAt` succeeds; callable by stranger, pays client
- **notice protection:** deposit 7, request 7 → freelancer files 3 during notice → complete pays 4 (with deposit 10 it pays 7: payout is `min(requested, available)`)
- **zero completion:** deposit 5, request 5 → freelancer files 5 → complete pays 0, clears request, emits `WithdrawalCompleted(id, 5, 0)`
- complete after end succeeds
- cancel clears; cancel with none reverts `NoWithdrawalPending`

### 4.10 `withdrawRemainder`
- before end reverts `RetainerNotEnded`; at `endTime` succeeds
- pays only available; pending claims stay reserved and still pay out afterwards
- clears a pending withdrawal and emits `WithdrawalCancelled` first
- zero available reverts `ZeroAmount`

### 4.11 `extendEndTime`
- equal or earlier reverts `EndTimeNotLater`
- after end, extension re-enables `fileClaim`

### 4.12 Credit fallback (with `BlocklistUSDC`)
- freelancer blocked → payOut succeeds, `owed[freelancer] == amount`, `PayoutDeferred` emitted, retainer accounting identical to normal payout
- client blocked → completeWithdrawal succeeds with credit
- unblock → `withdrawOwed` transfers and zeroes; second call reverts `NothingOwed`
- still blocked → `withdrawOwed` reverts and credit is preserved
- `FalseReturnUSDC` variant exercises the `false`-return branch

### 4.13 Isolation
- two retainers, different parties: actions on one never change the other's fields or balances
- a freelancer of retainer A cannot file on retainer B (`NotFreelancer`)

### 4.14 Views
- `getRetainer` returns correct `available` and `ended`; unknown id reverts
- `getClaims` pagination: offset/limit clamping, empty beyond end
- index arrays list ids in creation order

### 4.15 Worked example
- `test_workedExample_matchesSpecTable`: replays 03-CONTRACT-SPEC §14 step by step and asserts every column of every row. **This test is the contract between the spec and the demo.**

### 4.16 Fuzz (stateless)
- `testFuzz_fileClaim_neverExceedsAvailable(uint128 deposit, uint128 amount)`
- `testFuzz_completeWithdrawal_paysMinOfRequestedAndAvailable(...)`
- `testFuzz_window_boundaries(uint32 window, uint32 offset)`

## 5. Coverage matrix (Gate 2 checklist)

Tick every cell before leaving Phase 2.

**Status (2026-10-25, Studio P4):** all cells ticked. 380 tests pass (`evidence/test-output.txt`); `UnlessRetainer.sol` coverage is 100% lines, statements, branches and functions (`evidence/coverage.txt`).

| Function | Happy | Auth | Phase | Args | State pre | Boundary | Event | Fallback |
|---|---|---|---|---|---|---|---|---|
| createRetainer | ☑ | n/a | n/a | ☑ | n/a | ☑ | ☑ | n/a |
| deposit | ☑ | ☑ | ☑ | ☑ | n/a | n/a | ☑ | n/a |
| fileClaim | ☑ | ☑ | ☑ | ☑ | ☑ | ☑ | ☑ | n/a |
| approveClaim | ☑ | ☑ | n/a | n/a | ☑ | n/a | ☑ | ☑ |
| objectToClaim | ☑ | ☑ | n/a | ☑ | ☑ | ☑ | ☑ | n/a |
| cancelClaim | ☑ | ☑ | n/a | n/a | ☑ | n/a | ☑ | n/a |
| payOutClaim | ☑ | n/a | n/a | n/a | ☑ | ☑ | ☑ | ☑ |
| requestWithdrawal | ☑ | ☑ | ☑ | ☑ | ☑ | n/a | ☑ | n/a |
| cancelWithdrawal | ☑ | ☑ | n/a | n/a | ☑ | n/a | ☑ | n/a |
| completeWithdrawal | ☑ | n/a | n/a | n/a | ☑ | ☑ | ☑ | ☑ |
| withdrawRemainder | ☑ | ☑ | ☑ | n/a | ☑ | ☑ | ☑ | ☑ |
| extendEndTime | ☑ | ☑ | n/a | ☑ | n/a | n/a | ☑ | n/a |
| withdrawOwed | ☑ | n/a | n/a | n/a | ☑ | n/a | ☑ | ☑ |

Target line coverage ≥ 95% and branch coverage ≥ 90% from `arc-forge coverage` (or `forge coverage`). Save the summary to `evidence/coverage.txt`.

## 6. Fork tests (real Arc USDC)

Only run where the environment can reach Arc RPC. If Studio's sandbox cannot, run them locally after export and note it in the evidence.

- `test_fork_usdcInterface`: `decimals() == 6`; approve + transferFrom into the contract; transfer out; balances move by exact 6-dp amounts.
- `test_fork_fullHappyPath`: create → file → warp → payOut using real USDC (deal via impersonating a funded address or use Arc Foundry's native-USDC cheat support if available — **NEEDS VERIFICATION**).
- `test_fork_nativeAndErc20ShareBalance`: after an ERC-20 transfer, the recipient's native balance (18 dp) changed by `amount × 1e12`.

Arc Foundry is required for faithful native-USDC behavior; stock `anvil` does not emulate Arc's precompiles (06-ARC-PLATFORM-NOTES §3).

## 7. Manual testnet runbook (Gate 3)

Execute in the Studio preview with two wallets (two browser profiles). For each step record tx hash, block, and a screenshot into `evidence/testnet-runbook.md`.

1. F1 create + fund 10 · 2. F3 claim 3 · 3. wait → F4 pay out (third wallet or freelancer) · 4. F3 claim 2 → F6 object · 5. F8 request withdrawal 7 · 6. F3 claim 1 during notice → F5 approve now · 7. F9 complete (expect 6) · 8. F2 top up 1 · 9. F7 cancel a claim · 10. F12 extend end · 11. (optional) F11 after a short-end retainer.

## 8. Static analysis

If available in the environment, run Slither and record the output in `evidence/slither.txt`. Expected findings: timestamp comparisons (by design). Any other finding must be triaged in writing.
