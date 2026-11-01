# Testnet runbook (Gate 3 + Gate 4)

Network: Arc testnet (chain 5042002) · Contract: `0x54414913081adb0d95b0f5aedc6a4c8a8d85c821`
App: Studio preview at https://studio.arc.io/app/c5d3671f-867d-4c48-84c4-ba21f92f8020
Steps: docs/04-TEST-PLAN.md §7, extended to cover every flow in docs/01-PRODUCT.md §5 (F1–F13).

| Role | Browser profile | Address |
|---|---|---|
| Client | A | `0x89a68d0731F9Bc419d606f1F31Ead04c3fBDFdd6` (27.39 test USDC at start) |
| Freelancer | B | `0xe98540d28F45830E01D237251Bfc4777E69c9A46` (29.97 test USDC at start) |

Funding: the client needs at least 12 testnet USDC (10 + 1 deposits, plus gas). The freelancer needs a little for gas.

## Retainer A: 5-minute demo window, 5-minute notice, end date at least a week out

Expected balances are for retainer A after the step.

| # | Flow | Who | Action | Expected after | Tx hash | Verified on chain |
|---|---|---|---|---|---|---|
| 1 | F1 | Client | Create, fund 10 USDC (approve 10, then create) | balance 10 · available 10 | approve `0x4537f82a8dd237346618298ceb763f508987efc8717151e23d6fe539c2d373fd` (block 69101396) · create `0xdeafc3e4ef8b741121e6afbb616609d0e992a8f123c02dd05b8a1c6646919f11` (block 69101697) | ✅ retainer 0: client and freelancer correct, window 300 s, notice 324 s, balance 10.00, available 10.00; allowance was exactly 10.00 |
| 2 | F3 | Freelancer | File a claim for 3 USDC | reserved 3 · available 7 | `0x91445097ee550dce76bf50e9d66db8f4f2a638cd1a8e370ed53762cc18e350d1` (block 69102206) | ✅ claim 0: 3.00, filed 23:32:05, payableAt 23:37:05 (+300 s), Pending; available 7.00; noteHash = keccak("design work for week 1"); app showed "Ready to pay out" at payableAt |
| 3 | F4 | Freelancer (or anyone) | Wait for the fuse, then **Pay out 3.00 USDC** | balance 7 · reserved 0 · freelancer +3 · `PaidVia.PaidOut` | `0xb8474b952e3499eba9b04110a85dfd9e815c0e80bf9b9d2194402a7f51a9f51f` (block 69103158) | ✅ claim 0 Paid, paidVia PaidOut; `ClaimPaid` + USDC `Transfer`, no `PayoutDeferred`; balance 7.00, reserved 0, totalPaid 3.00; contract holds exactly 7.00 USDC; owed 0 |
| 4a | F3 | Freelancer | File a claim for 2 USDC | reserved 2 | `0x6008c2b86babd8e167f34a9e4dd91d81970cb8c5457378382a82fd7b9ec49cde` (block 69103414) | ✅ claim 1: 2.00, note "extra revision" (from the `ClaimFiled` event), payableAt 1792968436 |
| 4b | F6 | Client | Object with a reason, before the fuse ends | reserved 0 · available 7 · reason shown on the row | `0x345b6214dc5ef2d064564afbb5610237020edd8a20e03964a6ff22566e01ad56` (block 69103534) | ✅ claim 1 Objected at 1792968197, 239 s before payableAt; reason "no aggreed in advance" in `ClaimObjected`; reserved 0, available 7.00; no USDC moved |
| 5 | F8 | Client | Request withdrawal of 7 USDC | readyAt = now + 5 min · available still 7 | `0x1c2cfb0c3aefdbab21a762a4ac292184931502a5068d8025a7bf85c495992393` (block 69104007) | ✅ `WithdrawalRequested`; withdrawalAmount 7.00, readyAt 1792968761 = request time 1792968437 + 324 s notice; available still 7.00 (not reserved) |
| 6a | F3 | Freelancer | File a claim for 1 USDC during the notice | reserved 1 | `0x4db3884b478bbfbc14c50339ee643f8753344dba5804625fa03c891792a481bf` (block 69104613) | ✅ claim 2: 1.00, filed 1792968744, 17 s before readyAt 1792968761, so during the notice |
| 6b | F5 | Client | **Approve 1.00 USDC now** | balance 6 · freelancer +1 (total +4) · `PaidVia.ApprovedNow` | `0x2ce84a5517e5d8e9e144298cfb41df64a8a2354ea7aea51378c524f2a431ded1` (block 69104702) | ✅ claim 2 Paid, paidVia ApprovedNow, 255 s before its payableAt; `ClaimPaid` + `Transfer`; balance 6.00, available 6.00, totalPaid 4.00; withdrawal of 7.00 still pending; contract holds exactly 6.00 |
| 7 | F9 | Freelancer (or anyone) | After the notice, complete the withdrawal | `WithdrawalCompleted(id, 7, 6)` · balance 0 · client +6 | `0xd13441aad7330fb223c71c286692933545fecd0c37723955992d20737fd59314` (block 69104988) | ✅ sent by the freelancer; `WithdrawalCompleted(0, requested 7.00, paid 6.00)`; USDC `Transfer` 6.00 from the contract to the client (Arc also logs the same move at 18 decimals, ADR-002); balance 0, totalReturned 6.00; conservation holds: deposited 10 = 0 + paid 4 + returned 6; contract holds 0 |
| 8 | F2 | Client | Top up 1 USDC (approve 1, then deposit) | balance 1 | | |
| 9a | F8 | Client | Request withdrawal of 1 USDC | withdrawal pending | | |
| 9b | F10 | Client | Cancel withdrawal | no withdrawal pending | | |
| 10a | F3 | Freelancer | File a claim for 0.5 USDC | reserved 0.5 | | |
| 10b | F7 | Freelancer | Cancel own claim | reserved 0 | | |
| 11 | F12 | Client | Extend end date by a day | `EndTimeExtended(old, new)` | | |

## Retainer B: F11 (withdraw remainder after end)

End dates fall at 23:59:59 local time on the chosen day, so retainer B's end date must be today (and more than its 5-minute notice away).

| # | Flow | Who | Action | Expected after | Tx hash | Verified on chain |
|---|---|---|---|---|---|---|
| 12 | F1 | Client | Create retainer B, end date today, fund 0.5 USDC | balance 0.5 | | |
| 13 | F11 | Client | After midnight local time: **Withdraw remainder** | `RemainderWithdrawn(id, 0.5)` · client +0.5 | | |

## F13 (recover deferred payout): not executable on testnet

This flow needs a recipient on Circle's USDC blocklist, which cannot be staged on testnet. It is covered by the unit tests in `contracts/test/UnlessRetainer.Owed.t.sol` and `UnlessRetainer.Fallback.t.sol`, which use `BlocklistUSDC` and `FalseReturnUSDC` (see `evidence/test-output.txt`). The app's owed banner and **Withdraw X USDC owed to you** button were exercised only with sample data.

## Gate 4 checks during the run

- [ ] Both wallets in two separate browser profiles
- [ ] Wrong-network banner appears and switching works
- [ ] Every button named its action and amount
- [ ] Fuse burned down, turned settled at payout, Paid stamp shown
- [ ] Reduced motion (OS setting) makes state changes instant
- [ ] Notes and the objection reason show in full on the claim rows
- [ ] My retainers shows retainer A and B for both wallets with the right next event
- [ ] A rejected wallet prompt shows "Transaction cancelled in your wallet."
- [ ] On a phone: no input zoom, no tap flash, safe areas respected
