# 06 — Arc Platform Notes

Arc is EVM-compatible but not EVM-identical. This file lists every Arc behavior that affects this project, with its verification status. Code that depends on a **NEEDS VERIFICATION** item must not ship until the item is verified and this file updated.

Legend: **CONFIRMED** (from official docs or observed on-chain) · **NEEDS VERIFICATION** · **OBSERVED** (seen in community projects, not official).

## 1. Network parameters

| Item | Value | Status | Source |
|---|---|---|---|
| Mainnet chain id | `5042` | CONFIRMED | docs.arc.io "Connect to Arc"; ethereum-lists |
| Testnet chain id | `5042002` | CONFIRMED | same |
| Mainnet RPC | `https://rpc.mainnet.arc.io` (provider RPCs also exist) | CONFIRMED in guides; Arc's reference reportedly labels listed endpoints "permissioned" | datawallet.com guide; docs.bitquery.io |
| Testnet RPC | `https://rpc.testnet.arc.io` (older docs show `rpc.testnet.arc.network`) | NEEDS VERIFICATION which is current | docs.arc.io |
| Mainnet explorer | `https://explorer.arc.io` | CONFIRMED | same |
| Explorer URL paths | `/tx/<hash>`, `/address/<addr>` | NEEDS VERIFICATION | — |
| Contract source verification | Sourcify (used by community projects) | OBSERVED | github.com/Sofiia7/ARC |
| Native gas token | USDC (18 decimals at protocol level) | CONFIRMED | docs.arc.io EVM differences |
| Finality | Deterministic, sub-second; one confirmation is final | CONFIRMED | docs.arc.io |

**Action before Phase 5:** open docs.arc.io "Connect to Arc", re-check every row above, and update this table with the date checked.

## 2. USDC

| Item | Value | Status |
|---|---|---|
| ERC-20 interface address (mainnet and testnet) | `0x3600000000000000000000000000000000000000` | CONFIRMED |
| ERC-20 decimals | 6 | CONFIRMED |
| Native vs ERC-20 | One shared balance; native reads are 18 dp, ERC-20 reads are 6 dp | CONFIRMED |
| Wrapped USDC | Does not exist; do not wrap | CONFIRMED |
| Unified Transfer event | Native sends and ERC-20 transfers both emit `Transfer` on the USDC contract | CONFIRMED (docs.arc.io deposits guide) |
| Blocklist | Transfers to/from blocklisted addresses revert at runtime and consume gas | CONFIRMED |
| Transfer hooks | ERC-20 transfers credit a contract without running its code | CONFIRMED |
| Permit / EIP-2612 on the ERC-20 interface | — | NEEDS VERIFICATION (not used in v1) |

### Consequences for this project
- The contract uses `IERC20(0x3600…0000)` exclusively. No `msg.value`, no `address(this).balance`.
- Because transfers into the contract don't execute code, the contract cannot "notice" stray deposits. That is fine: accounting is ledger-based and invariant I-3 is `≥`.
- Blocklisting is the reason for the credit-fallback payout routine.

## 3. EVM differences that matter here

| Behavior | Status | What we do |
|---|---|---|
| Value transfer to `address(0)` reverts | CONFIRMED | Never send to zero; validate addresses |
| Burning is forbidden | CONFIRMED | No burn semantics anywhere |
| `PREVRANDAO` returns 0 | CONFIRMED | No randomness used |
| Timestamps non-decreasing, 1 s granularity; sub-second blocks may share a timestamp | CONFIRMED | All comparisons are `<` / `≥` against stored times; tests cover equal-timestamp boundaries |
| Mempool silently drops `maxFeePerGas < 20 gwei` | CONFIRMED | App enforces fee floor |
| `SELFDESTRUCT` moves native USDC and some patterns revert | CONFIRMED | Not used |
| Stock `anvil` does not emulate Arc precompiles; use Arc Foundry (`arc-anvil`, `arc-forge`, `arc-cast`) | CONFIRMED | Unit tests use mocks; fork tests use Arc Foundry |
| EIP-7702 delegated EOAs supported | CONFIRMED | Not relied on; a 7702-delegated client is just another caller |

## 4. Arc Studio

| Item | Status | Notes |
|---|---|---|
| Studio builds, tests, previews, deploys to **testnet** | CONFIRMED | docs.arc.io/ai/arc-studio |
| Studio does **not** deploy to mainnet, send mainnet txs, or host apps | CONFIRMED | studio.arc.io/terms-of-use |
| Sandbox is a Vite + Foundry app | CONFIRMED | docs.arc.io/ai/arc-studio-cli |
| Push to GitHub from Studio | CONFIRMED | docs.arc.io/ai/arc-studio |
| CLI with JSON output including deployments, diffs, preview URL, workspace URL | CONFIRMED | docs.arc.io/ai/arc-studio-cli |
| Foundry tests run in Studio terminal | NEEDS VERIFICATION | First action of Phase 2 |
| Arc Foundry available inside Studio sandbox | NEEDS VERIFICATION | If not, unit tests with mocks still run on plain Foundry |
| Env vars / secrets in Studio | NEEDS VERIFICATION (assume none) | App needs only public build-time vars |
| Usage limits may change without notice | CONFIRMED | Do Studio work early |
| Deploy turns can take 5–20 minutes | CONFIRMED | Budget time |

### Grant-specific Studio requirements (from the Round 2 page)
- Contracts **written and tested in Arc Studio** and deployed to Arc mainnet.
- App **built in Arc Studio**, live at a public link, calling those contracts.
- Studio project URL (format `https://studio.arc.io/app/<id>`) is how reviewers confirm the project was built in Studio.
- Video must show the build in Studio and the mainnet transaction.

## 5. Agent and payment infrastructure we deliberately do not use

| Component | Why not |
|---|---|
| Memo contract | Requires direct EOA calls; notes live in our own events instead |
| Multicall3From | Not needed |
| ERC-8004 / ERC-8183 | Agent identity and job standards; not this product |
| Circle Gateway / Nanopayments | Off-chain batching; we need contract-mediated USDC |
| StableFX | Permissioned; USDC only |
| Paymasters / gas sponsorship | Out of scope; both parties hold USDC anyway |

## 6. Funding the demo

- Both demo wallets need USDC on Arc mainnet. Budget: ~11 USDC for the script (03-CONTRACT-SPEC §14) plus gas (cents) plus margin → **15 USDC** on the client wallet, **0.5 USDC** on the freelancer wallet (gas only), **0.5 USDC** on a third "anyone" wallet if used.
- Sources: an exchange supporting USDC withdrawals on Arc, or CCTP from another chain (Arc CCTP domain 26). Verify the route before Oct 27.
