import { createContext, useCallback, useContext, useEffect, useRef, useState, type ReactNode } from 'react'
import { useQuery } from '@tanstack/react-query'
import { usePublicClient } from 'wagmi'
import { CHAIN_ID } from '@/app-config/contracts'

const REFETCH_MS = 10_000
/** Longest delay setTimeout can hold (about 24.8 days) is 2^31 - 1 ms; stay well under it. */
const MAX_TIMER_MS = 2_000_000_000

interface ChainTime {
  /** Unix seconds (fractional), advanced once per second between block reads. Null until the first block is read. */
  now: number | null
  isError: boolean
  /** The same clock read at this instant, for deadlines that must flip on time rather than on the next tick. */
  getNow: () => number | null
  /** Changes whenever a new block sample arrives, so timers can re-sync. */
  sampleId: number
}

const ChainTimeContext = createContext<ChainTime | null>(null)

/**
 * Chain time, not wall time (05-FRONTEND-SPEC section 8). The latest block timestamp is fetched every
 * 10 s; between fetches it advances with performance.now(), so a visitor with a wrong clock still sees
 * the right state. Every "is it payable yet" decision in the app uses this clock. One provider serves
 * the whole tree, so twenty claim rows share one query and one timer.
 */
export function ChainTimeProvider({ children }: { children: ReactNode }) {
  const client = usePublicClient({ chainId: CHAIN_ID })

  const { data: sample, isError } = useQuery({
    queryKey: ['chain-time', CHAIN_ID],
    enabled: client !== undefined,
    refetchInterval: REFETCH_MS,
    queryFn: async () => {
      if (!client) throw new Error('No RPC client for the active network')
      const block = await client.getBlock({ blockTag: 'latest' })
      return { timestamp: Number(block.timestamp), fetchedAt: performance.now() }
    },
  })

  const sampleRef = useRef(sample)
  useEffect(() => {
    sampleRef.current = sample
  }, [sample])

  const getNow = useCallback((): number | null => {
    const current = sampleRef.current
    return current ? current.timestamp + (performance.now() - current.fetchedAt) / 1000 : null
  }, [])

  // Advance the sampled block time once per second. The extrapolation lives in an effect, not in render,
  // so a re-render never produces a different "now".
  const [now, setNow] = useState<number | null>(() =>
    sample ? sample.timestamp + (performance.now() - sample.fetchedAt) / 1000 : null,
  )
  useEffect(() => {
    if (!sample) return
    const advance = () => setNow(sample.timestamp + (performance.now() - sample.fetchedAt) / 1000)
    advance()
    const timer = setInterval(advance, 1000)
    return () => clearInterval(timer)
  }, [sample])

  const value: ChainTime = { now, isError, getNow, sampleId: sample?.fetchedAt ?? 0 }
  return <ChainTimeContext.Provider value={value}>{children}</ChainTimeContext.Provider>
}

export function useChainTime(): ChainTime {
  const value = useContext(ChainTimeContext)
  if (!value) throw new Error('useChainTime must be used inside ChainTimeProvider')
  return value
}

/**
 * Whether chain time has reached `at` (unix seconds): true at t == at and after, false before, null while
 * chain time is unknown. It flips on a timer set for the exact moment, not on the one-second display tick,
 * so "payable" and "can no longer be objected to" change at payableAt, not a second later.
 */
export function usePassed(at: number): boolean | null {
  const { now, getNow, sampleId } = useChainTime()
  const [reachedAt, setReachedAt] = useState(Number.NEGATIVE_INFINITY)
  const [recheck, setRecheck] = useState(0)

  useEffect(() => {
    const current = getNow()
    if (current === null || current >= at) return
    // A few milliseconds of slack so the clock has certainly reached `at` when the timer fires. A very long
    // wait is split, because setTimeout cannot hold more than about 24.8 days.
    const delay = Math.min((at - current) * 1000 + 20, MAX_TIMER_MS)
    const timer = setTimeout(() => {
      const later = getNow()
      if (later !== null && later >= at) setReachedAt(at)
      else setRecheck((n) => n + 1)
    }, delay)
    return () => clearTimeout(timer)
  }, [at, getNow, sampleId, recheck])

  if (now === null) return null
  return now >= at || reachedAt >= at
}
