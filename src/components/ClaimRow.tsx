import { useState } from 'react'
import { retainerContract } from '@/app-config/contracts'
import type { HistoryStatus } from '@/hooks/useActivity'
import { useChainTime, usePassed } from '@/hooks/useChainTime'
import type { ClaimDetail } from '@/lib/activity'
import { claimPhase, isApprovedNow, type ClaimPhase, type ClaimView } from '@/lib/claims'
import { explorerTxUrl, formatCountdown, formatDateTime, formatUsdcPlain } from '@/lib/format'
import { ApproveNowDialog, ObjectDialog } from './ClaimDialogs'
import { Fuse } from './Fuse'
import { TxButton } from './TxButton'
import { UsdcAmount } from './UsdcAmount'

export type Role = 'client' | 'freelancer' | 'visitor'

interface ClaimRowProps {
  id: bigint
  claimId: number
  claim: ClaimView
  role: Role
  objectionWindow: number
  /** What the events say about this claim. Undefined while history is still loading. */
  detail: ClaimDetail | undefined
  /** How far reading the events has got, so a note still loading is never shown as a claim with no note. */
  history: HistoryStatus
}

/**
 * Notes and reasons exist only in events (ADR-008). Until the event has been read there is nothing to
 * show, and saying nothing would look like a claim with no note, so each unread state says what is going on.
 */
function missingText(kind: 'note' | 'reason', history: HistoryStatus): string {
  const word = kind === 'note' ? 'note' : 'reason'
  switch (history) {
    case 'loading':
      return `Loading ${word}…`
    case 'failed':
      return `Couldn't load this ${word} just now. It will try again.`
    case 'partial':
      return `This ${word} is not in the recent history this app reads, so it can't be shown. History may be incomplete.`
    default:
      return `This ${word} could not be found in the history of this retainer.`
  }
}

/** What a screen reader hears when the state changes. It changes on transitions, never on each tick. */
function announcement(claimId: number, phase: ClaimPhase | null, approved: boolean): string {
  switch (phase) {
    case 'open':
      return `Claim ${claimId} is in its objection window.`
    case 'payable':
      return `Claim ${claimId} is ready to pay out.`
    case 'paid':
      return approved ? `Claim ${claimId} was approved by the client.` : `Claim ${claimId} was paid out.`
    case 'objected':
      return `The client objected to claim ${claimId}.`
    case 'cancelled':
      return `The freelancer cancelled claim ${claimId}.`
    default:
      return ''
  }
}

export function ClaimRow({ id, claimId, claim, role, objectionWindow, detail, history }: ClaimRowProps) {
  const payableAt = Number(claim.payableAt)
  // Payable at t == payableAt and after; objectable only before it. Both read the same moment.
  const payable = usePassed(payableAt)
  const { now } = useChainTime()
  const phase = claimPhase(claim, payable)

  // The stamp animates only for a payout seen happening while this row is on screen.
  const [seen, setSeen] = useState<ClaimPhase | null>(phase)
  const [justPaid, setJustPaid] = useState(false)
  if (phase !== seen) {
    setSeen(phase)
    if (phase === 'paid' && (seen === 'open' || seen === 'payable')) setJustPaid(true)
  }

  const amount = formatUsdcPlain(claim.amount)
  const contract = retainerContract()
  const left = now === null ? null : Math.max(0, payableAt - Math.floor(now))

  let status: React.ReactNode
  switch (phase) {
    case 'open':
      status = left === null ? 'Reading network time…' : `Pays out in ${formatCountdown(left)}`
      break
    case 'payable':
      status = (
        <>
          <span className="punch" aria-hidden="true" />
          Ready to pay out. The window ended {formatDateTime(payableAt)}.
        </>
      )
      break
    case 'paid':
      status = isApprovedNow(claim) ? 'Approved by client' : 'Paid out, no objection'
      break
    case 'objected':
      status = 'Client objected'
      break
    case 'cancelled':
      status = 'Cancelled by freelancer'
      break
    default:
      status = phase === null ? 'Reading network time…' : 'Unknown'
  }

  return (
    <li className="panel perforated px-5 pb-4 sm:px-6">
      <div className="flex flex-wrap items-baseline justify-between gap-x-6 gap-y-1">
        <h3 className="font-display text-step-1 font-bold">Claim {claimId}</h3>
        <UsdcAmount raw={claim.amount} className="text-step-1" />
        {phase === 'paid' && (
          <span className="stamp" data-enter={justPaid ? 'true' : 'false'}>
            Paid
          </span>
        )}
      </div>

      <div className="mt-3">
        <Fuse phase={phase ?? 'open'} payableAt={payableAt} window={objectionWindow} now={now} fill={justPaid} />
      </div>
      <p className="mt-2 text-muted num [overflow-wrap:anywhere]">{status}</p>
      <span className="sr-only" role="status" aria-live="polite">
        {announcement(claimId, phase, isApprovedNow(claim))}
      </span>

      {detail?.note === undefined ? (
        <p className="mt-2 text-step--1 text-muted" role={history === 'loading' ? 'status' : undefined}>
          {missingText('note', history)}
        </p>
      ) : (
        detail.note !== '' && <p className="mt-2 whitespace-pre-wrap [overflow-wrap:anywhere]">{detail.note}</p>
      )}
      {phase === 'objected' &&
        (detail?.reason === undefined ? (
          <p className="mt-2 text-step--1 text-muted">{missingText('reason', history)}</p>
        ) : (
          detail.reason !== '' && (
            <p className="mt-2 whitespace-pre-wrap [overflow-wrap:anywhere]">
              <span className="text-muted">Reason: </span>
              {detail.reason}
            </p>
          )
        ))}
      <p className="mt-2 text-step--1 text-muted">
        Filed {formatDateTime(claim.filedAt)}
        {detail?.paidTx && (
          <>
            {' · '}
            <a href={explorerTxUrl(detail.paidTx)} target="_blank" rel="noopener noreferrer">
              View payout on explorer
            </a>
          </>
        )}
      </p>

      {(phase === 'open' || phase === 'payable') && (
        <div className="mt-3 flex flex-wrap items-start gap-3">
          {phase === 'payable' && (
            <TxButton
              label={`Pay out ${amount} USDC`}
              className="btn btn-primary"
              call={{ ...contract, functionName: 'payOutClaim', args: [id, BigInt(claimId)] }}
            />
          )}
          {role === 'client' && <ApproveNowDialog id={id} claimId={claimId} amount={claim.amount} />}
          {role === 'client' && phase === 'open' && <ObjectDialog id={id} claimId={claimId} amount={claim.amount} />}
          {role === 'freelancer' && (
            <TxButton
              label={`Cancel ${amount} USDC claim`}
              call={{ ...contract, functionName: 'cancelClaim', args: [id, BigInt(claimId)] }}
            />
          )}
        </div>
      )}
    </li>
  )
}
