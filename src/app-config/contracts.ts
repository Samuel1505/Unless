import { getAddress, isAddress, type Address } from 'viem'
import mainnetDeployment from '../../deployments/arc-mainnet.json'
import testnetDeployment from '../../deployments/arc-testnet.json'
import { ARC_FACTS, type NetworkKey } from './arc-facts'
import { ARC_CHAINS } from './chains'
import { retainerAbi } from './retainer-abi.generated'

/**
 * Network and contract configuration (05-FRONTEND-SPEC 2.2).
 *
 * This is the ONLY module that knows the retainer address. Components and hooks get it from
 * `retainerContract()`, never from a literal.
 *
 * VITE_NETWORK selects the network: "testnet" (the default) or "mainnet".
 * VITE_RETAINER_TESTNET / VITE_RETAINER_MAINNET optionally override the address recorded in
 * deployments/arc-testnet.json / deployments/arc-mainnet.json. An override has no known deployment block,
 * so its history is read from a recent window and is marked as possibly incomplete.
 */

export type { NetworkKey }

const env = import.meta.env as Record<string, string | undefined>

const NETWORKS = {
  testnet: {
    recordedAddress: testnetDeployment.address,
    recordedChainId: testnetDeployment.chainId,
    recordedBlock: testnetDeployment.block,
    addressOverride: env.VITE_RETAINER_TESTNET,
  },
  mainnet: {
    recordedAddress: mainnetDeployment.address,
    recordedChainId: mainnetDeployment.chainId,
    recordedBlock: mainnetDeployment.block,
    addressOverride: env.VITE_RETAINER_MAINNET,
  },
} as const

interface Resolved {
  network: NetworkKey
  retainerAddress: Address | undefined
  error: string | undefined
}

function resolveConfig(): Resolved {
  const requested = env.VITE_NETWORK?.trim() || 'testnet'
  if (requested !== 'testnet' && requested !== 'mainnet') {
    return {
      network: 'testnet',
      retainerAddress: undefined,
      error: `This build is set to the network "${requested}", which isn't configured. Set VITE_NETWORK to "testnet" or "mainnet".`,
    }
  }

  const network: NetworkKey = requested
  const facts = ARC_FACTS[network]
  const net = NETWORKS[network]
  const override = net.addressOverride?.trim()
  const candidate = override || net.recordedAddress
  if (!isAddress(candidate, { strict: false })) {
    return {
      network,
      retainerAddress: undefined,
      error: `The retainer address "${candidate}" for ${facts.label} isn't a valid address.`,
    }
  }
  if (!override && net.recordedChainId !== facts.chainId) {
    return {
      network,
      retainerAddress: undefined,
      error: `The recorded deployment is for chain ${net.recordedChainId}, not ${facts.label}.`,
    }
  }
  return { network, retainerAddress: getAddress(candidate), error: undefined }
}

const resolved = resolveConfig()

export const NETWORK: NetworkKey = resolved.network
export const ACTIVE_FACTS = ARC_FACTS[NETWORK]
export const NETWORK_LABEL = ACTIVE_FACTS.label
export const IS_TESTNET = ACTIVE_FACTS.isTestnet
export const ACTIVE_CHAIN = ARC_CHAINS[NETWORK]
export const CHAIN_ID = ACTIVE_CHAIN.id

/** Set when the build cannot run: the app renders a configuration error page instead of the routes. */
export const CONFIG_ERROR: string | undefined = resolved.error

/** ERC-20 interface of USDC (6 decimals). Native gas balance is the same pool at 18 decimals. */
export const USDC_ADDRESS: Address = getAddress(ACTIVE_FACTS.usdc.address)

export const RETAINER_ADDRESS: Address | undefined = resolved.retainerAddress

/**
 * Where activity history starts: the block the recorded deployment was mined in. Undefined when the
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
