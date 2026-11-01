import { parseGwei } from 'viem'

/**
 * Arc's mempool silently drops a transaction whose maxFeePerGas is below 20 gwei, so every
 * write the app sends carries a fee at or above this floor (05-FRONTEND-SPEC 6.3, CLAUDE.md rule 11).
 */
export const MIN_FEE_PER_GAS = parseGwei('20')

interface FeeEstimator {
  estimateFeesPerGas: () => Promise<{ maxFeePerGas: bigint; maxPriorityFeePerGas: bigint }>
}

export interface FeeOverrides {
  maxFeePerGas: bigint
  maxPriorityFeePerGas: bigint
}

export function applyFeeFloor(estimate: { maxFeePerGas: bigint; maxPriorityFeePerGas?: bigint | undefined }): FeeOverrides {
  const maxFeePerGas = estimate.maxFeePerGas < MIN_FEE_PER_GAS ? MIN_FEE_PER_GAS : estimate.maxFeePerGas
  const priority = estimate.maxPriorityFeePerGas ?? 0n
  return { maxFeePerGas, maxPriorityFeePerGas: priority > maxFeePerGas ? maxFeePerGas : priority }
}

/** Reads the network estimate and raises it to the floor. Pass the result on every write. */
export async function getFeeOverrides(client: FeeEstimator): Promise<FeeOverrides> {
  return applyFeeFloor(await client.estimateFeesPerGas())
}
