import { useCallback, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { useAccount, usePublicClient, useSwitchChain, useWalletClient } from 'wagmi'
import { erc20Abi, type Abi, type Address, type Hash } from 'viem'
import { ACTIVE_CHAIN, CHAIN_ID, USDC_ADDRESS, retainerContract } from '@/app-config/contracts'
import { describeError } from '@/lib/errors'
import { getFeeOverrides } from '@/lib/fees'

/** Lifecycle of one write: idle, preparing (simulate), awaiting signature, submitted, confirmed (05-FRONTEND-SPEC 6.1). */
export type TxState =
  | { status: 'idle' }
  | { status: 'preparing' }
  | { status: 'awaiting-signature' }
  | { status: 'submitted'; hash: Hash }
  | { status: 'confirmed'; hash: Hash }
  | { status: 'failed'; message: string; hash?: Hash }

export interface ContractCall {
  address: Address
  abi: Abi
  functionName: string
  args?: readonly unknown[]
}

/**
 * Sends one write the way every write in the app is sent:
 *  1. switch to the expected network if the wallet is elsewhere,
 *  2. read the fee estimate and raise maxFeePerGas to at least 20 gwei,
 *  3. simulate first, so a revert is decoded into a message before the wallet opens,
 *  4. sign and send with the same fees,
 *  5. wait for one receipt (Arc finality is deterministic: one receipt is final),
 *  6. refetch everything that was read from the chain.
 */
export function useTransaction() {
  const { address, chainId: walletChainId } = useAccount()
  const publicClient = usePublicClient({ chainId: CHAIN_ID })
  const { data: walletClient } = useWalletClient({ chainId: CHAIN_ID })
  const { switchChainAsync } = useSwitchChain()
  const queryClient = useQueryClient()
  const [state, setState] = useState<TxState>({ status: 'idle' })

  const run = useCallback(
    async (call: ContractCall): Promise<Hash | undefined> => {
      if (!address || !publicClient || !walletClient) {
        setState({ status: 'failed', message: 'Connect your wallet to continue.' })
        return undefined
      }
      let submitted: Hash | undefined
      try {
        setState({ status: 'preparing' })
        if (walletChainId !== CHAIN_ID) await switchChainAsync({ chainId: CHAIN_ID })

        const fees = await getFeeOverrides(publicClient)
        const params = {
          address: call.address,
          abi: call.abi,
          functionName: call.functionName,
          args: call.args,
          account: address,
          ...fees,
        }
        await publicClient.simulateContract(params)

        setState({ status: 'awaiting-signature' })
        submitted = await walletClient.writeContract({ ...params, chain: ACTIVE_CHAIN })

        setState({ status: 'submitted', hash: submitted })
        const receipt = await publicClient.waitForTransactionReceipt({ hash: submitted })
        if (receipt.status !== 'success') {
          setState({
            status: 'failed',
            hash: submitted,
            message: 'The transaction was included but failed. Check it on the explorer.',
          })
          return undefined
        }

        await Promise.all([
          queryClient.invalidateQueries({ queryKey: ['readContract'] }),
          queryClient.invalidateQueries({ queryKey: ['readContracts'] }),
        ])
        setState({ status: 'confirmed', hash: submitted })
        return submitted
      } catch (error) {
        const described = describeError(error)
        if (described.kind === 'rejected') {
          setState({ status: 'idle' })
        } else {
          setState({ status: 'failed', message: described.message, hash: submitted })
        }
        return undefined
      }
    },
    [address, publicClient, walletClient, walletChainId, switchChainAsync, queryClient],
  )

  const reset = useCallback(() => setState({ status: 'idle' }), [])

  return { state, run, reset }
}

/**
 * USDC approval for the retainer. The approval is for the exact amount about to be spent, never
 * more (CLAUDE.md rule 10), and it is skipped when the current allowance already covers it.
 * Resolves true when the allowance is sufficient afterwards.
 */
export function useApproveExact() {
  const { address } = useAccount()
  const publicClient = usePublicClient({ chainId: CHAIN_ID })
  const { state, run, reset } = useTransaction()

  const ensureAllowance = useCallback(
    async (amount: bigint): Promise<boolean> => {
      if (!address || !publicClient) return false
      const spender = retainerContract().address
      const allowance = await publicClient.readContract({
        address: USDC_ADDRESS,
        abi: erc20Abi,
        functionName: 'allowance',
        args: [address, spender],
      })
      if (allowance >= amount) return true
      const hash = await run({
        address: USDC_ADDRESS,
        abi: erc20Abi,
        functionName: 'approve',
        args: [spender, amount],
      })
      return hash !== undefined
    },
    [address, publicClient, run],
  )

  return { state, ensureAllowance, reset }
}
