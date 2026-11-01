import type { Hash } from 'viem'
import type { TxState } from '@/hooks/useTransaction'
import { explorerTxUrl } from '@/lib/format'

export const IN_FLIGHT = new Set<TxState['status']>(['preparing', 'awaiting-signature', 'submitted'])

/** The label a button shows for each lifecycle state of its own transaction (05-FRONTEND-SPEC 6.1). */
export function txLabel(state: TxState, idle: string, submitted: string, confirmed: string = idle): string {
  switch (state.status) {
    case 'preparing':
      return 'Checking…'
    case 'awaiting-signature':
      return 'Confirm in your wallet'
    case 'submitted':
      return submitted
    case 'confirmed':
      return confirmed
    default:
      return idle
  }
}

export function submittedHash(...states: TxState[]): Hash | undefined {
  for (const state of states) if (state.status === 'submitted') return state.hash
  return undefined
}

/** A failed step returns to idle with its reason under the button; nothing is hidden behind a toast. */
export function TxFailure({ state }: { state: TxState }) {
  if (state.status !== 'failed') return null
  return (
    <p role="alert" className="text-step--1 text-objected [overflow-wrap:anywhere]">
      {state.message}
      {state.hash && (
        <>
          {' '}
          <a href={explorerTxUrl(state.hash)} target="_blank" rel="noopener noreferrer">
            View on explorer
          </a>
        </>
      )}
    </p>
  )
}

export function TxSubmitted({ hash }: { hash: Hash | undefined }) {
  if (!hash) return null
  return (
    <p role="status" className="text-step--1 text-muted">
      Sent.{' '}
      <a href={explorerTxUrl(hash)} target="_blank" rel="noopener noreferrer">
        View on explorer
      </a>
    </p>
  )
}
