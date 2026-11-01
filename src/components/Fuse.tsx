import type { ClaimPhase } from '@/lib/claims'

interface FuseProps {
  phase: ClaimPhase
  /** Unix seconds when the claim becomes payable. */
  payableAt: number
  /** The retainer's objection window in seconds: the fuse's full length. */
  window: number
  /** Chain time in unix seconds, updated once per second. */
  now: number | null
  /** True for the one moment a confirmed payout fills the bar. */
  fill: boolean
}

/**
 * A claim's objection window drawn as a line that burns down to payout (05-FRONTEND-SPEC 5.3).
 * Length is (payableAt - chainNow) / objectionWindow, written as transform: scaleX() on its own layer,
 * once per second. At zero it is a solid settled bar. It carries no meaning on its own: the countdown
 * is always written as text next to it, so the whole component is hidden from assistive tech.
 */
export function Fuse({ phase, payableAt, window, now, fill }: FuseProps) {
  let scale = 1
  if (phase === 'open' && now !== null && window > 0) {
    const left = Math.max(0, payableAt - Math.floor(now))
    scale = Math.min(1, left / window)
  }
  const state = phase === 'open' ? 'open' : phase === 'payable' ? 'payable' : phase === 'paid' ? 'paid' : 'ended'

  return (
    <div className="fuse" data-state={state} data-fill={fill ? 'true' : 'false'} aria-hidden="true">
      <div className="fuse-bar" style={{ transform: `scaleX(${scale})` }} />
    </div>
  )
}
