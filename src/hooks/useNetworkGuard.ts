import { useCallback, useState } from 'react'
import { useAccount, useSwitchChain } from 'wagmi'
import { CHAIN_ID } from '@/app-config/contracts'

/**
 * Network guard (05-FRONTEND-SPEC 6.5). `wrongNetwork` is true when a wallet is connected on another
 * chain. `switchNetwork` asks the wallet to switch; wagmi sends wallet_switchEthereumChain and, when the
 * wallet does not know the chain (error 4902), wallet_addEthereumChain with the chain from
 * src/app-config/chains.ts.
 */
export function useNetworkGuard() {
  const { isConnected, chainId } = useAccount()
  const { switchChainAsync, isPending } = useSwitchChain()
  const [failed, setFailed] = useState(false)

  const switchNetwork = useCallback(async (): Promise<boolean> => {
    setFailed(false)
    try {
      await switchChainAsync({ chainId: CHAIN_ID })
      return true
    } catch {
      setFailed(true)
      return false
    }
  }, [switchChainAsync])

  return {
    isConnected,
    wrongNetwork: isConnected && chainId !== CHAIN_ID,
    switchNetwork,
    isSwitching: isPending,
    switchFailed: failed,
  }
}
