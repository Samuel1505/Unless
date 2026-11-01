# 07 — Deployment Runbook

Three environments, one source of truth:

```
Arc Studio workspace ──(Studio deploy)──▶ Arc testnet
        │
        └──(push to GitHub)──▶ public repo ──(arc-forge, own key)──▶ Arc mainnet
                                     │
                                     └──(static build)──▶ public host (app)
```

The mainnet contract must be built from the exact commit Studio pushed, with the exact compiler settings Studio used. That is what lets us prove lineage with a bytecode hash match (§6).

## 1. Prerequisites checklist

- [ ] Studio workspace created; project URL saved to `evidence/studio/project-url.txt`
- [ ] Studio connected to GitHub; repo is public
- [ ] Arc Foundry installed locally (§2)
- [ ] Deployer wallet: a **fresh** EOA used only for this deployment, funded with ~1 USDC on Arc mainnet
- [ ] Demo wallets funded (06-ARC-PLATFORM-NOTES §6)
- [ ] Static host account (Vercel, Cloudflare Pages, Netlify, or GitHub Pages)
- [ ] All Phase 1–4 gates passed (CLAUDE.md §5)

## 2. Arc Foundry

Install per docs.arc.io's Arc Foundry instructions. Record the installed versions:

```
arc-forge --version  > evidence/toolchain.txt
arc-cast  --version >> evidence/toolchain.txt
```

Why Arc Foundry and not stock Foundry for mainnet work: it handles Arc's protocol differences (native USDC precompiles, fee rules). Unit tests with mocks run on either; fork tests and deployments use Arc Foundry. If an `arc-*` command behaves differently from its `forge`/`cast` equivalent, trust the Arc one and note the difference here.

## 3. Testnet deployment (inside Studio)

1. Prompt Studio to deploy `UnlessRetainer` to Arc testnet with constructor argument `0x3600000000000000000000000000000000000000` (see 11-STUDIO-PROMPTS P5).
2. Capture Studio's deployment output (address, tx hash, explorer URL). With the CLI:
   ```
   arc-studio run "<P5 prompt>" --output json > evidence/studio/p5-testnet-deploy.json
   ```
3. Write `deployments/arc-testnet.json`:
   ```json
   {
     "network": "arc-testnet",
     "chainId": 5042002,
     "contract": "UnlessRetainer",
     "address": "0x…",
     "deployTx": "0x…",
     "block": 0,
     "constructorArgs": ["0x3600000000000000000000000000000000000000"],
     "compiler": { "solc": "0.8.x", "optimizer": true, "runs": 200, "evmVersion": "…", "viaIR": false },
     "deployedBy": "Arc Studio",
     "studioProjectUrl": "https://studio.arc.io/app/…",
     "date": "2026-10-2x"
   }
   ```
   The compiler block is mandatory. Read it from `foundry.toml` in the Studio workspace (or the build artifact metadata).
4. Run the manual testnet runbook (04-TEST-PLAN §7).

## 4. Export

1. Prompt Studio to push the workspace to GitHub (11-STUDIO-PROMPTS P10). Note the commit hash in `deployments/arc-mainnet.json` before deploying.
2. Clone the repo locally. Do **not** modify contract source or `foundry.toml`.
3. Verify the local build reproduces Studio's artifact:
   ```
   arc-forge build --force
   arc-forge inspect UnlessRetainer deployedBytecode | arc-cast keccak
   ```
   Compare against the testnet runtime code hash (§6, step 1). If they differ, stop: settings diverged.

   *Corrected 2026-11-01:* the raw `deployedBytecode` hash never equals the on-chain hash, because the artifact zero-fills the six `USDC` immutable slots. Write `0x3600…0000` into the slots listed in the artifact's `deployedBytecode.immutableReferences` first, then compare. Alternatively, compare on-chain code with on-chain code (§6). Tooling used on 2026-11-01: no published Arc Foundry install was found, so standard Foundry 1.8.4 with the pinned solc 0.8.28 was used. The result was byte-identical (`evidence/bytecode-match.txt`).

## 5. Mainnet deployment

### 5.1 Deploy script (`script/Deploy.s.sol`)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UnlessRetainer} from "../contracts/UnlessRetainer.sol";

