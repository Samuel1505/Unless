import { useMemo, useState } from 'react'
import type { HistoryStatus } from '@/hooks/useActivity'
import { useChainTime } from '@/hooks/useChainTime'
import { useClaims } from '@/hooks/useRetainer'
import type { ClaimDetail } from '@/lib/activity'
import type { ClaimView } from '@/lib/claims'
import { ClaimRow, type Role } from './ClaimRow'
import { EmptyState } from './EmptyState'

const PAGE = 25

const EMPTY_COPY: Record<Role, string> = {
  freelancer: 'File your first claim when work is done.',
  client: 'Claims from the freelancer will appear here.',
  visitor: 'No claim has been filed on this retainer.',
}

interface ClaimsSectionProps {
  id: bigint
  claimCount: number
  role: Role
  objectionWindow: number
  details: Map<number, ClaimDetail>
  history: HistoryStatus
}

/** Every claim, newest first. Reads are in pages of 20; the list shows 25 at a time. */
export function ClaimsSection({ id, claimCount, role, objectionWindow, details, history }: ClaimsSectionProps) {
  const claims = useClaims(id, claimCount)
  const { isError: clockFailed } = useChainTime()
  const [visible, setVisible] = useState(PAGE)

  const rows = useMemo(() => {
    if (!claims.data) return []
    const flat = claims.data.flatMap((page) => (page.status === 'success' ? (page.result as readonly ClaimView[]) : []))
    // A claim's id is its position in the oldest-first list.
    return flat.map((claim, claimId) => ({ claimId, claim })).reverse()
  }, [claims.data])

  let body
  if (claimCount === 0) {
    body = (
      <EmptyState title="No claims yet">
        <p>{EMPTY_COPY[role]}</p>
      </EmptyState>
    )
  } else if (claims.isError || claims.data?.some((page) => page.status === 'failure')) {
    body = (
      <p className="text-objected" role="alert">
        Couldn't read the claims. Check your connection and reload the page.
      </p>
    )
  } else if (!claims.data) {
    body = (
      <p className="text-muted" role="status">
        Loading claims…
      </p>
    )
  } else {
    body = (
      <>
        {clockFailed && (
          <p className="mb-3 text-step--1 text-objected" role="alert">
            Couldn't read the network time, so claim countdowns may be out of date.
          </p>
        )}
        <ul className="space-y-3">
          {rows.slice(0, visible).map(({ claimId, claim }) => (
            <ClaimRow
              key={claimId}
              id={id}
              claimId={claimId}
              claim={claim}
              role={role}
              objectionWindow={objectionWindow}
              detail={details.get(claimId)}
              history={history}
            />
          ))}
        </ul>
        {rows.length > visible && (
          <div className="mt-4">
            <button type="button" className="btn btn-quiet" onClick={() => setVisible((n) => n + PAGE)}>
              Show {Math.min(PAGE, rows.length - visible)} older claims
            </button>
          </div>
        )}
      </>
    )
  }

  return (
    <section aria-labelledby="claims-heading">
      <h2 id="claims-heading" className="mb-4 font-display text-step-2 font-bold">
        Claims
      </h2>
      {body}
    </section>
  )
}
