# P0 Orientation: Unless

Read in CLAUDE.md section 2 order. No code written yet.

## 0. Rulings (recorded 2026-10-25)

Updated `CLAUDE.md` and `docs/03-CONTRACT-SPEC.md` are the source of truth. I verified the edits are present.

| # | Item | Ruling | Effect on implementation and tests |
|---|---|---|---|
| 1 | Unknown claim id | ACCEPTED | `approveClaim`, `objectToClaim`, `cancelClaim`, `payOutClaim` revert `ClaimNotFound` when `claimId >= claimCount`. Order: `RetainerNotFound`, then `ClaimNotFound`, then authorization, then the rest of the Pre list (spec 6.6 to 6.9). |
| 2 | Check ordering | ACCEPTED | Each function's own Pre list wins over section 12. Section 12 lists three exceptions: `deposit` (`ZeroAmount` before `RetainerEnded`), `requestWithdrawal` (`WithdrawalAlreadyPending` before `ZeroAmount`), `objectToClaim` (`ObjectionWindowClosed` before `TextTooLong`). Tests follow the Pre lists. |
| 3 | Invariant count | ACCEPTED | CLAUDE.md Gate 0 now says eight. |
| 7 | Metadata settings | REJECTED | `foundry.toml` is NOT changed for metadata. No `bytecode_hash = "none"`, no `cbor_metadata = false`. Default compiler metadata stays so explorers can fully verify source. The mainnet deploy uses this exact source and `foundry.toml`. |
| 4, 5, 6, 8 to 16 | Accepted as stated below | ACCEPTED | See section 4. For item 13 the working deadline is the earliest date in the docs (Oct 27 for funding the demo wallets, Oct 30 for the demo, per docs 06 and 01). |

Consequences of ruling 7: the only `foundry.toml` edit I will make is the `[invariant]` block (runs 256, depth 128, fail_on_revert false), which does not affect compiled output. After the first testnet deploy, `foundry.toml`, `remappings.txt`, the OpenZeppelin version and the contract source are frozen.

---

## 1. The eight invariants (docs/03 section 8), in my words

- **I-1 Reservation bound.** In every retainer, money set aside for pending claims never exceeds the money held. `reserved <= balance`, so `available` can never go negative.
- **I-2 Reservation exactness.** `reserved` is exactly the sum of that retainer's Pending claim amounts, and `pendingClaims` is exactly their count. Incremental counters never drift from the claims.
- **I-3 Solvency.** The contract's real USDC balance is at least the sum of all retainer balances plus `totalOwed`. Equality holds unless someone sends USDC straight to the contract.
- **I-4 Conservation.** Per retainer, everything ever deposited is accounted for: `totalDeposited == balance + totalPaid + totalReturned`.
- **I-5 Destination safety.** USDC only ever leaves to that retainer's client, that retainer's freelancer, or an address pulling its own `owed` credit. Nobody else, including whoever pressed the button.
- **I-6 Terminality.** Paid, Objected and Cancelled claims never change state again.
- **I-7 Time ordering.** Every claim has `payableAt == filedAt + objectionWindow`, and was filed strictly before `endTime`.
- **I-8 Immutability of terms.** `client`, `freelancer`, `objectionWindow` and `noticePeriod` never change after creation. `endTime` only moves later.

## 2. External functions I will implement (exactly these)

State-changing, all `external nonReentrant`, none payable:

1. `createRetainer(address,uint32,uint32,uint64,uint128) returns (uint256)`
2. `deposit(uint256,uint128)`
3. `fileClaim(uint256,uint128,string) returns (uint256)`
4. `approveClaim(uint256,uint256)`
5. `objectToClaim(uint256,uint256,string)`
6. `cancelClaim(uint256,uint256)`
7. `payOutClaim(uint256,uint256)`
8. `requestWithdrawal(uint256,uint128)`
9. `cancelWithdrawal(uint256)`
10. `completeWithdrawal(uint256)`
11. `withdrawRemainder(uint256)`
12. `extendEndTime(uint256,uint64)`
13. `withdrawOwed()`

