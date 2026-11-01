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

- `VITE_NETWORK`: the network the app talks to. Only `testnet` is configured; leave it unset for testnet.
- `VITE_RETAINER_TESTNET`: optional. Overrides the retainer address recorded in `deployments/arc-testnet.json`.
