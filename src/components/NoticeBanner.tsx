import { retainerContract } from '@/app-config/contracts'
import { useChainTime, usePassed } from '@/hooks/useChainTime'
import { formatCountdown, formatUsdcPlain } from '@/lib/format'
import { TxButton } from './TxButton'

interface NoticeBannerProps {
  id: bigint
  requested: bigint
  readyAt: bigint
  available: bigint
}

/**
 * A pending withdrawal, for everyone to see. Nothing is held back during the notice, so what comes back
 * is the smaller of what was asked and what is still available when it completes. Once the notice has
 * ended, anyone can complete it.
 */
export function NoticeBanner({ id, requested, readyAt, available }: NoticeBannerProps) {
  const ready = usePassed(Number(readyAt))
  const { now } = useChainTime()
  const payout = requested <= available ? requested : available
  const left = now === null ? null : Math.max(0, Number(readyAt) - Math.floor(now))

  return (
    <div className="enter-fade border-t border-rule px-5 py-4 sm:px-6" style={{ background: 'color-mix(in srgb, var(--carbon) 8%, transparent)' }}>
      <p>
        The client asked to take back {formatUsdcPlain(requested)} USDC.{' '}
        {ready
          ? 'The notice has ended, so the withdrawal can be completed now.'
          : left === null
            ? 'It completes when the withdrawal notice ends.'
            : `It completes in ${formatCountdown(left)}.`}{' '}
        {ready && payout < requested
          ? `Claims filed in the meantime come first, so ${formatUsdcPlain(payout)} USDC would go back now.`
          : 'Claims filed before then are still paid.'}
      </p>
      <span className="sr-only" role="status" aria-live="polite">
        {ready ? 'The withdrawal can now be completed.' : ''}
      </span>
      {ready && (
        <div className="mt-3">
          <TxButton
            label={payout === 0n ? 'Complete withdrawal (nothing is left to return)' : `Complete withdrawal of ${formatUsdcPlain(payout)} USDC`}
            className="btn btn-primary"
            call={{ ...retainerContract(), functionName: 'completeWithdrawal', args: [id] }}
          />
        </div>
      )}
    </div>
  )
}
