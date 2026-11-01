import { UsdcAmount } from '@/components/UsdcAmount'
import { useChainTime } from '@/hooks/useChainTime'
import { useNextClaim } from '@/hooks/useNextClaim'
import { formatDate, formatUsdcPlain, shortAddress } from '@/lib/format'
import { describeNextEvent, nextEvent } from '@/lib/nextEvent'
import { Link } from '@/lib/router'

interface RetainerRowData {
  client: string
  freelancer: string
  endTime: bigint
  reserved: bigint
  claimCount: number
  pendingClaims: number
  totalDeposited: bigint
  withdrawalReadyAt: bigint
}

interface RetainerRowProps {
  id: bigint
  /** Whose address to show next to the retainer: the other party. */
  counterparty: 'client' | 'freelancer'
  /** The live state from getRetainer, or undefined while it is being read. */
  data: { r: RetainerRowData; available: bigint; ended: boolean } | undefined
  /** True when reading this retainer failed. */
  failed: boolean
}

/** One retainer in a list. The whole row is a link and a pressable (05-FRONTEND-SPEC 5.5). */
export function RetainerRow({ id, counterparty, data, failed }: RetainerRowProps) {
  const { now } = useChainTime()
  // Claims are read only for a row that is on screen (it exists) and has pending claims.
  const claims = useNextClaim(id, data?.r.claimCount ?? 0, data?.r.pendingClaims ?? 0, data !== undefined)

  const facts: string[] = []
  let next: string | null = null
  if (data) {
    const { r, ended } = data
    facts.push(r.pendingClaims === 0 ? 'No claims waiting' : `${r.pendingClaims} ${r.pendingClaims === 1 ? 'claim' : 'claims'} waiting`)
    if (r.reserved > 0n) facts.push(`${formatUsdcPlain(r.reserved)} USDC reserved`)
    if (ended) facts.push(`Ended ${formatDate(r.endTime)}`)
    if (r.withdrawalReadyAt !== 0n) facts.push('Withdrawal pending')
    if (r.totalDeposited === 0n) facts.push('Nothing deposited yet')

    const claimsLoading = r.pendingClaims > 0 && claims.data === undefined && !claims.isError
    if (now === null || claimsLoading) {
      next = 'Checking what happens next…'
    } else {
      const event = nextEvent({
        now,
        claimPayableAt: claims.data?.payableAt,
        withdrawalReadyAt: Number(r.withdrawalReadyAt),
        endTime: Number(r.endTime),
        ended,
      })
      next = event ? describeNextEvent(event, now) : null
      if (claims.isError) next = `${next ?? 'Nothing else is scheduled'}. The next claim time couldn't be read.`
    }
  }

  return (
    <li>
      <Link
        to={`/r/${id.toString()}`}
        className="panel perforated pressable pressable-row block px-5 pb-4 text-ink no-underline sm:px-6"
      >
        <span className="flex flex-wrap items-baseline justify-between gap-x-6 gap-y-1">
          <span className="font-display text-step-1 font-bold">Retainer {id.toString()}</span>
          {data && (
            <span className="min-w-0">
              <UsdcAmount raw={data.available} className="font-bold" /> <span className="text-muted">available</span>
            </span>
          )}
        </span>
        {data ? (
          <>
            <span className="mt-1 block text-muted [overflow-wrap:anywhere]">
              {counterparty === 'freelancer' ? 'Freelancer' : 'Client'}{' '}
              <span className="num">{shortAddress(counterparty === 'freelancer' ? data.r.freelancer : data.r.client)}</span>
            </span>
            <span className="mt-1 block text-muted num [overflow-wrap:anywhere]">{facts.join(' · ')}</span>
            {next && <span className="mt-1 block font-bold num [overflow-wrap:anywhere]">{next}</span>}
          </>
        ) : (
          <span className="mt-1 block text-muted" role={failed ? undefined : 'status'}>
            {failed ? "Couldn't read this retainer just now." : 'Loading…'}
          </span>
        )}
      </Link>
    </li>
  )
}
