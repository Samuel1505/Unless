import { useModal } from 'connectkit'
import type { Hash } from 'viem'
import { useAccount } from 'wagmi'
import { useTransaction, type ContractCall } from '@/hooks/useTransaction'
import { IN_FLIGHT, TxFailure, TxSubmitted, submittedHash, txLabel } from './TxStatus'

interface TxButtonProps {
  /** Names the action and the amount: "Pay out 3.00 USDC". */
  label: string
  /** Null while the inputs behind the button are not valid. */
  call: ContractCall | null
  className?: string
  disabled?: boolean
  onConfirmed?: (hash: Hash) => void
}

/**
 * One write behind one button. The button itself shows where the transaction is (checking, waiting for
 * the wallet, sent) and a failure appears under it. Without a wallet it opens the connect dialog.
 */
export function TxButton({ label, call, className = 'btn btn-quiet', disabled = false, onConfirmed }: TxButtonProps) {
  const { isConnected } = useAccount()
  const { setOpen } = useModal()
  const { state, run } = useTransaction()
  const busy = IN_FLIGHT.has(state.status)

  const click = async () => {
    if (!isConnected) {
      setOpen(true)
      return
    }
    if (!call) return
    const hash = await run(call)
    if (hash) onConfirmed?.(hash)
  }

  return (
    <div className="flex min-w-0 flex-col items-start gap-1">
      <button type="button" className={className} disabled={disabled || busy || call === null} aria-busy={busy} onClick={() => void click()}>
        {txLabel(state, label, 'Sent, waiting for Arc…')}
      </button>
      <TxSubmitted hash={submittedHash(state)} />
      <TxFailure state={state} />
    </div>
  )
}
