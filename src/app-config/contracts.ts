import { getAddress, isAddress, type Address } from 'viem'
import { getUsdc } from '@/onchain-facts'
import deployment from '../../deployments/arc-testnet.json'
import { arcTestnet } from './chains'
import { retainerAbi } from './retainer-abi.generated'

/**
 * Network and contract configuration (05-FRONTEND-SPEC 2.2).
 *
 * This is the ONLY module that knows the retainer address. Components and hooks get it from
 * `retainerContract()`, never from a literal.
 *
 * VITE_NETWORK selects the network. Only "testnet" is configured in this build.
 * VITE_RETAINER_TESTNET optionally overrides the address recorded in deployments/arc-testnet.json.
 */

export type NetworkKey = 'testnet'

const env = import.meta.env as Record<string, string | undefined>

const NETWORKS = {
  testnet: {
    key: 'testnet',
    label: 'Arc testnet',
    chain: arcTestnet,
    recordedAddress: deployment.address,
    recordedChainId: deployment.chainId,
    recordedBlock: deployment.block,
    addressOverride: env.VITE_RETAINER_TESTNET,
  },
} as const

function resolveConfig(): {
  network: NetworkKey
  retainerAddress: Address | undefined
  error: string | undefined
} {
  const requested = env.VITE_NETWORK?.trim() || 'testnet'
  if (requested !== 'testnet') {
    return {
      network: 'testnet',
      retainerAddress: undefined,
      error: `This build is set to the network "${requested}", which isn't configured. Set VITE_NETWORK to "testnet".`,
    }
  }

  const net = NETWORKS.testnet
  const candidate = net.addressOverride?.trim() || net.recordedAddress
  if (!isAddress(candidate, { strict: false })) {
    return {
      network: 'testnet',
      retainerAddress: undefined,
      error: `The retainer address "${candidate}" for ${net.label} isn't a valid address.`,
    }
  }
  if (!net.addressOverride?.trim() && net.recordedChainId !== net.chain.id) {
    return {
      network: 'testnet',
      retainerAddress: undefined,
      error: `The recorded deployment is for chain ${net.recordedChainId}, not ${net.label}.`,
    }
  }
  return { network: 'testnet', retainerAddress: getAddress(candidate), error: undefined }
}

const resolved = resolveConfig()

export const NETWORK: NetworkKey = resolved.network
export const NETWORK_LABEL = NETWORKS[NETWORK].label
export const ACTIVE_CHAIN = NETWORKS[NETWORK].chain
export const CHAIN_ID = ACTIVE_CHAIN.id

/** Set when the build cannot run: the app renders a configuration error page instead of the routes. */
export const CONFIG_ERROR: string | undefined = resolved.error

const usdcFact = getUsdc(CHAIN_ID)
if (!usdcFact) {
  throw new Error(`USDC is not listed for chain ${CHAIN_ID} in @/onchain-facts`)
}
/** ERC-20 interface of USDC (6 decimals). Native gas balance is the same pool at 18 decimals. */
export const USDC_ADDRESS: Address = getAddress(usdcFact.address)

export const RETAINER_ADDRESS: Address | undefined = resolved.retainerAddress

/**
 * Where activity history starts. The block the recorded deployment was mined in, or undefined when the
 * address is overridden (the deployment block of another address is unknown, so a recent window is used).
 */
export const RETAINER_START_BLOCK: bigint | undefined =
  NETWORKS[NETWORK].addressOverride?.trim() || typeof NETWORKS[NETWORK].recordedBlock !== 'number'
    ? undefined
    : BigInt(NETWORKS[NETWORK].recordedBlock)

/**
 * Used only when RETAINER_START_BLOCK is unknown (the address is overridden): the recent blocks that are
 * read instead, and the history is then marked as possibly incomplete (05-FRONTEND-SPEC section 8).
 * With a known deployment block there is no cap: notes and reasons exist only in events.
 */
export const FALLBACK_LOOKBACK_BLOCKS = 200_000n

/** Address and ABI for wagmi/viem calls. Only call after the configuration gate has passed. */
export function retainerContract() {
  if (!RETAINER_ADDRESS) {
    throw new Error(CONFIG_ERROR ?? 'Retainer address is not configured')
  }
  return { address: RETAINER_ADDRESS, abi: retainerAbi } as const
}

export { retainerAbi }
