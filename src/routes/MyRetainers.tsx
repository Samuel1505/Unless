import { useMemo, useState } from 'react'
import { useAccount } from 'wagmi'
import { EmptyState } from '@/components/EmptyState'
import { RetainerRow } from '@/components/RetainerRow'
import { WalletGate } from '@/components/WalletGate'
import { useMyRetainerIds, useRetainerSummaries } from '@/hooks/useRetainer'
import { Link } from '@/lib/router'

/** How many retainers a list shows at first. Only the ones on screen are read for their live state. */
const PAGE = 25

export function MyRetainers() {
  return (
    <div>
      <h1 className="mb-8 font-display text-step-3 font-bold">My retainers</h1>
      <WalletGate needed="Connect the wallet you fund retainers from, or the one you are paid to.">
        <MyList />
      </WalletGate>
    </div>
  )
}

function MyList() {
  const { address } = useAccount()
  const idLists = useMyRetainerIds(address)
  const [funded, setFunded] = useState(PAGE)
  const [paidFrom, setPaidFrom] = useState(PAGE)

  // Ids come back oldest first; people look for the newest first.
  const { fundedIds, paidFromIds } = useMemo(() => {
    const read = (index: number) => {
      const entry = idLists.data?.[index]
      return entry?.status === 'success' ? [...entry.result].reverse() : []
    }
    return { fundedIds: read(0), paidFromIds: read(1) }
  }, [idLists.data])

  const shownFunded = fundedIds.slice(0, funded)
  const shownPaidFrom = paidFromIds.slice(0, paidFrom)
  const toRead = useMemo(
    () => [...new Set([...fundedIds.slice(0, funded), ...paidFromIds.slice(0, paidFrom)])],
    [fundedIds, paidFromIds, funded, paidFrom],
  )
  const summaries = useRetainerSummaries(toRead)
  const position = useMemo(() => new Map(toRead.map((id, index) => [id.toString(), index])), [toRead])

  if (idLists.isError || idLists.data?.some((entry) => entry.status === 'failure')) {
    return (
      <EmptyState
        title="Couldn't read your retainers"
        action={
          <button type="button" className="btn btn-primary" onClick={() => void idLists.refetch()}>
            Try again
          </button>
        }
      >
        <p>The network didn't answer. Check your connection and try again.</p>
      </EmptyState>
    )
  }

  if (!idLists.data) {
    return (
      <p className="text-muted" role="status">
        Loading your retainers…
      </p>
    )
  }

  if (fundedIds.length === 0 && paidFromIds.length === 0) {
    return (
      <EmptyState
        title="You don't have any retainers yet"
        action={
          <Link to="/new" className="btn btn-primary">
            Start a retainer
          </Link>
        }
      >
        <p>Retainers you fund, or are paid from, will be listed here.</p>
      </EmptyState>
    )
  }

  const rows = (ids: bigint[], counterparty: 'freelancer' | 'client') =>
    ids.map((id) => {
      const entry = summaries.data?.[position.get(id.toString()) ?? -1]
      const loaded = entry?.status === 'success' ? entry.result : undefined
      return (
        <RetainerRow
          key={id.toString()}
          id={id}
          counterparty={counterparty}
          data={loaded ? { r: loaded[0], available: loaded[1], ended: loaded[2] } : undefined}
          failed={entry?.status === 'failure' || summaries.isError}
        />
      )
    })

  const more = (total: number, shown: number, grow: () => void) =>
    total > shown && (
      <div className="mt-4">
        <button type="button" className="btn btn-quiet" onClick={grow}>
          Show {Math.min(PAGE, total - shown)} older {total - shown === 1 ? 'retainer' : 'retainers'}
        </button>
      </div>
    )

  return (
    <div className="space-y-10">
      {fundedIds.length > 0 && (
        <section aria-labelledby="funded-heading">
          <h2 id="funded-heading" className="mb-4 font-display text-step-2 font-bold">
            You fund <span className="num text-muted">({fundedIds.length})</span>
          </h2>
          <ul className="space-y-3">{rows(shownFunded, 'freelancer')}</ul>
          {more(fundedIds.length, shownFunded.length, () => setFunded((n) => n + PAGE))}
        </section>
      )}
      {paidFromIds.length > 0 && (
        <section aria-labelledby="paid-from-heading">
          <h2 id="paid-from-heading" className="mb-4 font-display text-step-2 font-bold">
            You're paid from <span className="num text-muted">({paidFromIds.length})</span>
          </h2>
          <ul className="space-y-3">{rows(shownPaidFrom, 'client')}</ul>
          {more(paidFromIds.length, shownPaidFrom.length, () => setPaidFrom((n) => n + PAGE))}
        </section>
      )}
    </div>
  )
}
