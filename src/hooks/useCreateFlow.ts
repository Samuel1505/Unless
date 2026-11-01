import { useCallback, useEffect } from 'react'
import { useAccount, usePublicClient } from 'wagmi'
import { parseEventLogs } from 'viem'
import { CHAIN_ID, retainerContract } from '@/app-config/contracts'
import { useUsdcAllowance } from '@/hooks/useCreateReads'
import { useApproveExact, useTransaction } from '@/hooks/useTransaction'
import type { CreateTerms } from '@/lib/createRetainer'
import { navigate } from '@/lib/router'

/**
 * The two steps of 05-FRONTEND-SPEC 4.2: approve the exact amount (skipped when the allowance already
 * covers it), then create the retainer. Both go through the shared transaction hooks, so both simulate
 * first, carry the fee floor and report the same lifecycle states.
 */
export function useCreateFlow(terms: CreateTerms | null) {
  const { address } = useAccount()
  const publicClient = usePublicClient({ chainId: CHAIN_ID })
  const allowance = useUsdcAllowance(address)
  const approval = useApproveExact()
  const creation = useTransaction()

  // A changed amount or terms is a new request: forget the last outcome.
  const amount = terms?.amount
  const resetApproval = approval.reset
  const resetCreation = creation.reset
  useEffect(() => {
    resetApproval()
    resetCreation()
  }, [amount, terms?.freelancer, terms?.window, terms?.notice, terms?.endTime, resetApproval, resetCreation])

  /** true: approval needed, false: already covered, undefined: still reading the allowance. */
  const needsApproval =
    terms === null || allowance.data === undefined ? undefined : terms.amount > 0n && allowance.data < terms.amount

  const refetchAllowance = allowance.refetch
  const approve = useCallback(async () => {
    if (terms === null) return
    await approval.ensureAllowance(terms.amount)
    await refetchAllowance()
  }, [terms, approval, refetchAllowance])

  const create = useCallback(async () => {
    if (terms === null || !publicClient) return
    const contract = retainerContract()
    const hash = await creation.run({
      address: contract.address,
      abi: contract.abi,
      functionName: 'createRetainer',
      args: [terms.freelancer, terms.window, terms.notice, BigInt(terms.endTime), terms.amount],
    })
    if (hash === undefined) return
    // The new retainer's number comes from the receipt, so two people creating at once cannot cross wires.
    const receipt = await publicClient.getTransactionReceipt({ hash })
    const [created] = parseEventLogs({ abi: contract.abi, logs: receipt.logs, eventName: 'RetainerCreated' })
    navigate(created === undefined ? '/me' : `/r/${created.args.id.toString()}`)
  }, [terms, publicClient, creation])

  return {
    needsApproval,
    approvalState: approval.state,
    creationState: creation.state,
    approve,
    create,
  }
}
