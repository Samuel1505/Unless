# 08 — Evidence and Submission

Reviewers screen for completeness, verify on Arc mainnet, then score. This file makes each rubric criterion verifiable in under a minute.

## 1. What reviewers must be able to verify

| Rubric criterion (weight) | What they check | Where we prove it |
|---|---|---|
| Real USDC on mainnet (30%) | Contract address; tx hashes; USDC moving through the contract between parties | README evidence table (§3) with explorer links; the silent-payout tx featured first |
| Studio across the build (25%) | Studio project URL; contracts *and tests* *and app* built there | Project URL; Studio screenshots/JSON in `evidence/studio/`; video segment; bytecode-match file |
| Working product (25%) | Live app that works | Public URL; demo retainer page they can open without a wallet |
| Potential (20%) | Credible path beyond the grant | README "What's next" (§4.6) |

## 2. Evidence folder contents (all committed)

```
evidence/
├── studio/
│   ├── project-url.txt
│   ├── cli-version.txt
│   ├── p1-contract.json … p10-push.json     ← CLI outputs per prompt (if CLI used)
│   └── screenshots/                         ← one per phase, timestamp visible
├── testnet-runbook.md                       ← every flow, tx hash, screenshot
├── coverage.txt
├── test-output.txt                          ← full test run from Studio terminal
├── slither.txt                              ← if available
├── toolchain.txt
├── bytecode-match.txt
├── mainnet-transactions.md                  ← evidence table (copy of README §3)
└── app-url.txt
```

## 3. Mainnet evidence table (fill during the demo)

| # | Step | Actor | USDC movement | Tx hash |
|---|---|---|---|---|
| 0 | Deploy `UnlessRetainer` | Deployer | — | `0x…` |
| 1 | Approve 10 USDC | Client | — | `0x…` |
| 2 | Create retainer and deposit 10 USDC | Client | Client → contract 10.00 | `0x…` |
| 3 | File claim #0 for 3 USDC | Freelancer | — (3.00 reserved) | `0x…` |
| 4 | **Pay out claim #0 with no client action** | Anyone | Contract → freelancer 3.00 | `0x…` |
| 5 | File claim #1 for 2 USDC | Freelancer | — | `0x…` |
| 6 | Object to claim #1 | Client | — (2.00 unreserved) | `0x…` |
| 7 | Request withdrawal of 7 USDC | Client | — | `0x…` |
| 8 | File claim #2 for 1 USDC during notice | Freelancer | — | `0x…` |
| 9 | Approve claim #2 now | Client | Contract → freelancer 1.00 | `0x…` |
| 10 | Complete withdrawal | Anyone | Contract → client 6.00 | `0x…` |

Each hash links to `https://explorer.arc.io/tx/<hash>` (verify path format). Below the table, state the reconciliation: deposited 10.00 = paid 4.00 + returned 6.00 + balance 0.00.

The submission form asks for **one example transaction hash**: use **row 4**. It is the product in one transaction.

## 4. README template

```markdown
# Unless

Claims pay out unless the client objects.

A client prefunds a USDC retainer for a freelancer. The freelancer files a claim for finished work,
and it pays out automatically when the objection window ends — unless the client objects first.
Built in Arc Studio. Live on Arc mainnet.

- Live app: <url>
- Arc Studio project: https://studio.arc.io/app/<id>
- Contract (Arc mainnet): [`0x…`](https://explorer.arc.io/address/0x…)
- Video walkthrough: <url>
- Demo retainer: <url>/#/r/0

## The problem
<3–4 sentences: late payment, the permission root cause, why retainers fail today>

## How it works
1. The client funds a retainer for one freelancer.
2. The freelancer files a claim with an amount and a note.
3. The client can approve it now or object within the window.
4. If the client does nothing, anyone can pay it out when the window ends.
5. Taking money back needs notice, and claims filed during notice still get paid.

## Proof on Arc mainnet
<evidence table from §3>

## How Arc Studio was used
- Contracts: <what was prompted, how many iterations, what was reviewed>
- Tests: <N unit tests, invariant suite, coverage %> — output in `evidence/test-output.txt`
- App: <screens built in Studio>
- Testnet: deployed from Studio at `0x…` (tx `0x…`)
- Mainnet: same commit deployed with Arc Foundry. Runtime bytecode hash is identical on testnet and mainnet:
  `<hash>` — see `evidence/bytecode-match.txt`

## Design decisions
<3 bullets linking to docs/10-DECISIONS.md: immutable, ERC-20-only accounting, credit fallback>

## Limitations
- No arbiter: a client can object to any claim. Objections are public and permanent.
- Notes are self-reported; the contract proves timing and money, not work quality.
- Unaudited. Use small amounts.

## What's next
- Optional arbiter chosen at creation, with an appeal window
- Recurring top-ups and claim schedules for monthly retainers
- Team retainers: one client, several freelancers
- Shareable claim receipts for accounting and tax records
- Notifications when a claim is filed or about to pay out

## Run it yourself
<build, test, deploy commands from docs/07>

## License
MIT
```

## 5. Description field (submission form)

Target 120–180 words. Structure: problem (1 sentence) → mechanism (2 sentences) → what's onchain (1 sentence) → how Studio was used (2–3 sentences) → what's next (1 sentence).

> Freelancers wait to be paid because every payment needs the client to say yes. Unless flips the default: a client prefunds a USDC retainer, the freelancer files claims for finished work, and each claim pays out automatically when its objection window ends unless the client objects. Reserved money is locked, and the client can only take unreserved money back after a notice period, during which the freelancer can still claim for work already done. Everything runs through one immutable contract on Arc mainnet; the featured transaction is a payout the client never approved. I built the contract, a full unit and invariant test suite, and the app in Arc Studio, deployed to testnet from Studio, then deployed the same commit to mainnet with Arc Foundry — the runtime bytecode hashes match. Next: an optional arbiter and recurring retainers.

## 6. Submission checklist

- [ ] Arc Studio project URL (`https://studio.arc.io/app/…`)
- [ ] Live app link (public, works without a wallet for viewing)
- [ ] Contract address with explorer.arc.io link
- [ ] One example tx hash with explorer link (row 4)
- [ ] Public repo pushed from Studio, README complete
- [ ] Video walkthrough showing the Studio build and the mainnet transaction
- [ ] Short description (§5)
- [ ] Public builder profile (GitHub, X, or Farcaster) linked
- [ ] Re-open every link from a logged-out browser before submitting

## 7. Pre-submission self-review (as a skeptical reviewer)

- Can I see USDC move from the contract to a wallet **other than the client** without the client approving? (row 4)
- Do the testnet and mainnet bytecode hashes actually match?
- Does the video show Studio writing tests, not just contracts?
- Does the live app's demo retainer page load without a wallet?
- Is anything in the README claimed but not linked?
