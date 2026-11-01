import { useMemo } from 'react'
import { useAccount } from 'wagmi'
import { NETWORK_LABEL } from '@/app-config/contracts'
import { ActivityTimeline } from '@/components/ActivityTimeline'
import type { Role } from '@/components/ClaimRow'
import { ClaimsSection } from '@/components/ClaimsSection'
import { EmptyState } from '@/components/EmptyState'
import { OwedBanner } from '@/components/OwedBanner'
import { ClientPanel, FreelancerPanel } from '@/components/RolePanels'
import { RetainerSummary } from '@/components/RetainerSummary'
import { useActivity } from '@/hooks/useActivity'
import { usePassed } from '@/hooks/useChainTime'
import { useRetainer } from '@/hooks/useRetainer'
import { claimDetails } from '@/lib/activity'
import { isRetainerNotFound } from '@/lib/errors'
import { Link } from '@/lib/router'

export function RetainerPage({ id }: { id: bigint }) {
  const retainer = useRetainer(id)
  const { address } = useAccount()

  // Anything on screen that changed on chain makes the history re-read straight away.
  const r = retainer.data?.[0]
  const refreshKey = r
    ? [r.claimCount, r.balance, r.reserved, r.totalPaid, r.totalReturned, r.totalDeposited, r.withdrawalReadyAt, r.endTime].join(':')
    : ''
  // The end moment is decided by chain time, so "ended" flips at endTime and not at the next poll.
  const endedByClock = usePassed(r ? Number(r.endTime) : Number.MAX_SAFE_INTEGER)
  const activity = useActivity(id, r?.createdAt, refreshKey)
  const details = useMemo(() => claimDetails(activity.items), [activity.items])

  if (retainer.isError) {
    if (isRetainerNotFound(retainer.error)) {
      return (
        <EmptyState
          title={`There's no retainer ${id.toString()} on ${NETWORK_LABEL}`}
          action={
            <Link to="/" className="btn btn-primary">
              Go to the start
            </Link>
          }
        >
          <p>Check the number, or start a new retainer.</p>
        </EmptyState>
      )
    }
    return (
      <EmptyState
        title="Couldn't read this retainer"
        action={
          <button type="button" className="btn btn-primary" onClick={() => void retainer.refetch()}>
            Try again
          </button>
        }
      >
        <p>The network didn't answer. Check your connection and try again.</p>
      </EmptyState>
    )
  }

  if (!retainer.data) {
    return (
      <p className="text-muted" role="status">
        Loading retainer {id.toString()}…
      </p>
    )
  }

  const [data, available, endedOnChain] = retainer.data
  const ended = endedByClock ?? endedOnChain
  // Roles come from chain data only: the connected address against the client and freelancer on chain.
  const lower = address?.toLowerCase()
  const role: Role =
    lower === data.client.toLowerCase() ? 'client' : lower === data.freelancer.toLowerCase() ? 'freelancer' : 'visitor'

  return (
    <div className="space-y-10">
      <OwedBanner account={address} />

      <RetainerSummary
        id={id}
        r={{
          client: data.client,
          freelancer: data.freelancer,
          endTime: data.endTime,
          reserved: data.reserved,
          totalPaid: data.totalPaid,
          totalDeposited: data.totalDeposited,
          withdrawalAmount: data.withdrawalAmount,
          withdrawalReadyAt: data.withdrawalReadyAt,
        }}
        available={available}
        ended={ended}
        role={role}
      />

      {role === 'client' && (
        <ClientPanel
          id={id}
          available={available}
          ended={ended}
          endTime={data.endTime}
          noticePeriod={data.noticePeriod}
          withdrawalPending={data.withdrawalReadyAt !== 0n}
          withdrawalAmount={data.withdrawalAmount}
        />
      )}
      {role === 'freelancer' && (
        <FreelancerPanel id={id} available={available} ended={ended} pendingClaims={data.pendingClaims} />
      )}

      <ClaimsSection
        id={id}
        claimCount={data.claimCount}
        role={role}
        objectionWindow={data.objectionWindow}
        details={details}
        history={activity.history}
      />

      <ActivityTimeline activity={activity} />
    </div>
  )
}
