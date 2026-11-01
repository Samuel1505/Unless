import { CLAIM_STATUS } from '@/hooks/useRetainer'
import { formatCountdown, formatDate } from '@/lib/format'

/** Claims are read this many at a time, newest first. */
export const CLAIM_PAGE = 20

interface PendingCandidate {
  payableAt: number
  status: number
}

/**
 * The earliest payableAt among the Pending claims of one retainer, found without reading more than it
 * has to. Pending claims are mostly recent, so pages are read from the newest backwards, and reading stops
 * as soon as `pendingClaims` pending claims (the count the retainer itself reports) have been seen.
 * A retainer with no pending claims reads nothing.
 */
export async function earliestPendingPayableAt(
  readPage: (offset: number, limit: number) => Promise<readonly PendingCandidate[]>,
  claimCount: number,
  pendingClaims: number,
): Promise<{ payableAt: number | undefined; pagesRead: number }> {
  let found = 0
  let pagesRead = 0
  let earliest: number | undefined
  let end = claimCount
  while (found < pendingClaims && end > 0) {
    const offset = Math.max(0, end - CLAIM_PAGE)
    const page = await readPage(offset, end - offset)
    pagesRead += 1
    for (const claim of page) {
      if (claim.status !== CLAIM_STATUS.Pending) continue
      found += 1
      earliest = earliest === undefined ? claim.payableAt : Math.min(earliest, claim.payableAt)
    }
    end = offset
  }
  return { payableAt: earliest, pagesRead }
}

export type NextEventKind = 'claim' | 'withdrawal' | 'end'

export interface NextEvent {
  kind: NextEventKind
  at: number
  /** True when it has already happened: a claim ready to pay out, a withdrawal ready to complete. */
  due: boolean
}

interface NextEventInput {
  /** Chain time, unix seconds. */
  now: number
  /** The earliest payableAt among Pending claims, if there are any. */
  claimPayableAt: number | undefined
  /** withdrawalReadyAt, or 0 when no withdrawal is pending. */
  withdrawalReadyAt: number
  endTime: number
  ended: boolean
}

/**
 * What happens next on a retainer: the earliest future one of a pending claim becoming payable, a
 * withdrawal becoming ready, and the end date (if it has not passed). Something that is already due
 * (a claim ready to pay out, a withdrawal ready to complete) is waiting for someone to act, so it wins
 * over anything in the future.
 */
export function nextEvent(input: NextEventInput): NextEvent | null {
  const { now, claimPayableAt, withdrawalReadyAt, endTime, ended } = input
  const due: NextEvent[] = []
  const future: NextEvent[] = []
  const place = (kind: NextEventKind, at: number | undefined, canBeDue: boolean) => {
    if (at === undefined) return
    if (canBeDue && at <= now) due.push({ kind, at, due: true })
    else if (at > now) future.push({ kind, at, due: false })
  }
  place('claim', claimPayableAt, true)
  place('withdrawal', withdrawalReadyAt === 0 ? undefined : withdrawalReadyAt, true)
  if (!ended) place('end', endTime, false)
  const byTime = (a: NextEvent, b: NextEvent) => a.at - b.at
  return [...due].sort(byTime)[0] ?? [...future].sort(byTime)[0] ?? null
}

/** "Claim pays out in 3m 12s", "Withdrawal ready in 2d 4h", "Ends 24 Nov 2026", "Claim ready to pay out". */
export function describeNextEvent(event: NextEvent, now: number): string {
  const left = formatCountdown(event.at - Math.floor(now))
  switch (event.kind) {
    case 'claim':
      return event.due ? 'Claim ready to pay out' : `Claim pays out in ${left}`
    case 'withdrawal':
      return event.due ? 'Withdrawal ready to complete' : `Withdrawal ready in ${left}`
    case 'end':
      return `Ends ${formatDate(event.at)}`
  }
}
