/**
 * Facts about the Arc networks this app can run on. They are written down here, in the project, because
 * the app must build from a plain clone of the repository.
 *
 * Source: Arc documentation, read on 2026-11-01:
 *   https://docs.arc.io/arc/references/connect-to-arc.md        (chain ids, RPC URLs, explorers)
 *   https://docs.arc.io/arc/references/contract-addresses.md    (USDC ERC-20 interface and its decimals)
 *   https://docs.arc.io/arc/references/evm-differences.md       (gas is USDC at 18 decimals)
 *
 * Gas is USDC at 18 decimals. That native view is only for gas. Every amount in the app is the 6-decimal
 * ERC-20 view of USDC, never the native one.
 */

export type NetworkKey = 'testnet' | 'mainnet'

export interface ArcNetworkFacts {
  key: NetworkKey
  /** Short name shown to people: the badge, the switch prompt. */
  label: string
  /** Name a wallet shows when the chain is added. */
  chainName: string
  chainId: number
  rpcUrl: string
  /** No trailing slash. */
  explorerBase: string
  explorerName: string
  nativeCurrency: { name: string; symbol: string; decimals: number }
  /** The ERC-20 interface of USDC. */
  usdc: { address: `0x${string}`; decimals: number }
  /** True on the network where USDC has no value. */
  isTestnet: boolean
}

const USDC_ERC20 = { address: '0x3600000000000000000000000000000000000000', decimals: 6 } as const
const NATIVE_USDC = { name: 'USDC', symbol: 'USDC', decimals: 18 } as const

export const ARC_FACTS: Record<NetworkKey, ArcNetworkFacts> = {
  testnet: {
    key: 'testnet',
    label: 'Arc testnet',
    chainName: 'Arc Testnet',
    chainId: 5042002,
    rpcUrl: 'https://rpc.testnet.arc.io',
    explorerBase: 'https://explorer.testnet.arc.io',
    explorerName: 'Arc Testnet Explorer',
    nativeCurrency: NATIVE_USDC,
    usdc: USDC_ERC20,
    isTestnet: true,
  },
  mainnet: {
    key: 'mainnet',
    label: 'Arc mainnet',
    chainName: 'Arc',
    chainId: 5042,
    rpcUrl: 'https://rpc.mainnet.arc.io',
    explorerBase: 'https://explorer.arc.io',
    explorerName: 'Arc Explorer',
    nativeCurrency: NATIVE_USDC,
    usdc: USDC_ERC20,
    isTestnet: false,
  },
}
