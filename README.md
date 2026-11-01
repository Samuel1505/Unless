# Unless

Claims pay out unless the client objects.

A client prefunds a USDC retainer for a freelancer. The freelancer files a claim for finished work, and it pays out automatically when the objection window ends, unless the client objects first. Live on Arc mainnet.

Built with [Arc Studio](https://studio.arc.io)

- Live app: https://unless-nu.vercel.app/ (Vercel, `VITE_NETWORK=mainnet`)
- Arc Studio project: https://studio.arc.io/app/c5d3671f-867d-4c48-84c4-ba21f92f8020
- Contract (Arc mainnet, chain 5042): [`0x766bBE6b3819261F7C1161073551A27362c96047`](https://explorer.arc.io/address/0x766bBE6b3819261F7C1161073551A27362c96047)
- Video walkthrough: link coming shortly
- Demo retainer: https://unless-nu.vercel.app/#/r/0

## The problem

Freelancers are paid late because payment needs the client to act: the work is done, and the freelancer waits for someone else to click pay. In an Upwork/Censuswide study, 81% of offline freelancers had been paid late and spent about 30 hours a year chasing payments; a Freelancers Union/Authors Guild survey found 91% of New York freelancers had been paid late at least once. The usual fix is a retainer, where the client pays in advance, but that moves the risk to the client, who has handed over money and lost control of it, so most clients refuse. The root cause is permission, not cash: every existing payment flow, including escrow, makes the client's approval the trigger. Unless removes approval as the trigger and keeps it only as a veto.

## How it works

1. The client funds a retainer for one freelancer.
2. The freelancer files a claim with an amount and a note.
3. The client can approve it now or object within the objection window.
4. If the client does nothing, anyone can pay it out when the window ends.
5. Taking money back needs notice, and claims filed during the notice still get paid.

## Proof on Arc mainnet

Retainer 0 on Arc mainnet (chain 5042), contract [`0x766bBE6b…6047`](https://explorer.arc.io/address/0x766bBE6b3819261F7C1161073551A27362c96047). **Amounts are one tenth of the original demo script** ([docs/09-DEMO-SCRIPT.md](docs/09-DEMO-SCRIPT.md)); the contract has no minimum amount and the sequence and outcomes are the same. Every row was checked on chain with `cast` on 2026-11-01. Source: [evidence/mainnet-transactions.md](evidence/mainnet-transactions.md).

| Role | Address |
|---|---|
| Client | `0x89a68d0731F9Bc419d606f1F31Ead04c3fBDFdd6` |
| Freelancer | `0xe98540d28F45830E01D237251Bfc4777E69c9A46` |
| Deployer | `0x88aE55a562536862B6ec32784a640AaF0349b859` |

| # | Step | Actor | USDC movement | Tx hash |
|---|---|---|---|---|
| 0 | Deploy `UnlessRetainer` | Deployer | none | [`0x24a7f498…09ce`](https://explorer.arc.io/tx/0x24a7f49850ff628acd68880c611b39921de4366cb7c500fef2da9391225f09ce) |
| 1 | Approve exactly 1.00 USDC | Client | none | [`0x1b61e217…886f`](https://explorer.arc.io/tx/0x1b61e2174bab8e901f93f3bb386030b68c6925bb471d6956cae310518cea886f) |
| 2 | Create retainer 0 and deposit 1.00 USDC | Client | Client to contract 1.00 | [`0x21e2dd8d…2646`](https://explorer.arc.io/tx/0x21e2dd8d2aaec346726ec79b0338f39da7b2ed957652c3be7ec158c930d52646) |
| 3 | File claim #0 for 0.30 USDC | Freelancer | none (0.30 reserved) | [`0xde5f4c35…d795`](https://explorer.arc.io/tx/0xde5f4c359c8000064c3f33fac0a16e2248acdad17f715fbaa1e60fb7d258d795) |
| 4 | **Pay out claim #0 with no client action** | Freelancer | Contract to freelancer 0.30 | [`0x3080138c…9ca5`](https://explorer.arc.io/tx/0x3080138c62f1483ba7ccc702b977343621360fc47bdf0ef47f3b993fd5949ca5) |
| 5 | File claim #1 for 0.20 USDC | Freelancer | none | [`0xba0b76fd…efc9`](https://explorer.arc.io/tx/0xba0b76fdf668a03012f50d326108669ddf3a27ffcf4816ac1097050cfc41efc9) |
| 6 | Object to claim #1 | Client | none (0.20 unreserved) | [`0x09900884…15d2`](https://explorer.arc.io/tx/0x099008842fdb375735dfd4a7756977d712b33fa3bfbc3e67d773c1e5cff915d2) |
| 7 | Request withdrawal of 0.70 USDC | Client | none | [`0x64d57c64…9bfb`](https://explorer.arc.io/tx/0x64d57c641dfcb2c2d0ee8cdb99aeb034b890c0b031ca8180e94d0abd1b049bfb) |
| 8 | File claim #2 for 0.10 USDC during the notice | Freelancer | none | [`0x5c4e0c00…f90d`](https://explorer.arc.io/tx/0x5c4e0c00cb3da73e268909841ab9c62f5b4f0cdc436e1c5a33e969f6bab9f90d) |
| 9 | Approve claim #2 now | Client | Contract to freelancer 0.10 | [`0x993c930f…cdc7`](https://explorer.arc.io/tx/0x993c930f521f1f5c51e853923e85792b4e3c8905f34dbb7eff4caa3de0d9cdc7) |
| 10 | Complete withdrawal | Freelancer (anyone may) | Contract to client 0.60 | [`0xffa11f61…49e0`](https://explorer.arc.io/tx/0xffa11f61c04dcb13bbb560e1283b5d5a7e0c0edbbbe3fb5b6b214f67dffe49e0) |

**Row 4 is the product in one transaction.** [`0x3080138c62f1483ba7ccc702b977343621360fc47bdf0ef47f3b993fd5949ca5`](https://explorer.arc.io/tx/0x3080138c62f1483ba7ccc702b977343621360fc47bdf0ef47f3b993fd5949ca5) moved 0.30 USDC from the contract to the freelancer with no client approval: the client sent no transaction between the claim being filed and it being paid out.

**Reconciliation (retainer 0, read on chain after row 10):** deposited 1.00 = paid 0.40 + returned 0.60 + balance 0.00. The withdrawal event records 0.70 requested and 0.60 paid. The contract holds 0 USDC.

**Timing checks:** claim #0 was paid out at block time 1793544705, 42 s after its `payableAt` 1793544663, with no client transaction in between. The objection (row 6) came 204 s before claim #1's `payableAt`. Claim #2 (row 8) was filed 236 s before the withdrawal's `readyAt` 1793545281.

## How Arc Studio was used

The raw output of each Arc Studio CLI turn is in [evidence/studio/](evidence/studio/).

- **Contract:** Studio wrote `contracts/UnlessRetainer.sol` from [docs/03-CONTRACT-SPEC.md](docs/03-CONTRACT-SPEC.md) over four prompts: P0 (orientation: it found 16 conflicts or ambiguities in the docs, which were ruled on and written back into the spec), P1 (skeleton), P3a and P3b (implementation). Every diff was reviewed against the spec. The follow-up rulings from the implementation are ADR-012 to ADR-014 in [docs/10-DECISIONS.md](docs/10-DECISIONS.md).
- **Tests:** Studio wrote and ran 380 Foundry tests: unit tests, fuzz tests, the spec's worked example, and all 8 invariants (256 runs of depth 128, 32,768 calls each, zero violations). Coverage of `UnlessRetainer.sol` is 100% of lines, statements, branches and functions. Output in [evidence/test-output.txt](evidence/test-output.txt) and [evidence/coverage.txt](evidence/coverage.txt).
- **App:** built in Studio over P6 (foundation, error map, the 20 gwei fee floor, exact-amount approvals), P6b (motion and mobile polish from vendored [Emil Kowalski design references](docs/design-references/emil-kowalski/)), P7 (create retainer), P8 (retainer page, the fuse, the activity timeline), P9 (home and My retainers), and the mainnet configuration.
- **Testnet:** Studio deployed `0x54414913081adb0d95b0f5aedc6a4c8a8d85c821` on Arc testnet (chain 5042002, tx [`0x5a421959…c7e`](https://explorer.testnet.arc.io/tx/0x5a421959e9218941d67139ca7e3caff8fa9d2d8b41d95f581b26699143ca8c7e)). Flows were then run with two wallets; [evidence/testnet-runbook.md](evidence/testnet-runbook.md) records the ones that were run and verified on chain.
- **Mainnet:** commit `4cff754`, pushed from this Studio workspace, was deployed with Foundry (forge 1.8.4, solc pinned to 0.8.28) from the builder's own deployer wallet. Arc Foundry was not used for the mainnet deployment. The runtime bytecode hash is identical on testnet and mainnet: `0x392029f2c9e51b363392c3f23e99539f29cc86d4932c470635d07c8dc37a4d79`. See [evidence/bytecode-match.txt](evidence/bytecode-match.txt).

## Design decisions

Full list in [docs/10-DECISIONS.md](docs/10-DECISIONS.md).

- **Immutable, no administrator, no fee** ([ADR-004](docs/10-DECISIONS.md)): no owner, pause, upgrade, fee or rescue function. The cost is that bugs cannot be patched in place.
- **USDC through its ERC-20 interface only** ([ADR-002](docs/10-DECISIONS.md)): Arc exposes USDC at 6 decimals as an ERC-20 and at 18 decimals as the native gas token. The contract never touches the native view, so there is no 10^12 mix-up.
- **Push payouts with a credit fallback** ([ADR-006](docs/10-DECISIONS.md)): a payout is sent directly. If the transfer fails, for example to a recipient blocked from receiving USDC, the amount is credited to that recipient instead, so a blocked address cannot freeze a retainer for the other side.

## Limitations

- No arbiter: a client can object to any claim. Objections are public and permanent.
- Notes are self-reported; the contract proves timing and money, not work quality.
- Unaudited. Use small amounts.
- Recovering a deferred payout (`withdrawOwed`) is covered by unit tests only. A recipient on the USDC blocklist cannot be staged on a live network, so this flow has no live evidence.
- Several actions have no live-network evidence in this repository, only tests: topping up, cancelling a withdrawal, cancelling a claim, extending the end date, and withdrawing the remainder after the end date. The live runs cover create and fund, file, silent payout, objection, withdrawal request, approve now and complete withdrawal.

## What's next

- Optional arbiter chosen at creation, with an appeal window
- Recurring top-ups and claim schedules for monthly retainers
- Team retainers: one client, several freelancers
- Shareable claim receipts for accounting and tax records
- Notifications when a claim is filed or about to pay out

## Run it yourself

Prerequisites: [Bun](https://bun.sh) and [Foundry](https://book.getfoundry.sh).

```
bun install
bun run dev
bun run contracts:build
bun run contracts:test
bun run check
bun run build
```

`bun run build` checks that every custom error in the compiled ABI has a message, type-checks, and then makes the production build. After a contract rebuild, run `bun run sync:abi` to refresh the generated ABI in `src/app-config/`.

### Environment variables

Copy `.env.example` to `.env` (never committed).

- `VITE_NETWORK`: `testnet` or `mainnet`. Unset means `testnet`. Any other value shows a configuration error page. `mainnet` uses real USDC.
- `VITE_RETAINER_TESTNET`: optional. Overrides the address recorded in `deployments/arc-testnet.json`.
- `VITE_RETAINER_MAINNET`: optional. Overrides the address recorded in `deployments/arc-mainnet.json`. With an override the app does not know the deployment block, so it reads recent history only and says it may be incomplete.

### Verify the bytecode match

Both commands should print `0x392029f2c9e51b363392c3f23e99539f29cc86d4932c470635d07c8dc37a4d79`:

```
cast code 0x54414913081adb0d95b0f5aedc6a4c8a8d85c821 --rpc-url https://rpc.testnet.arc.io | cast keccak
cast code 0x766bBE6b3819261F7C1161073551A27362c96047 --rpc-url https://rpc.mainnet.arc.io | cast keccak
```

### Hosting

The build is static (`dist/`) with hash routing, so no rewrite rules are needed. The app must never be framed: `public/_headers` (Netlify, Cloudflare Pages) and `vercel.json` (Vercel) set `Content-Security-Policy: frame-ancestors 'none'` and `X-Frame-Options: DENY` for every path. If you use another host, set the same two headers.

## Tech stack

- Solidity 0.8.28 and Foundry, with OpenZeppelin contracts 5.6.1
- Vite, React, TypeScript, Tailwind CSS
- wagmi and viem for wallet and chain access
- Arc, with USDC as the payment asset

## License

MIT. See [LICENSE](LICENSE), copyright 2026 Samuel Owen.

[`docs/design-references/emil-kowalski/`](docs/design-references/emil-kowalski/) is third-party material, MIT licensed, copyright Emil Kowalski (see the `LICENSE` in that folder). Other dependencies, including the vendored `lib/forge-std`, keep their own licenses.
