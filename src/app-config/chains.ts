import { defineChain } from 'viem'
import { ARC_FACTS, type ArcNetworkFacts, type NetworkKey } from './arc-facts'

/**
 * Chain definitions for the app (05-FRONTEND-SPEC 2.1), built from ./arc-facts. These are the parameters a
 * wallet is given when it is asked to add the chain, so the name, RPC, explorer and USDC gas currency
 * match what the Arc documentation lists.
 *
 * The native currency is USDC at 18 decimals. That is the gas unit only: it is never used for amounts.
 */
function toChain(facts: ArcNetworkFacts) {
  return defineChain({
    id: facts.chainId,
    name: facts.chainName,
    nativeCurrency: { ...facts.nativeCurrency },
    rpcUrls: { default: { http: [facts.rpcUrl] } },
    blockExplorers: { default: { name: facts.explorerName, url: facts.explorerBase } },
    testnet: facts.isTestnet,
  })
}

export const arcTestnet = toChain(ARC_FACTS.testnet)
export const arcMainnet = toChain(ARC_FACTS.mainnet)

export const ARC_CHAINS: Record<NetworkKey, typeof arcTestnet> = { testnet: arcTestnet, mainnet: arcMainnet }
