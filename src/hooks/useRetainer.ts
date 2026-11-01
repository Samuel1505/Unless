import { useReadContract, useReadContracts } from 'wagmi'
import type { Address } from 'viem'
import { CHAIN_ID, retainerContract } from '@/app-config/contracts'

/** State is read from view functions and polled; events are never needed to decide what is allowed (ADR-007). */
const POLL_MS = 4000

export const CLAIM_STATUS = { None: 0, Pending: 1, Paid: 2, Objected: 3, Cancelled: 4 } as const
export const PAID_VIA = { None: 0, ApprovedNow: 1, PaidOut: 2 } as const

export function useRetainer(id: bigint | undefined) {
  return useReadContract({
    ...retainerContract(),
    functionName: 'getRetainer',
    args: id === undefined ? undefined : [id],
    chainId: CHAIN_ID,
    query: { enabled: id !== undefined, refetchInterval: POLL_MS, retry: false },
  })
}

/** All claims of a retainer, oldest first. Pages of 20 once there are more than 20 (05-FRONTEND-SPEC section 8). */
export function useClaims(id: bigint | undefined, claimCount: number) {
  const pages = Math.ceil(claimCount / 20)
  const contract = retainerContract()
  return useReadContracts({
    contracts: Array.from({ length: pages }, (_, page) => ({
      ...contract,
      functionName: 'getClaims' as const,
      args: [id ?? 0n, BigInt(page * 20), 20n] as const,
      chainId: CHAIN_ID,
    })),
    query: { enabled: id !== undefined && claimCount > 0, refetchInterval: POLL_MS },
  })
}

export function useOwed(account: Address | undefined) {
  return useReadContract({
    ...retainerContract(),
    functionName: 'owed',
    args: account ? [account] : undefined,
    chainId: CHAIN_ID,
    query: { enabled: account !== undefined, refetchInterval: POLL_MS },
  })
}

/** Ids of the retainers a wallet funds and the ones it is paid from. */
export function useMyRetainerIds(account: Address | undefined) {
  const contract = retainerContract()
  return useReadContracts({
    contracts: account
      ? [
          { ...contract, functionName: 'retainersOfClient' as const, args: [account] as const, chainId: CHAIN_ID },
          { ...contract, functionName: 'retainersOfFreelancer' as const, args: [account] as const, chainId: CHAIN_ID },
        ]
      : [],
    query: { enabled: account !== undefined, refetchInterval: POLL_MS },
  })
}

export function useRetainerSummaries(ids: readonly bigint[]) {
  const contract = retainerContract()
  return useReadContracts({
    contracts: ids.map((id) => ({
      ...contract,
      functionName: 'getRetainer' as const,
      args: [id] as const,
      chainId: CHAIN_ID,
    })),
    query: { enabled: ids.length > 0, refetchInterval: POLL_MS },
  })
}
