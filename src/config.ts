/**
 * wagmi configuration
 * Built with Arc Studio — https://studio.arc.io
 */

import { http, createConfig } from 'wagmi'
import { mainnet } from 'wagmi/chains'
import { ACTIVE_CHAIN } from './app-config/contracts'
import { injected } from 'wagmi/connectors'
import { registerChain } from './tracing'

// Pre-register chain RPC URLs so trace events show correct chain names immediately
registerChain(ACTIVE_CHAIN.id, ACTIVE_CHAIN.rpcUrls.default.http[0])

// Only the active Arc network is configured, so a wallet is only ever asked to add or switch to that one.
// Ethereum mainnet is here for ENS name resolution only; the app never reads or writes retainers on it.
export const config = createConfig({
  chains: [ACTIVE_CHAIN, mainnet],
  connectors: [injected()],
  transports: {
    [ACTIVE_CHAIN.id]: http(),
    [mainnet.id]: http(), // ENS resolution uses Ethereum mainnet
  },
})
