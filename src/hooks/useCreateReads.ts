import { useReadContract, useReadContracts } from 'wagmi'
import { erc20Abi, type Address } from 'viem'
import { CHAIN_ID, USDC_ADDRESS, retainerContract } from '@/app-config/contracts'
import type { Limits } from '@/lib/createRetainer'

const POLL_MS = 8000

/** The connected wallet's USDC balance in the ERC-20 view (6 decimals). */
export function useUsdcBalance(owner: Address | undefined) {
  return useReadContract({
    address: USDC_ADDRESS,
    abi: erc20Abi,
    functionName: 'balanceOf',
    args: owner ? [owner] : undefined,
    chainId: CHAIN_ID,
    query: { enabled: owner !== undefined, refetchInterval: POLL_MS },
  })
}

/** How much USDC the retainer may already pull from the wallet. */
export function useUsdcAllowance(owner: Address | undefined) {
  return useReadContract({
    address: USDC_ADDRESS,
    abi: erc20Abi,
    functionName: 'allowance',
    args: owner ? [owner, retainerContract().address] : undefined,
    chainId: CHAIN_ID,
    query: { enabled: owner !== undefined, refetchInterval: POLL_MS },
  })
}

/**
 * The window and notice limits, read from the deployed retainer itself so the form can never disagree
 * with it. They are constants of the deployment, so they are read once.
 */
export function useRetainerLimits(): { limits: Limits | undefined; isError: boolean } {
  const contract = retainerContract()
  const { data, isError } = useReadContracts({
    contracts: [
      { ...contract, functionName: 'MIN_WINDOW', chainId: CHAIN_ID },
      { ...contract, functionName: 'MAX_WINDOW', chainId: CHAIN_ID },
      { ...contract, functionName: 'MIN_NOTICE', chainId: CHAIN_ID },
      { ...contract, functionName: 'MAX_NOTICE', chainId: CHAIN_ID },
    ],
    query: { staleTime: Infinity },
  })
  if (!data) return { limits: undefined, isError }
  const [minWindow, maxWindow, minNotice, maxNotice] = data
  if (
    minWindow.status !== 'success' ||
    maxWindow.status !== 'success' ||
    minNotice.status !== 'success' ||
    maxNotice.status !== 'success'
  ) {
    return { limits: undefined, isError: true }
  }
  return {
    limits: {
      minWindow: Number(minWindow.result),
      maxWindow: Number(maxWindow.result),
      minNotice: Number(minNotice.result),
      maxNotice: Number(maxNotice.result),
    },
    isError,
  }
}