Views: `getRetainer(uint256)`, `getClaim(uint256,uint256)`, `getClaims(uint256,uint256,uint256)`, `retainersOfClient(address)`, `retainersOfFreelancer(address)`.

Auto-generated public getters declared by the spec: `USDC`, `nextRetainerId`, `owed`, `totalOwed`, and the six constants (`MIN_WINDOW`, `MAX_WINDOW`, `MIN_NOTICE`, `MAX_NOTICE`, `MAX_PENDING_CLAIMS`, `MAX_TEXT_BYTES`).

Internal only: deposit routine (6.3), `_send` (6.4), payout routine (6.10). No `receive`, no `fallback`, no owner, no extra surface. 13 events and 24 errors exactly as in sections 10 and 11, declared inside the contract so tests can use `UnlessRetainer.X.selector`.

## 3. Planned file paths (adapted to this scaffold)

This workspace's `foundry.toml` sets `src = contracts`, `test = contracts/test`, `script = contracts/script`, solc 0.8.28 (fits `^0.8.24`), cancun, optimizer 200 runs. OpenZeppelin 5.6.1 resolves from `node_modules` via `remappings.txt`. I keep those paths and treat CLAUDE.md section 4 as the mapping below.

| CLAUDE.md path | Workspace path |
|---|---|
| `contracts/UnlessRetainer.sol` | same |
| `test/UnlessRetainer.t.sol` | `contracts/test/UnlessRetainer.t.sol` |
| `test/UnlessRetainer.invariant.t.sol` | `contracts/test/UnlessRetainer.invariant.t.sol` |
| `test/UnlessRetainer.fork.t.sol` | `contracts/test/UnlessRetainer.fork.t.sol` |
| `test/mocks/*` | `contracts/test/mocks/MockUSDC.sol`, `BlocklistUSDC.sol`, `FalseReturnUSDC.sol`, plus `FeeOnTransferUSDC.sol` (see conflict 6) |
| `script/Deploy.s.sol` | `contracts/script/Deploy.s.sol` (import becomes `../UnlessRetainer.sol`) |
| `src/config/chains.ts`, `contracts.ts` | `src/config/chains.ts`, `src/config/contracts.ts` (but see conflict 11) |
| `src/lib`, `hooks`, `components`, `routes` | same under `src/` |
| `deployments/`, `evidence/` | repo root, as written |

Also: add an `[invariant]` block to `foundry.toml` (runs 256, depth 128, fail_on_revert false). Existing scaffold files `contracts/script/Create2Factory.sol` and `DeployCreate2.s.sol` stay untouched. Commands use plain `forge` (no `arc-forge` here).

## 4. Conflicts and ambiguities

**Blocking or money-relevant (I want your ruling before P1):**

1. **Unknown claim id on state-changing calls.** Sections 6.6 to 6.9 say only "claim status == Pending (`ClaimNotPending`)". A nonexistent claim has status `None`, so it would revert `ClaimNotPending` ("already resolved"). `ClaimNotFound` is specified only for `getClaim`, and test 4.5 lists "unknown claim" without naming the error. Proposal: revert `ClaimNotFound` when `claimId >= claimCount` in all claim functions (existence first, per section 12).
2. **Check ordering contradicts section 12 in three places.** Section 12 says existence, authorization, phase, arguments, state, balance. But `deposit` lists ZeroAmount before RetainerEnded; `requestWithdrawal` lists WithdrawalAlreadyPending before ZeroAmount; `objectToClaim` lists ObjectionWindowClosed before TextTooLong. Tests assert exact errors, so this matters. Proposal: follow each function's explicit Pre list (it is more specific), and write tests to match.
3. **Invariant count.** CLAUDE.md Gate 0 says "five contract invariants". Spec section 8, 04-TEST-PLAN and P0 all say eight. Treating eight as correct.
4. **I-7 has no test.** Spec says the suite encodes each invariant, but 04-TEST-PLAN section 3.2 lists I1 to I6, I8 and a ghost check, with no `invariant_I7_*`. I will add one.
5. **"Zero warnings" vs empty-body skeleton (P1).** Reverting stubs with named parameters trigger unused-parameter and mutability warnings. I will use unnamed parameters or minimal references in the skeleton to keep Gate 1 true.
6. **`DepositMismatch` needs a mock nobody listed.** 04-TEST-PLAN 4.3 requires a fee-on-transfer mock, but P2, section 2.1 and CLAUDE.md list only MockUSDC, BlocklistUSDC and FalseReturnUSDC. I will add `FeeOnTransferUSDC.sol` as a test double (stays under `contracts/test`).
7. **REJECTED (see section 0).** ~~Bytecode-match fragility.~~ Original proposal, kept for the record: Runbook section 6 requires identical runtime bytecode on testnet and mainnet, but the compiler metadata hash embeds source paths and settings, and a re-export may change remappings. Proposal: add `bytecode_hash = "none"` and `cbor_metadata = false` to `foundry.toml` now, before the first deploy, since the runbook forbids changing it afterwards. This does not alter logic.

