# 02 — Architecture

## 1. System shape

Unless is deliberately two components and nothing else: one immutable contract and one static web app. Every piece of state the app shows is read from the chain; every action the app takes is a wallet-signed transaction.

```
            ┌─────────────────────────────────────────────────┐
            │                 Browser (static app)             │
            │                                                   │
 client ──▶ │  routes/  ──  hooks/useRetainer, useClaims        │
 wallet     │     │            │ reads: view functions (poll)   │
            │     │            │ writes: wallet-signed txs      │
 freelancer │  components/     │                                │
 wallet ──▶ │  lib/errors (custom error → message)              │
            │  lib/time (chain-time sync, countdowns)           │
            └──────────────┬──────────────────────┬─────────────┘
                           │ JSON-RPC             │ explorer links
                           ▼                      ▼
            ┌──────────────────────────┐   explorer.arc.io
            │   Arc mainnet (5042)      │
            │                           │
            │  UnlessRetainer           │──transferFrom / transfer──▶ USDC (ERC-20 iface)
            │  (immutable, no admin)    │                              0x3600…0000
            └──────────────────────────┘
```

No backend, indexer, keeper, oracle, relayer, database, or API key. This is a product decision (ADR-001), an eligibility decision (everything must be buildable in Arc Studio), and a security decision (no server can move money).

## 2. Contract architecture

- **One singleton contract holds every retainer.** Retainers are identified by an incrementing `uint256` id. No factory, no per-retainer clones (ADR-003).
- **Per-retainer accounting is self-contained.** Each retainer tracks its own `balance` and `reserved`. A bug or griefing attempt in one retainer cannot touch another's money because every money-moving function operates on exactly one retainer id and checks its own balance.
- **Aggregates, not iteration.** `reserved` is updated on every claim transition. No function loops over claims.
- **Push with credit fallback for outbound USDC.** The contract attempts a direct transfer; if the recipient cannot receive (e.g., blocklisted), the amount is credited to `owed[recipient]` and can be pulled later. A recipient problem never blocks the counterparty (ADR-006).
- **Time is the only external input.** All conditions are `block.timestamp` comparisons and caller identity. No oracle.

## 3. Frontend architecture

- **Static SPA** built by Studio's Vite scaffold, hosted on any static host.
- **Reads** come from view functions (`getRetainer`, `getClaims`, `retainersOfClient`, `retainersOfFreelancer`, `owed`), polled at a modest interval and refetched after every confirmed transaction. The app does **not** depend on scanning event logs for correctness; events power the activity timeline only and may be fetched over a bounded block range (ADR-007).
- **Chain time, not wall time.** Countdowns are computed from the latest block timestamp plus elapsed local time since that block was fetched. A user with a wrong clock still sees the right state.
- **Network is a build-time setting** (`VITE_NETWORK=testnet|mainnet`); the app refuses to transact when the wallet is on another chain and offers to switch.
- **Error mapping is total.** Every custom error the contract can raise has a human message (05-FRONTEND-SPEC §7).

## 4. Trust model

| Actor | Can | Cannot |
|---|---|---|
| Client | Fund, top up, approve now, object (window open), request/cancel withdrawal, withdraw remainder after end, extend end date | Touch reserved money; withdraw without notice before end; redirect any payout; change the freelancer, window, or notice |
| Freelancer | File claims (≤ available, before end), cancel own pending claims | Claim more than available; claim after end; stop an objection; touch the client's withdrawal |
| Anyone | Pay out matured claims; complete matured withdrawals; pull their own owed balance | Change where any money goes |
| Deployer | Nothing after deployment | Everything (no privileged role exists) |
| Arc/Circle | Operate the chain and USDC (including blocklisting addresses) | — this is a platform risk, handled by credit fallback |

**Money can only ever go to the retainer's client or its freelancer.** This is the master safety property (03-CONTRACT-SPEC §8, I-5).

## 5. Threat model

