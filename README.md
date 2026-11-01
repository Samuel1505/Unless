# Unless

A retainer for freelancers that pays by default. A client prefunds a USDC retainer for a named freelancer. The freelancer files claims for finished work, and each claim pays out automatically when its objection window ends, unless the client objects first.

Built with [Arc Studio](https://studio.arc.io)

Status: the contract is complete, tested and deployed on Arc testnet. The app foundation is in place: wallet connection, a network badge and network guard, and the start page, retainer pages and "My retainers" list reading live data. Creating a retainer and acting on claims are the next screens.

## Tech stack

- Solidity 0.8.28 and Foundry, with OpenZeppelin contracts
- Vite, React, TypeScript, Tailwind CSS
- wagmi and viem for wallet and chain access
- Arc, with USDC as the payment asset

## Development

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

- `VITE_NETWORK`: the network the app talks to, `testnet` or `mainnet`. Unset means `testnet`. Any other value shows a configuration error page. `mainnet` uses real USDC.
- `VITE_RETAINER_TESTNET`: optional. Overrides the retainer address recorded in `deployments/arc-testnet.json`.
- `VITE_RETAINER_MAINNET`: optional. Overrides the retainer address recorded in `deployments/arc-mainnet.json`. With an override the app does not know the deployment block, so it reads recent history only and says it may be incomplete.

`.env.example` lists these names. Copy it to `.env`; `.env` is never committed.

### Hosting

The build is static (`dist/`) with hash routing, so no rewrite rules are needed. The app must never be framed: `public/_headers` (Netlify, Cloudflare Pages) and `vercel.json` (Vercel) set `Content-Security-Policy: frame-ancestors 'none'` and `X-Frame-Options: DENY` for every path. If you use another host, set the same two headers.
