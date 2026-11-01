import { NETWORK_LABEL, RETAINER_ADDRESS } from '@/app-config/contracts'
import { explorerAddressUrl, formatDate } from '@/lib/format'
import { AddressChip } from './AddressChip'
import { NoticeBanner } from './NoticeBanner'
import type { Role } from './ClaimRow'
import { UsdcAmount } from './UsdcAmount'

interface RetainerView {
  client: string
  freelancer: string
  endTime: bigint
  reserved: bigint
  totalPaid: bigint
  totalDeposited: bigint
  withdrawalAmount: bigint
  withdrawalReadyAt: bigint
}

interface RetainerSummaryProps {
  id: bigint
  r: RetainerView
  available: bigint
  ended: boolean
  role: Role
}

/** The retainer at a glance: who, until when, and where the money is. */
export function RetainerSummary({ id, r, available, ended, role }: RetainerSummaryProps) {
  const withdrawalPending = r.withdrawalReadyAt !== 0n
  const balances = [
    { label: 'Available', raw: available },
    { label: 'Reserved', raw: r.reserved },
    { label: 'Paid to date', raw: r.totalPaid },
  ]

  return (
    <section aria-labelledby="retainer-heading" className="panel perforated">
      <div className="px-5 pb-5 sm:px-6">
        <h1 id="retainer-heading" className="font-display text-step-3 font-bold">
          Retainer {id.toString()}
        </h1>
        <p className="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-muted">
          <span>{NETWORK_LABEL}</span>
          {RETAINER_ADDRESS && (
            <a href={explorerAddressUrl(RETAINER_ADDRESS)} target="_blank" rel="noopener noreferrer">
              View on explorer
            </a>
          )}
          {role !== 'visitor' && <span>You are the {role} on this retainer.</span>}
        </p>
        <dl className="mt-5 grid gap-x-10 gap-y-3 sm:grid-cols-3">
          <div className="min-w-0">
            <dt className="text-muted">Client</dt>
            <dd>
              <AddressChip address={r.client} label="client address" />
            </dd>
          </div>
          <div className="min-w-0">
            <dt className="text-muted">Freelancer</dt>
            <dd>
              <AddressChip address={r.freelancer} label="freelancer address" />
            </dd>
          </div>
          <div className="min-w-0">
            <dt className="text-muted">{ended ? 'Ended' : 'Ends'}</dt>
            <dd className="num">{formatDate(r.endTime)}</dd>
          </div>
        </dl>
      </div>

      <dl className="grid border-t border-rule sm:grid-cols-3">
        {balances.map((item) => (
          <div key={item.label} className="min-w-0 border-b border-rule px-5 py-4 last:border-b-0 sm:border-b-0 sm:border-r sm:px-6 sm:last:border-r-0">
            <dt className="text-muted">{item.label}</dt>
            <dd>
              <UsdcAmount raw={item.raw} className="font-display text-step-2 font-bold [overflow-wrap:anywhere]" />
            </dd>
          </div>
        ))}
      </dl>

      {r.totalDeposited === 0n && (
        <p className="border-t border-rule px-5 py-3 text-muted sm:px-6">
          Nothing has been deposited yet. The freelancer can't file a claim until the client tops up.
        </p>
      )}
      {ended && (
        <p className="border-t border-rule px-5 py-3 text-muted sm:px-6">
          This retainer has ended. No new claims or top-ups, and claims already filed still pay out.
        </p>
      )}
      {withdrawalPending && (
        <NoticeBanner id={id} requested={r.withdrawalAmount} readyAt={r.withdrawalReadyAt} available={available} />
      )}
    </section>
  )
}
