import type { Activity } from '@/hooks/useActivity'
import { describeActivity } from '@/lib/activity'
import { explorerTxUrl, formatDateTime } from '@/lib/format'

/**
 * Every event of this retainer with its time and a link to the transaction. It is informational: it
 * says what happened, and no button anywhere depends on it.
 */
export function ActivityTimeline({ activity }: { activity: Activity }) {
  const { items, timestamps, complete, failed, scanning, locating, blocksRemaining, partial } = activity

  return (
    <section aria-labelledby="activity-heading">
      <h2 id="activity-heading" className="mb-4 font-display text-step-2 font-bold">
        Activity
      </h2>

      {locating && (
        <p className="mb-3 text-muted" role="status">
          Finding where this retainer's history starts…
        </p>
      )}
      {scanning && blocksRemaining !== null && blocksRemaining > 0n && (
        <p className="mb-3 text-muted num" role="status">
          Reading history. {Number(blocksRemaining).toLocaleString('en-GB')} blocks left.
        </p>
      )}
      {failed && (
        <p className="mb-3 text-step--1 text-objected" role="alert">
          Couldn't read all of the history just now. It will try again.
        </p>
      )}
      {partial && (
        <p className="mb-3 text-muted">
          History may be incomplete. This app doesn't know when the retainer service was set up, so it reads only the
          most recent blocks. Older events, and the notes and reasons in them, may be missing.
        </p>
      )}

      {items.length === 0 ? (
        complete && <p className="text-muted">No events in the history shown here.</p>
      ) : (
        <ol className="border-t border-rule">
          {items.map((item) => {
            const line = describeActivity(item.event)
            const at = timestamps[item.blockNumber.toString()]
            return (
              <li key={item.key} className="grid gap-x-6 gap-y-1 border-b border-rule py-3 sm:grid-cols-[11rem_1fr]">
                <span className="text-muted num">
                  {at === undefined ? `Block ${item.blockNumber.toString()}` : <time dateTime={new Date(at * 1000).toISOString()}>{formatDateTime(at)}</time>}
                </span>
                <div className="min-w-0">
                  <p className="[overflow-wrap:anywhere]">{line.text}</p>
                  {line.detail && <p className="mt-1 whitespace-pre-wrap text-muted [overflow-wrap:anywhere]">{line.detail}</p>}
                  <a href={explorerTxUrl(item.transactionHash)} target="_blank" rel="noopener noreferrer" className="text-step--1">
                    View transaction on explorer
                  </a>
                </div>
              </li>
            )
          })}
        </ol>
      )}
    </section>
  )
}
