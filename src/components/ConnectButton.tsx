import { ConnectKitButton } from 'connectkit'
import { shortAddress } from '@/lib/format'

export function ConnectButton({ primary = false }: { primary?: boolean }) {
  return (
    <ConnectKitButton.Custom>
      {({ isConnected, isConnecting, show, address, ensName }) => (
        <button
          type="button"
          onClick={show}
          disabled={isConnecting}
          className={`btn ${isConnected && !primary ? 'btn-quiet num' : 'btn-primary'}`}
        >
          {isConnecting
            ? 'Connecting…'
            : isConnected && address
              ? (ensName ?? shortAddress(address))
              : 'Connect wallet'}
        </button>
      )}
    </ConnectKitButton.Custom>
  )
}
