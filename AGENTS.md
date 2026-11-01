# [App Name]

> Built with Arc Studio - money-powered apps in minutes

This is the **project memory** - what Arc Studio remembers about building this app. It helps future agents (or humans) understand and extend the project.

---

## What This App Does

[Brief description of what the app does and its primary use case]

## Tech Stack

- Frontend: React 18, Vite, TypeScript, Tailwind CSS
- Web3: wagmi v2, viem v2, ConnectKit
- Contracts: Solidity 0.8.28 + Foundry. Sources in `contracts/`, unit tests in `contracts/test/*.t.sol`. Build with `bun run contracts:build` (`forge build`), test with `bun run contracts:test` (`forge test`).
- Wallet: injected (MetaMask, etc.)
- Chain: Arc Testnet (Chain ID: 5042002, imported from `viem/chains`)
- Token: USDC (6 decimals) (Address: 0x3600000000000000000000000000000000000000, Chain: Arc Testnet)
- Toasts: Sonner

## Key Files

- `src/App.tsx` - Composition root: configuration gate, shell, hash routes
- `src/config.ts` - wagmi config (chains, connectors, transports); uses the chain from `src/app-config/chains.ts`
- `src/app-config/chains.ts` - Arc chain definition, built from `@/onchain-facts`
- `src/app-config/contracts.ts` - network selection (`VITE_NETWORK`), the ONLY place the retainer address is resolved (from `deployments/arc-testnet.json`, optional `VITE_RETAINER_TESTNET` override), USDC address, ABI export
- `src/app-config/retainer-abi.generated.ts` - GENERATED from the compiled artifact by `bun run sync:abi`; never edit by hand
- `src/lib/error-messages.ts` - one message per ABI error (type-checked and re-checked by `bun run check:errors` before every build); `src/lib/errors.ts` decodes thrown errors
- `src/lib/fees.ts` - 20 gwei fee floor; every write goes through `src/hooks/useTransaction.ts` (network switch, simulate, fees, exact USDC approval)
- `src/hooks/useChainTime.ts` - chain time for all countdowns; `src/lib/router.tsx` - hash routing
- `src/routes/`, `src/components/` - screens and shared UI
- Design tokens and fonts: `src/index.css`, `tailwind.config.js` (docs/05-FRONTEND-SPEC 5.2)

## Deployed Contracts

- `UnlessRetainer` on Arc Testnet (5042002): `0x54414913081adb0d95b0f5aedc6a4c8a8d85c821`, tx `0x5a421959e9218941d67139ca7e3caff8fa9d2d8b41d95f581b26699143ca8c7e`, block 69092835. Constructor arg: USDC `0x3600000000000000000000000000000000000000`. Full record in `deployments/arc-testnet.json`. The contract is frozen: any change to the source, `foundry.toml`, `remappings.txt` or the OpenZeppelin version means a redeploy.

## To Run

```bash
bun install
bun run dev
```
