import { keepPreviousData, useQuery } from '@tanstack/react-query'
import { usePublicClient } from 'wagmi'
import { CHAIN_ID, retainerContract } from '@/app-config/contracts'
import { earliestPendingPayableAt } from '@/lib/nextEvent'

/**
 * The earliest payableAt among a retainer's Pending claims, for a list row. It reads nothing unless the
 * row is on screen and has pending claims. The result cannot change unless the retainer's own counters
 * do (a claim filed raises claimCount; one resolved lowers pendingClaims), so the counters are the query
 * key and there is no polling of its own.
 */
export function useNextClaim(id: bigint, claimCount: number, pendingClaims: number, enabled: boolean) {
  const client = usePublicClient({ chainId: CHAIN_ID })
  const active = enabled && pendingClaims > 0 && client !== undefined

  return useQuery({
    queryKey: ['next-claim', CHAIN_ID, id.toString(), claimCount, pendingClaims],
    enabled: active,
    staleTime: Infinity,
    placeholderData: keepPreviousData,
    queryFn: async () => {
      if (!client) throw new Error('No RPC client for the active network')
      const contract = retainerContract()
      const { payableAt } = await earliestPendingPayableAt(
        async (offset, limit) => {
          const claims = await client.readContract({
            ...contract,
            functionName: 'getClaims',
            args: [id, BigInt(offset), BigInt(limit)],
          })
          return claims.map((claim) => ({ status: claim.status, payableAt: Number(claim.payableAt) }))
        },
        claimCount,
        pendingClaims,
      )
      return { payableAt }
    },
  })
}
