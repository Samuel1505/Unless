import type { useCreateFlow } from '@/hooks/useCreateFlow'
import type { CreateTerms } from '@/lib/createRetainer'
import { explorerTxUrl, formatUsdcPlain } from '@/lib/format'
import { IN_FLIGHT, TxFailure, submittedHash, txLabel } from './TxStatus'

type Flow = ReturnType<typeof useCreateFlow>

interface CreateActionsProps {
  terms: CreateTerms | null
  flow: Flow
  /** Why the buttons are disabled, when the form itself is the reason. */
  blockedReason: string | null
}

/** Approve the exact amount, then create. The approval step disappears when the allowance already covers it. */
export function CreateActions({ terms, flow, blockedReason }: CreateActionsProps) {
  const { needsApproval, approvalState, creationState } = flow
  const busy = IN_FLIGHT.has(approvalState.status) || IN_FLIGHT.has(creationState.status)
  const ready = terms !== null && needsApproval !== undefined
  const hash = submittedHash(approvalState, creationState)

  const status =
    blockedReason ?? (terms !== null && needsApproval === undefined ? 'Reading your USDC approval…' : null)

  return (
    <div className="space-y-3">
      <div className="flex flex-col gap-3 sm:flex-row">
        {needsApproval === true && terms && (
          <button
            type="submit"
            className="btn btn-primary w-full sm:w-auto"
            disabled={!ready || busy}
            aria-busy={IN_FLIGHT.has(approvalState.status)}
          >
            {txLabel(
              approvalState,
              `Approve ${formatUsdcPlain(terms.amount)} USDC`,
              'Approving…',
              `Approve ${formatUsdcPlain(terms.amount)} USDC`,
            )}
          </button>
        )}
        <button
          type={needsApproval === true ? 'button' : 'submit'}
          className={`btn w-full sm:w-auto ${needsApproval === true ? 'btn-quiet' : 'btn-primary'}`}
          disabled={!ready || busy || needsApproval === true}
          aria-busy={IN_FLIGHT.has(creationState.status)}
        >
          {txLabel(creationState, 'Create retainer', 'Creating retainer…', 'Opening your retainer…')}
        </button>
      </div>

      {hash && (
        <p className="text-step--1 text-muted" role="status">
          Sent to Arc.{' '}
          <a href={explorerTxUrl(hash)} target="_blank" rel="noopener noreferrer">
            View on explorer
          </a>
        </p>
      )}
      <TxFailure state={approvalState} />
      <TxFailure state={creationState} />
      {status && (
        <p className="text-step--1 text-muted" role="status">
          {status}
        </p>
      )}
    </div>
  )
}
