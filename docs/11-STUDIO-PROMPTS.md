# 11 — Arc Studio Prompt Sequence

These are the prompts that drive Arc Studio from empty workspace to deployed testnet app. Each prompt is **one focused change**. After each, review the diff against the spec, run tests, save evidence, then move on.

Use them in the Studio browser chat, or from Claude Code via the CLI:
```
arc-studio run "$(cat prompts/P1.txt)" --output json > evidence/studio/p1-contract.json
```
(Confirm exact CLI syntax with `arc-studio --help` and record the version.)

## How to get these docs into Studio (do this first)

Studio's agent can only follow the spec if the spec is in the workspace.

- **Preferred:** push this design pack (`CLAUDE.md` + `docs/`) to a new public GitHub repo, then start the Studio workspace from it (Studio CLI supports importing a public repo server-side; verify the command, e.g. `arc-studio clone <repo-url>`).
- **Fallback:** create the workspace, then prompt Studio: "Create the following files exactly as given" and paste each doc. Large pastes may need splitting.

Either way, the first Studio prompt confirms Studio can read the docs.

---

## P0 — Orientation

```
Read CLAUDE.md and every file in docs/ in the order listed in CLAUDE.md section 2.
Do not write code yet. Reply with:
1) the eight invariants from docs/03-CONTRACT-SPEC.md section 8 in your own words,
2) the exact list of external functions you will implement,
3) your planned file paths, adapted to this workspace's scaffold,
4) any conflicts or ambiguities you found in the docs.
```
**Accept when:** the answer matches the spec with no invented functions. Resolve any conflicts in the docs before P1.

## P1 — Contract skeleton

```
Create contracts/UnlessRetainer.sol implementing ONLY the declarations from docs/03-CONTRACT-SPEC.md:
constructor and immutable USDC, constants (section 3), enums and structs (section 4),
state variables, all events (section 10), all custom errors (section 11), and every external
and view function signature (sections 6 and 7) with empty bodies that revert.
Use OpenZeppelin ReentrancyGuard, SafeERC20, IERC20. Pin the Solidity version in foundry.toml.
No receive or fallback. No owner. It must compile with zero warnings.
```

## P2 — Mocks and test scaffold

```
Create test/mocks/MockUSDC.sol (6 decimals, public mint), test/mocks/BlocklistUSDC.sol
(transfer and transferFrom revert when sender or recipient is blocked), and
test/mocks/FalseReturnUSDC.sol (transfer returns false for blocked recipients),
per docs/04-TEST-PLAN.md section 2.1.
Create test/UnlessRetainer.t.sol with setUp() using the actors and default parameters in
section 2.2 and 2.3. Add one passing test: constructor sets USDC.
```

## P3a — Implement: create, deposit, claims

```
Implement createRetainer, deposit (with the balance-delta check from section 6.3),
fileClaim, approveClaim, objectToClaim, cancelClaim, payOutClaim, and the internal payout
routine (6.10) and _send credit-fallback routine (6.4) exactly as specified in
docs/03-CONTRACT-SPEC.md. Follow the check ordering in section 12.
Then write the unit tests for these functions listed in docs/04-TEST-PLAN.md sections
4.1 to 4.8 and 4.12. Assert exact error selectors and full events. Run the tests and show
the output.
```

## P3b — Implement: withdrawals, end, owed

```
Implement requestWithdrawal, cancelWithdrawal, completeWithdrawal, withdrawRemainder,
extendEndTime, withdrawOwed, and all view functions (section 7) exactly as specified.
Then write the tests in docs/04-TEST-PLAN.md sections 4.9, 4.10, 4.11, 4.13, 4.14.
Run the full test suite and show the output.
```

## P4 — Worked example and invariants

```
Add test_workedExample_matchesSpecTable that replays docs/03-CONTRACT-SPEC.md section 14
row by row and asserts balance, reserved, available, and party balances after every row.
Then create test/UnlessRetainer.invariant.t.sol with the handler and the invariants in
docs/04-TEST-PLAN.md section 3, using the configuration in 3.3. Add the stateless fuzz tests
in 4.16. Run everything, then run coverage, and show both outputs.
```
**Accept when:** all pass; coverage meets 04-TEST-PLAN §5 targets. Save output to `evidence/test-output.txt` and `evidence/coverage.txt`.

## P5 — Deploy to testnet

```
Create script/Deploy.s.sol exactly as in docs/07-DEPLOYMENT-RUNBOOK.md section 5.1.
Deploy UnlessRetainer to Arc testnet with constructor argument
0x3600000000000000000000000000000000000000. Report the contract address, deployment
transaction hash, and explorer link. Write deployments/arc-testnet.json in the shape given in
docs/07-DEPLOYMENT-RUNBOOK.md section 3, including the compiler settings from foundry.toml.
```

## P6 — App foundation

```
Build the app foundation per docs/05-FRONTEND-SPEC.md: chain config (2.1), contract config
(2.2) using the testnet address from deployments/arc-testnet.json, amount helpers (2.3),
hash routing for the four routes (3), wallet connection, network badge, network guard (6.5),
fee floor (6.3), chain-time hook (8), and the full error map (7) derived from the contract ABI
so the build fails if any error lacks a message. Apply the design tokens and fonts in 5.2.
Render placeholder-free empty states for every route.
```

## P7 — Create retainer screen

```
Implement the Create retainer screen per docs/05-FRONTEND-SPEC.md section 4.2: fields,
presets (including "5 minutes (demo)"), validation, the live summary sentence, exact-amount
approval (6.4) skipped when allowance suffices, simulate-before-send (6.2), and the
transaction lifecycle states (6.1). On success navigate to the retainer page.
```

## P8 — Retainer page

```
Implement the Retainer page per docs/05-FRONTEND-SPEC.md section 4.3: summary panel with
perforated edge, notice banner, client panel, freelancer panel, everyone actions, owed banner,
the claims list with every state in the claim-row table, and the activity timeline (8).
Implement the fuse exactly as in section 5.3, including reduced-motion behavior.
Every button names its action and amount.
```

## P9 — Home and My retainers, then full testnet pass

```
Implement Home (4.1) and My retainers (4.4). Then walk through docs/04-TEST-PLAN.md section 7
on Arc testnet in the preview with two wallets and list every transaction hash.
Fix any bug you find and re-run the affected steps.
```
**Accept when:** Gate 3 and Gate 4 in CLAUDE.md pass. Save `evidence/testnet-runbook.md`.

## P10 — README and push

```
Write README.md from the template in docs/08-EVIDENCE-AND-SUBMISSION.md section 4, filling
everything known so far and leaving mainnet fields as TODO. Add .env.example with
VITE_NETWORK, VITE_RETAINER_TESTNET, VITE_RETAINER_MAINNET. Ensure .env is gitignored.
Push the workspace to the connected GitHub repository and report the commit hash.
```

After P10, leave Studio for mainnet deployment (07-DEPLOYMENT-RUNBOOK §5). Return to Studio for any code change (then redeploy and redo the bytecode match).

---

## Prompting rules that make Studio output better

1. **Reference sections, not vibes.** "Implement 6.13 exactly" beats "add withdrawals".
2. **Ask for test output every time.** It's evidence and it catches regressions.
3. **One concern per prompt.** If a diff touches files the prompt didn't mention, ask why before accepting.
4. **Correct with specifics.** "In completeWithdrawal, payout must be min(requested, available); you used requested" — not "fix withdrawals".
5. **Freeze the contract after P5** unless a bug is found. Every contract change after testnet deployment means redeploying testnet and redoing the bytecode match.