contract Deploy is Script {
    address constant ARC_USDC = 0x3600000000000000000000000000000000000000;

    function run() external returns (UnlessRetainer retainer) {
        require(block.chainid == 5042 || block.chainid == 5042002, "not Arc");
        vm.startBroadcast();
        retainer = new UnlessRetainer(IERC20(ARC_USDC));
        vm.stopBroadcast();
        console2.log("UnlessRetainer", address(retainer));
    }
}
```
This script is authored in Studio (it is part of the workspace) and used unchanged for mainnet.

### 5.2 Key handling

Use an encrypted keystore, never a raw key on the command line:
```
arc-cast wallet import unless-deployer --interactive
```

### 5.3 Dry run, then broadcast

```
export ARC_MAINNET_RPC=https://rpc.mainnet.arc.io

# 1. simulate
arc-forge script script/Deploy.s.sol:Deploy --rpc-url $ARC_MAINNET_RPC --account unless-deployer

# 2. broadcast (ensure fees ≥ 20 gwei; set explicitly if the estimator returns less)
arc-forge script script/Deploy.s.sol:Deploy --rpc-url $ARC_MAINNET_RPC --account unless-deployer \
  --broadcast --with-gas-price 25gwei
```
Flag names follow Foundry conventions; confirm with `arc-forge script --help`. If the transaction does not appear within a few seconds, the fee was too low; do **not** resend blindly — check the nonce first with `arc-cast nonce`.

### 5.4 Post-deploy verification

```
export RETAINER=0x…   # from broadcast output

arc-cast call $RETAINER "USDC()(address)"          --rpc-url $ARC_MAINNET_RPC   # expect 0x3600…0000
arc-cast call $RETAINER "nextRetainerId()(uint256)" --rpc-url $ARC_MAINNET_RPC   # expect 0
arc-cast call $RETAINER "MIN_WINDOW()(uint256)"     --rpc-url $ARC_MAINNET_RPC   # expect 60
```
Then verify source on the explorer (Sourcify or the explorer's verifier — NEEDS VERIFICATION which one explorer.arc.io reads) using the same compiler settings.

Write `deployments/arc-mainnet.json` in the same shape as testnet, with `"deployedBy": "arc-forge from Studio commit <hash>"`.

## 6. Lineage proof: bytecode match

Because the only constructor argument is the USDC address, which is identical on testnet and mainnet, and `USDC` is an immutable embedded in runtime code, **the runtime bytecode of both deployments must be byte-identical**.

```
arc-cast code $RETAINER_TESTNET --rpc-url https://rpc.testnet.arc.io  | arc-cast keccak
arc-cast code $RETAINER        --rpc-url $ARC_MAINNET_RPC            | arc-cast keccak
```
Write both hashes, both addresses, the Studio project URL, and the commit hash to `evidence/bytecode-match.txt`. Matching hashes are the strongest single piece of evidence that the mainnet contract is the Studio-built contract.

If hashes differ only in the metadata suffix (CBOR-encoded IPFS hash at the end), the source or settings differ. Fix rather than explain.

## 7. Hosting the app

1. In the exported repo, create `.env.production` (not committed) or set host environment variables:
   ```
   VITE_NETWORK=mainnet
   VITE_RETAINER_MAINNET=0x…
   VITE_RETAINER_TESTNET=0x…
   ```
2. Build with the command Studio's scaffold defines (typically `npm ci && npm run build`); output directory typically `dist/`.
3. Deploy `dist/` to the static host. Hash routing means no rewrite rules are needed.
   - **Required response header:** `Content-Security-Policy: frame-ancestors 'none'` (and `X-Frame-Options: DENY` for older browsers). The app must never be framed. Reasons: clickjacking on payment buttons, and the Studio scaffold's `src/tracing.ts` posts every RPC and wallet call to `window.parent`, so a framing site would receive them. Top-level, it only posts to itself. Added 2026-10-25 after the P6 review.
4. Smoke test on the public URL with a fresh browser profile:
   - network badge says "Arc mainnet"
   - home loads; `/#/r/0` shows "There's no retainer 0" (before the demo) or the demo retainer (after)
   - connect wallet → switch-network prompt appears when on another chain
   - contract link opens the mainnet explorer address page
   - response headers include `frame-ancestors 'none'` (check with `curl -sI <url>`)

Record the URL in `evidence/app-url.txt`.

## 8. Rollback

There is no upgrade path. If a mainnet bug is found:
1. Stop using the deployment in the app (point `VITE_RETAINER_MAINNET` at a fixed redeploy).
2. Funds in existing retainers remain governed by the old contract's rules; both parties can still resolve them through the old address via explorer or `cast`.
3. Fix in Studio, re-run Phases 1–3, redeploy, re-run §6.
4. Document the incident in the README.

Keep demo amounts small (Round 2 page: "use small amounts").
