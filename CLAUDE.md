# CLAUDE.md — Unless

> Operating manual for any coding agent (Arc Studio's agent, Claude Code driving the Arc Studio CLI, or a human) working on this repository. Read this file fully before touching code. It is the source of truth for *how* we work; the files in `docs/` are the source of truth for *what* we build.

---

## 1. What we are building, in one paragraph

**Unless** is a retainer for freelancers that pays by default. A client prefunds a USDC retainer for a named freelancer. The freelancer files a claim for finished work. The claim pays out automatically when its objection window expires **unless** the client objects first. The client can also approve a claim instantly. Money reserved by a pending claim is locked, and the client can only take unreserved money back after a withdrawal notice period, during which the freelancer can still claim for work already done. Everything runs through one immutable smart contract on Arc mainnet and one static web app. There is no backend.

The product exists to win an **Arc Microgrants: Built with Arc Studio** grant (deadline November 1, 2026) and to be a credible seed of a real product afterwards. Both goals matter; neither excuses sloppiness.

## 2. Read order

Read these before writing code, in this order. Do not skim the contract spec.

| # | File | Why you need it |
|---|---|---|
| 1 | `CLAUDE.md` (this file) | Rules of engagement, workflow, definition of done |
| 2 | `docs/01-PRODUCT.md` | Users, problem, flows, vocabulary, scope boundaries |
| 3 | `docs/02-ARCHITECTURE.md` | System shape, trust model, threat model, failure modes |
| 4 | `docs/03-CONTRACT-SPEC.md` | **Normative** contract specification: storage, state machine, every function, every invariant |
| 5 | `docs/04-TEST-PLAN.md` | Required tests, invariant suite, coverage matrix |
| 6 | `docs/05-FRONTEND-SPEC.md` | Screens, components, chain config, transaction UX, design system |
| 7 | `docs/06-ARC-PLATFORM-NOTES.md` | Arc-specific behavior that breaks normal EVM assumptions |
| 8 | `docs/07-DEPLOYMENT-RUNBOOK.md` | Testnet in Studio, export, mainnet deploy, hosting |
| 9 | `docs/08-EVIDENCE-AND-SUBMISSION.md` | What the grant reviewers must be able to verify, README template |
| 10 | `docs/09-DEMO-SCRIPT.md` | Mainnet transaction script and video script |
| 11 | `docs/10-DECISIONS.md` | Architecture decision records: why things are the way they are |
| 12 | `docs/11-STUDIO-PROMPTS.md` | The sequenced prompts used to drive Arc Studio |

If two documents disagree, the precedence is: **03-CONTRACT-SPEC > 06-ARC-PLATFORM-NOTES > 02-ARCHITECTURE > 05-FRONTEND-SPEC > everything else**. Report the conflict; do not silently pick one.

## 3. Non-negotiable rules

These are hard constraints. Violating one is a failed task even if the code works.

### 3.1 Grant eligibility rules

1. **Everything is built in Arc Studio.** Contracts, tests, and the app are authored inside the Studio workspace (browser or via the `arc-studio` CLI). The Studio project URL is how reviewers confirm this. If you are Claude Code working locally, you make changes **by sending prompts to Arc Studio through its CLI**, not by editing files locally and pushing around Studio. See §6.
2. **Mainnet deployment happens outside Studio** (Studio is testnet-only by its Terms of Use) using Arc Foundry (`arc-forge`) with the builder's own key, deploying the **exact same source and compiler settings** Studio used on testnet. See `docs/07-DEPLOYMENT-RUNBOOK.md`.
3. **Real USDC must move through the contract and the app on Arc mainnet.** A transfer that bypasses the contract does not count.
4. **No mocks, placeholders, or simulated results in the shipped app.** Test doubles live only in `test/`.

### 3.2 Engineering rules

5. **The contract is immutable.** No owner, no admin, no pause, no proxy, no upgrade path, no fee. See ADR-004.
6. **USDC accounting uses only the 6-decimal ERC-20 interface** at `0x3600000000000000000000000000000000000000`. The contract never reads `msg.value`, never reads `address(this).balance`, and has no `receive()` or `fallback()`. Arc's native (18-decimal) and ERC-20 (6-decimal) USDC share one balance; mixing them is off by 10¹². See ADR-002.
7. **No loops over unbounded data in state-changing functions.** Aggregates (`reserved`, `balance`, counters) are maintained incrementally.
8. **Checks-effects-interactions plus `nonReentrant` on every state-changing external function.**
9. **Outbound payments never revert the caller's action because the recipient cannot receive.** Use the push-with-credit-fallback pattern from the spec (§6.4 of 03-CONTRACT-SPEC). A blocklisted recipient must not freeze a retainer.
10. **Exact approvals only.** The app requests USDC approval for the exact amount being deposited, never `type(uint256).max`.
11. **Every transaction the app sends sets `maxFeePerGas ≥ 20 gwei`.** Arc's mempool silently drops anything lower.
12. **Custom errors, not revert strings.** Every error in the spec exists in code with the same name and is mapped to a human message in the app.

### 3.3 Product rules

13. **The vocabulary in `docs/01-PRODUCT.md` §6 is binding** in UI copy, event names, function names, and docs. A "claim" is never called an "invoice" in one place and a "draw" in another.
14. **Scope is fixed.** The out-of-scope list in `docs/01-PRODUCT.md` §8 is not a backlog for this deadline. If you think something out of scope is necessary, stop and ask.

## 4. Repository layout

Arc Studio scaffolds a **Vite + Foundry** workspace. **Do not fight the scaffold.** If Studio's default paths differ from those below, keep Studio's paths and update this table in the same change.

```
/
├── CLAUDE.md                     ← this file
├── README.md                     ← public README (template in docs/08)
├── docs/                         ← specifications (this design pack)
├── foundry.toml                  ← Studio scaffold: src=contracts, test=contracts/test, script=contracts/script
├── contracts/
│   ├── UnlessRetainer.sol        ← the only production contract
│   ├── test/
│   │   ├── UnlessRetainer.t.sol      ← unit tests
│   │   ├── UnlessRetainer.invariant.t.sol ← invariant suite + handler
│   │   ├── UnlessRetainer.fork.t.sol ← optional fork tests against real Arc USDC
│   │   └── mocks/
│   │       ├── MockUSDC.sol          ← 6-decimal ERC-20 for local tests
│   │       ├── BlocklistUSDC.sol     ← MockUSDC that reverts transfers to listed addresses
│   │       ├── FalseReturnUSDC.sol   ← MockUSDC whose transfer returns false for listed recipients
│   │       └── FeeOnTransferUSDC.sol ← MockUSDC that delivers less than requested (DepositMismatch)
│   └── script/
│       ├── Deploy.s.sol              ← deployment script (testnet and mainnet)
│       └── Create2Factory.sol, DeployCreate2.s.sol ← Studio scaffold files, untouched
├── src/  (or app/)               ← Vite frontend, whatever Studio scaffolds
│   ├── config/chains.ts          ← Arc mainnet + testnet chain definitions
│   ├── config/contracts.ts       ← per-network contract address + ABI import
│   ├── lib/                      ← formatting, time, errors, explorer links
│   ├── hooks/                    ← data + transaction hooks
│   ├── components/
│   └── routes/
├── deployments/
│   ├── arc-testnet.json          ← address, tx hash, block, compiler settings
│   └── arc-mainnet.json
└── evidence/
    ├── studio/                   ← Studio CLI JSON outputs, screenshots
    ├── mainnet-transactions.md   ← the evidence table (docs/08)
    └── bytecode-match.txt        ← testnet vs mainnet runtime bytecode hashes
```

## 5. Workflow: phases and gates

Work proceeds in phases. **Do not start a phase until the previous gate passes.** Each gate is a checklist that must be fully true.

### Phase 0 — Orientation
- Read all docs in the order of §2.
- Confirm the Studio workspace exists and record its project URL in `evidence/studio/project-url.txt`.
- **Gate 0:** you can state, without looking, the eight contract invariants in 03-CONTRACT-SPEC §8.

### Phase 1 — Contract
- Implement `contracts/UnlessRetainer.sol` exactly per 03-CONTRACT-SPEC.
- **Gate 1:** compiles with zero warnings; every function, event, error, and constant in the spec exists with the specified name and signature; no extra public surface.

### Phase 2 — Tests
- Implement the suites in 04-TEST-PLAN.
- **Gate 2:** all tests pass in the Studio terminal; the coverage matrix in 04-TEST-PLAN §5 is fully ticked; invariant runs complete with the configured depth and zero violations.

### Phase 3 — Testnet deployment (in Studio)
- Deploy from Studio to Arc testnet. Save Studio's deployment output (address, tx hash, explorer URL) to `deployments/arc-testnet.json` and `evidence/studio/`.
- Run the full happy path and objection path manually against testnet.
- **Gate 3:** every flow in 01-PRODUCT §5 executed on testnet with recorded tx hashes.
- *Ruled 2026-10-25:* the deployment half of Phase 3 is done (`deployments/arc-testnet.json`, `evidence/studio/p5-onchain-verification.txt`). The flow runs for Gate 3 are executed through the app at P9 (11-STUDIO-PROMPTS), with two wallets, so Phase 4 starts before Gate 3 closes. Gate 3 and Gate 4 are checked together at P9. The contract stays frozen in the meantime.

### Phase 4 — App
- Build the frontend per 05-FRONTEND-SPEC against the testnet deployment.
- **Gate 4:** every screen and state in 05-FRONTEND-SPEC §4 renders; every custom error has a mapped message; the app works with two different wallets in two browsers.

### Phase 5 — Export and mainnet
- Push from Studio to GitHub. Deploy to mainnet per 07-DEPLOYMENT-RUNBOOK. Host the app.
- **Gate 5:** `evidence/bytecode-match.txt` shows identical runtime bytecode hashes on testnet and mainnet; the hosted app reads the mainnet contract.

### Phase 6 — Evidence and demo
- Execute 09-DEMO-SCRIPT on mainnet. Fill 08-EVIDENCE-AND-SUBMISSION. Record the video.
- **Gate 6:** the submission checklist in 08 §6 is fully ticked.

## 6. Working with Arc Studio (lineage discipline)

Reviewers verify "built in Arc Studio" from the Studio project URL and the video. Our job is to make the lineage unambiguous.

1. **The Studio workspace is the canonical source** until Phase 5 export. Contract and app changes go through Studio.
2. **If you are Claude Code**, delegate changes to Studio with the CLI. The canonical pattern is a single focused prompt per change, requesting JSON output so deployments, diffs, and URLs are captured:
   ```
   arc-studio run "<focused prompt from docs/11-STUDIO-PROMPTS.md>" --output json > evidence/studio/<step>.json
   ```
   Verify exact command names and flags with `arc-studio --help` before first use; record the CLI version in `evidence/studio/cli-version.txt`.
3. **Pull Studio's workspace locally** for review (`arc-studio pull` or the GitHub push) but treat local edits as drafts that must be re-applied through Studio.
4. **Small prompts beat large ones.** One function, one test group, or one screen per prompt. Large prompts produce large unreviewable diffs.
5. **Review every Studio diff against the spec** before accepting it. Studio's agent is good but not authoritative; the spec is.
6. **Capture evidence as you go**: after each phase, save the Studio JSON output and one screenshot to `evidence/studio/`.
7. **Never deploy to mainnet from a local edit that Studio has not seen.** The bytecode-match proof depends on it.

## 7. Commands (verify in the Studio terminal; Studio may use plain `forge`)

```
# build and test (Arc Foundry preferred; plain forge acceptable for unit tests using mocks)
arc-forge build
arc-forge test -vvv
arc-forge test --match-contract UnlessRetainerInvariant -vvv
arc-forge coverage

# fork tests against real Arc USDC (only where network access exists)
arc-forge test --match-contract UnlessRetainerFork --fork-url https://rpc.testnet.arc.io

# read deployed state
arc-cast call $RETAINER "nextRetainerId()(uint256)" --rpc-url $RPC
arc-cast code $RETAINER --rpc-url $RPC | arc-cast keccak
```

Exact Arc Foundry installation and flags: see `docs/07-DEPLOYMENT-RUNBOOK.md` §2. Treat any command you have not run successfully as **unverified**.

## 8. Definition of done (for the whole project)

- [ ] Contract matches spec; all tests and invariants pass; coverage matrix complete.
- [ ] Testnet and mainnet runtime bytecode hashes match.
- [ ] Hosted app on a public URL, reading and writing the mainnet contract.
- [ ] The five-step mainnet demo in 09-DEMO-SCRIPT executed with two distinct wallets; every tx hash recorded.
- [ ] README complete per 08 template; repo public; pushed from Studio.
- [ ] Video recorded per 09-DEMO-SCRIPT §B.
- [ ] Submission checklist ticked.

## 9. Things you must never do

- Never add an owner, admin, pause, fee, or upgrade mechanism.
- Never use `msg.value`, `address(this).balance`, `receive()`, `fallback()`, or `selfdestruct`.
- Never send USDC to `address(0)` or use it as a sentinel recipient (Arc reverts zero-address value transfers).
- Never rely on block randomness (`PREVRANDAO` is always 0 on Arc).
- Never assume strictly increasing timestamps (Arc blocks can share a timestamp).
- Never request unlimited USDC approval from the user.
- Never hardcode a contract address in a component; it comes from `config/contracts.ts`.
- Never ship copy that calls a claim an "invoice", "draw", "payment request", or "milestone".
- Never claim in docs or UI that Arc or Circle audited, endorsed, or reviewed the contract.
- Never commit private keys, mnemonics, or RPC keys. `.env` is gitignored; `.env.example` lists names only.

## 10. When you are unsure

Stop and ask when: the spec is silent on a behavior that changes where money goes; two docs conflict; a Studio change touches more than the prompt asked for; an Arc behavior in 06-ARC-PLATFORM-NOTES is marked **NEEDS VERIFICATION** and your code depends on it. Writing "I assumed X" in a commit message is not a substitute for asking when money paths are involved.
