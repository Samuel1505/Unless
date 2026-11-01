# 10 — Architecture Decision Records

Each ADR: context, decision, consequences, and what would make us revisit it. Add new ADRs at the end; never rewrite accepted ones — supersede them.

---

## ADR-001 — No backend of any kind
**Status:** accepted

**Context.** The grant requires the app to be built in Arc Studio, and Studio's documented capabilities are a Vite frontend plus Foundry contracts; backend functions, secrets, and scheduled jobs are not documented. A backend would also be a party that can fail or be compromised.

**Decision.** The product is one contract and one static app. All reads are view calls; all writes are wallet-signed. Matured claims and withdrawals are executed by any user pressing a button.

**Consequences.** Nothing happens automatically at the exact second a window closes; someone has to press "Pay out". This is acceptable because execution has no deadline and anyone may do it. No notifications in v1.

**Revisit if.** A real user loses money or trust because nobody executed a matured claim for a long time. Then add an optional, permissionless keeper (any bot can call `payOutClaim`), still with no special rights.

---

## ADR-002 — ERC-20 interface only for USDC accounting
**Status:** accepted

**Context.** Arc exposes USDC both as the native gas token (18 decimals) and through an ERC-20 interface (6 decimals) over one shared balance. Mixing the two is off by 10¹². Native value sent to a contract is not guaranteed to succeed, and ERC-20 transfers into a contract do not run its code.

**Decision.** All deposits use `transferFrom` and all payouts use `transfer` on `0x3600…0000`. The contract never reads `msg.value` or `address(this).balance`, and defines no `receive`/`fallback`.

**Consequences.** Deposits need an approval step (two transactions on first use). Accounting is uniform and testable with a plain 6-decimal mock.

**Revisit if.** Arc documents a safe, single-transaction native deposit path with clear accounting semantics — and even then only with a new invariant suite.

---

## ADR-003 — Singleton contract, retainers as ids
**Status:** accepted

**Context.** Alternatives were a factory deploying one contract (or clone) per retainer.

**Decision.** One contract holds all retainers in mappings keyed by an incrementing id.

**Consequences.** One address to verify, link, and prove (simplifies the bytecode-match evidence and reviewer verification). Per-retainer isolation is enforced by accounting rather than by separate contracts, so invariants I-1 to I-4 must hold per retainer, and isolation tests are mandatory.

**Revisit if.** Retainers need per-instance customization that cannot be expressed as parameters.

---

## ADR-004 — Immutable, no admin, no fee
**Status:** accepted

**Context.** Any privileged role is a party that can move or freeze other people's money, which contradicts the product's trust story and enlarges the attack surface.

**Decision.** No owner, pause, upgrade, fee, or rescue function.

**Consequences.** Bugs cannot be patched in place; recovery is redeploy-and-migrate (07-DEPLOYMENT-RUNBOOK §8). Demo with small amounts. Stray USDC sent directly to the contract is unrecoverable (documented).

**Revisit if.** Never for v1. A future version with an arbiter will still have no admin; the arbiter is chosen per retainer by the parties.

---

## ADR-005 — Approval by silence, with a disjoint time boundary
**Status:** accepted

**Context.** The product's core idea is that the trigger for payment is time, and the client's role is veto, not approval.

**Decision.** A claim is objectionable while `now < payableAt` and payable while `now ≥ payableAt`. The client can also approve early.

**Consequences.** No ambiguous instant where both object and payout are valid. Arc's shared-timestamp blocks don't create a race because the conditions are disjoint for any single timestamp.

**Revisit if.** Users want "pause the clock" semantics (e.g., client asks a question). That would be a new claim state, not a change to this boundary.

---

## ADR-006 — Push payouts with credit fallback
**Status:** accepted

**Context.** USDC on Arc enforces a blocklist; transfers to blocklisted addresses revert. With plain push payments, a blocklisted freelancer would make `payOutClaim` revert forever, and a blocklisted client would make withdrawals revert. Pure pull payments avoid this but add a transaction to every payout and weaken the demo ("paid" would mean "withdrawable").

**Decision.** Attempt a direct transfer; if it fails, credit `owed[recipient]` and emit `PayoutDeferred`. Recipients pull credits with `withdrawOwed()`.

**Consequences.** The happy path is one transaction and the freelancer's wallet balance changes immediately. Failures never block the counterparty. `totalOwed` enters the solvency invariant.

**Revisit if.** Arc changes USDC transfer semantics.

---

