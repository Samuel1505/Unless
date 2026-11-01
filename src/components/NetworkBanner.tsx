import { NETWORK_LABEL } from '@/app-config/contracts'
import { useNetworkGuard } from '@/hooks/useNetworkGuard'

/**
 * Shown when a wallet is connected on another network. The region is a polite live region that
 * only changes when the state changes, so a screen reader hears it once.
 */
export function NetworkBanner() {
  const { wrongNetwork, switchNetwork, isSwitching, switchFailed } = useNetworkGuard()

  return (
    <div role="status" aria-live="polite">
      {wrongNetwork && (
        <div
          className="enter-fade border-b border-rule"
          style={{ background: 'color-mix(in srgb, var(--objected) 10%, transparent)' }}
        >
          <div className="shell-x mx-auto flex max-w-5xl flex-wrap items-center gap-3 py-3">
            <p className="text-step-0">
              {switchFailed
                ? `Your wallet didn't switch. Switch to ${NETWORK_LABEL} in your wallet, then try again.`
                : `Your wallet is on another network. Switch to ${NETWORK_LABEL} to continue.`}
            </p>
            <button
              type="button"
              className="btn btn-primary ml-auto"
              disabled={isSwitching}
              onClick={() => void switchNetwork()}
            >
              {isSwitching ? 'Waiting for your wallet…' : `Switch to ${NETWORK_LABEL}`}
            </button>
          </div>
        </div>
      )}
    </div>
  )
}
