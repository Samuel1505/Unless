import { defineChain } from 'viem'
import { requireChainByScpBlockchain } from '@/onchain-facts'

/**
 * Chain definitions for the app. Every value comes from @/onchain-facts (05-FRONTEND-SPEC 2.1).
 *
 * The native currency is USDC at 18 decimals. That is the gas unit only: it is never used for amounts.
 * Amounts are always the 6-decimal ERC-20 view (see src/lib/format.ts and @/onchain-money).
 */
const testnetFacts = requireChainByScpBlockchain('ARC-TESTNET')

export const arcTestnet = defineChain({
  id: testnetFacts.chainId,
  name: testnetFacts.name,
  nativeCurrency: {
    name: testnetFacts.nativeCurrency.symbol,
    symbol: testnetFacts.nativeCurrency.symbol,
    decimals: testnetFacts.nativeCurrency.decimals,
  },
  rpcUrls: { default: { http: [...testnetFacts.rpcUrls] } },
  blockExplorers: { default: { name: 'Arc Testnet Explorer', url: testnetFacts.explorerBase } },
  testnet: true,
})
