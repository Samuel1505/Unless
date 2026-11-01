import type { ReactNode } from 'react'
import { NETWORK_LABEL } from '@/app-config/contracts'
import { useNetworkGuard } from '@/hooks/useNetworkGuard'
import { ConnectButton } from './ConnectButton'
import { EmptyState } from './EmptyState'

/**
 * Renders `children` only when a wallet is connected on the expected network.
 * Otherwise it renders the one step that is missing.
 */
export function WalletGate({ needed, children }: { needed: string; children: ReactNode }) {
  const { isConnected, wrongNetwork, switchNetwork, isSwitching } = useNetworkGuard()

  if (!isConnected) {
    return (
      <EmptyState title="Connect a wallet" action={<ConnectButton primary />}>
        <p>{needed}</p>
      </EmptyState>
    )
  }

  if (wrongNetwork) {
    return (
      <EmptyState
        title={`Switch to ${NETWORK_LABEL}`}
        action={
          <button type="button" className="btn btn-primary" disabled={isSwitching} onClick={() => void switchNetwork()}>
            {isSwitching ? 'Waiting for your wallet…' : `Switch to ${NETWORK_LABEL}`}
          </button>
        }
      >
        <p>Your wallet is on another network.</p>
      </EmptyState>
    )
  }

  return <>{children}</>
}