**Lesser ambiguities (I will resolve as stated unless you object):**

8. **Constant types.** Section 3 allows uint256 or smaller. I will use `uint256 public constant`.
9. **Zero-payout withdrawal edge.** `withdrawRemainder` reverts `ZeroAmount` when available is 0, so a client cannot use it to clear a pending withdrawal in that case. `completeWithdrawal` can still clear it. Left as specified.
10. **`TextTooLong` copy.** The limit is 280 bytes, but the error-map message says "280 characters". Multibyte text will hit it earlier. I will word the UI as "280 bytes" with the live byte counter.
11. **Frontend vs scaffold.**
    - The scaffold already has `src/config.ts` (wagmi) and generated `@/onchain-facts` and `@/onchain-money`. Docs 05 section 2 hand-write chain ids, RPC URLs, the USDC address and `parseUnits(..., 6)`. I will read chain and USDC facts from `@/onchain-facts` and amounts via `@/onchain-money` instead of retyping them. Their values match the docs (5042 / 5042002, `rpc.mainnet.arc.io` / `rpc.testnet.arc.io`, explorers `explorer.arc.io` / `explorer.testnet.arc.io`, USDC `0x3600...0000`).
    - A `src/config/` folder next to `src/config.ts` is confusing for imports. Proposal: keep `src/config.ts` for wagmi and put the app's chain and contract settings in `src/config/chains.ts` and `src/config/contracts.ts` only if imports stay unambiguous; otherwise `src/app-config/`.
    - The wagmi config currently lists Arc testnet only (plus Ethereum for ENS). Mainnet support (VITE_NETWORK) needs it added.
12. **Vocabulary leaks.** Product doc bans "contract" in UI copy, yet 05 asks for a "contract link" and the error map says "Contract misconfigured". CLAUDE.md says reserved money is "locked", which the vocabulary table lists as a banned term. Fine in internal docs; I will use "reserved" and "retainer" in UI copy.
13. **Dates.** CLAUDE.md says the grant deadline is November 1, 2026. 01-PRODUCT section 7 says "by Oct 30", and 06 says verify funding "before Oct 27". Today is Oct 25, so the shortest deadline is the working one.
14. **Mainnet work.** The runbook has mainnet config (`VITE_NETWORK=mainnet`, mainnet RPC, mainnet deploy). Arc Studio is testnet-only: I will build and deploy on Arc testnet. Before I write any mainnet config or mainnet deploy step I must show you a required warning and get your confirmation first. Mainnet deploy and transactions happen outside Studio, by you.
15. **Receipts of unverified items.** Items marked NEEDS VERIFICATION in 06 that my work touches: explorer URL paths (`/tx`, `/address`), fork-test USDC funding cheats, and Arc-specific ERC-20 revert errors for the "allowance/balance" message. I will not rely on them: explorer links will use the `@/onchain-facts` helpers, and fork tests stay optional.
16. **CEI exception in `createRetainer`.** The spec itself notes the deposit routine updates `balance` after the `transferFrom`. That is a deliberate, documented exception to CLAUDE.md rule 8 (`nonReentrant` still applies). Implemented as specified.