| # | Threat | Vector | Mitigation | Residual risk |
|---|---|---|---|---|
| T1 | Client drains retainer before a claim matures | Withdraw while claim pending | Reserved funds excluded from `available`; withdrawal pays `min(requested, available at completion)` | None |
| T2 | Client empties retainer right before freelancer bills | Instant withdrawal | Withdrawal notice period; freelancer can claim during notice | Freelancer must actually file during notice |
| T3 | Freelancer over-claims | Claim > available | `amount ≤ available` check; reservation is atomic | None |
| T4 | Freelancer claims for work not done | Self-reported note | Objection window; client can object | Client must watch claims (UI makes pending claims prominent) |
| T5 | Client objects to everything | Bad faith | Public, permanent objection record; freelancer stops work | Real; no arbiter in v1 (documented limitation) |
| T6 | Reentrancy | Malicious token callback | USDC system contract has no hooks; still CEI + `nonReentrant` | None known |
| T7 | Recipient blocklisted, payout reverts and freezes funds | USDC blocklist | Push-with-credit fallback, `withdrawOwed()` | Recipient may remain unable to receive |
| T8 | Decimal confusion | Mixing 18-dp native with 6-dp ERC-20 | ERC-20 interface only; no `msg.value` | None if rule followed |
| T9 | Griefing with many tiny claims | Freelancer spams claims | `MAX_PENDING_CLAIMS = 20`; client can object | Minor UI clutter |
| T10 | Boundary race at window end | Object and execute in same second | Object requires `now < payableAt`; execute requires `now ≥ payableAt`; disjoint | None |
| T11 | Timestamp manipulation | Validator skew | Windows are minutes-to-days; Arc timestamps non-decreasing with 1 s granularity | Negligible |
| T12 | Approval phishing via our app | Unlimited approval | Exact-amount approvals only | User's other approvals out of scope |
| T13 | Silent transaction drops | `maxFeePerGas < 20 gwei` | Fee floor enforced in app | None |
| T14 | Front-end compromise | Malicious hosted build | Contract enforces all rules; address shown and linked to explorer; repo public | A compromised UI could request a malicious approval: exact-approval rule limits blast radius |
| T15 | Wrong-network deposit | User on testnet thinks it's mainnet | Network banner; chain-id check before every write | None |

## 6. Failure modes and recovery

| Failure | Effect | Recovery |
|---|---|---|
| Nobody presses "Pay out" | Matured claim stays pending; money still reserved | Anyone can execute at any later time; no expiry on execution |
| Client loses their key | Pending claims still pay out by silence; remaining available money is stuck until end date… and then stuck (only client can withdraw) | Documented; future: designated backup address |
| Freelancer loses key | Cannot file new claims; pending claims still pay to the old address | Client can object to pending claims and, after end date, withdraw |
| App host goes down | No UI | Contract is usable via explorer or `cast`; README documents function calls |
| RPC outage | Reads/writes fail | App lists a fallback RPC; user can switch |
| USDC blocklists contract | All transfers fail | Platform risk, outside our control; documented |

## 7. Data model at a glance

```
Retainer (id)
 ├─ client, freelancer
 ├─ objectionWindow, noticePeriod, endTime, createdAt
 ├─ balance, reserved            → available = balance − reserved
 ├─ withdrawal {amount, readyAt} (0/0 = none)
 ├─ pendingClaims, claimCount
 ├─ totals {deposited, paid, returned}
 └─ claims[claimId]
      └─ amount, filedAt, payableAt, status, noteHash
           status ∈ {Pending, Paid, Objected, Cancelled}
           paidVia ∈ {None, ApprovedNow, PaidOut}
owed[address]  (credit-fallback ledger, global)
```

## 8. Why each architectural choice serves the grant rubric

| Rubric criterion | Architectural consequence |
|---|---|
| Real USDC on mainnet (30%) | Every product action moves USDC through the contract between two distinct wallets |
| Arc Studio across the build (25%) | No backend means Studio can author 100% of shipped code; bytecode-match proves lineage to mainnet |
| Working product (25%) | Small state machine; no external dependencies to fail during review |
| Potential (20%) | Clean primitive that a future arbiter, invoicing tool, or agent-payments layer can build on |