## ADR-007 — View functions for state, events for history
**Status:** accepted

**Context.** Log scanning over long ranges is slow, provider-dependent, and fragile; a broken log query must not break the product.

**Decision.** Everything needed to decide what actions are valid comes from view functions (`getRetainer`, `getClaims`, indexes, `owed`). Events power the activity timeline only, over a bounded block range.

**Consequences.** Slightly more storage (claim records, per-address index arrays). The app works on any RPC.

---

## ADR-008 — Notes in events, hashes in storage
**Status:** accepted

**Context.** Claim notes and objection reasons are useful context but storing strings is expensive and unnecessary for logic.

**Decision.** Store `keccak256(note)`; emit the full text in `ClaimFiled` / `ClaimObjected`. Cap at 280 bytes.

**Consequences.** If the activity range doesn't reach an old claim's event, the UI shows "note not loaded" with an explorer link. The hash lets anyone verify a displayed note.

**Revisit if.** Users need notes rendered without any log access.

---

## ADR-009 — Withdrawal notice does not reserve funds
**Status:** accepted

**Context.** If a withdrawal request reserved its amount, the freelancer could not claim during notice, defeating the notice's purpose.

**Decision.** A withdrawal request only records an amount and a ready time. At completion the client receives `min(requested, available)`.

**Consequences.** The client may receive less than requested; the UI states this up front ("claims filed before then are still paid"). A completion can pay zero and still clears the request.

---

## ADR-010 — Short minimum windows to enable a real mainnet demo
**Status:** accepted

**Context.** Real retainers use windows of days; a grant demo cannot wait days.

**Decision.** `MIN_WINDOW = MIN_NOTICE = 60 s`; the demo uses 300 s. The app's default is 48 h / 72 h, with "5 minutes (demo)" as an explicit preset.

**Consequences.** A careless client could create a retainer with a 1-minute window. The create form's summary sentence makes the consequence explicit.

**Revisit if.** Post-grant: consider raising the minimum to 1 hour in a v2 deployment.

---

## ADR-011 — Use Arc Studio as the author, Arc Foundry as the deployer
**Status:** accepted

**Context.** The grant requires Studio-built contracts, tests, and app; Studio cannot deploy to mainnet.

**Decision.** All code changes go through Studio (browser or CLI). Mainnet deployment uses Arc Foundry on the exact pushed commit. Lineage is proven by identical runtime bytecode hashes on testnet (Studio-deployed) and mainnet.

**Consequences.** Local "quick fixes" are forbidden unless re-applied through Studio before deployment.

---

## ADR-012 — `_send` checks the return word equals 1
**Status:** accepted (2026-10-25)

**Context.** The original §6.4 snippet decoded the `transfer` return as `bool`. Solidity's ABI decoder reverts on a 32-byte word that is not 0 or 1, so a misbehaving token could make `_send` revert, violating ADR-006.

**Decision.** Success is `ok && (ret.length == 0 || (ret.length == 32 && uint256(word) == 1))`, the same test OpenZeppelin SafeERC20 uses. Anything else credits `owed`.

**Consequences.** `_send` can never revert because of the token's return data. For real USDC (returns `true`) behavior is identical to the original text.

---

## ADR-013 — No code-length check on the USDC address
**Status:** accepted (2026-10-25)

**Context.** With an empty return treated as success, a call to an address with no code would look like a successful payment. OpenZeppelin guards this with `code.length > 0`.

**Decision.** No code-length check, in the constructor or in `_send`. `USDC` is immutable and fixed to `0x3600…0000` on both networks. That address is Arc's native-USDC system interface, and whether it reports ordinary contract code is not verified (06-ARC-PLATFORM-NOTES). A check that failed there would push every payout into the `owed` ledger.

**Consequences.** Deploying with a wrong token address is caught by the deployment runbook and the testnet run, not by the contract.

**Revisit if.** Arc documents that `0x3600…0000` reports nonzero code length, in a v2 deployment only.

---

## ADR-014 — `block.timestamp` lint findings are accepted, not suppressed
**Status:** accepted (2026-10-25)

**Context.** `forge lint` flags every `block.timestamp` comparison. The product is time-based by design (objection window, notice period, end time).

**Decision.** No `forge-lint: disable` comments in the contract. Gate 1's "zero warnings" means compiler warnings. Lint and Slither timestamp findings are expected (04-TEST-PLAN §8).

**Consequences.** Lint output is not empty. Any lint finding other than `block-timestamp` must be triaged.

