import { useEffect, useRef, useState } from 'react'
import { pad, toHex } from 'viem'
import { usePublicClient } from 'wagmi'
import { CHAIN_ID, FALLBACK_LOOKBACK_BLOCKS, RETAINER_START_BLOCK, retainerContract } from '@/app-config/contracts'
import { byNewest, toActivityItem, type ActivityItem, type RpcLogLike } from '@/lib/activity'
import { firstBlockAtOrAfter } from '@/lib/blockSearch'

/**
 * Blocks per eth_getLogs call. The public RPC answered a 5,000-block range and refused a 10,000-block
 * one when measured, so history is read in 5,000-block pieces and never in one call.
 */
const CHUNK_BLOCKS = 5000n
const PARALLEL_CHUNKS = 4
const POLL_MS = 10_000

interface ActivityState {
  items: ActivityItem[]
  /** Block timestamps by block number, for the time on each line. */
  timestamps: Record<string, number>
  /** Where reading starts: the retainer's creation block, or a recent window when that cannot be known. */
  startBlock: bigint | null
  scannedTo: bigint | null
  head: bigint | null
  /** Looking for the creation block (a binary search on block timestamps). */
  locating: boolean
  scanning: boolean
  failed: boolean
  /** True when reading started at a recent window, so older events may be missing. */
  partial: boolean
}

const INITIAL: ActivityState = {
  items: [],
  timestamps: {},
  startBlock: null,
  scannedTo: null,
  head: null,
  locating: false,
  scanning: false,
  failed: false,
  partial: false,
}

/** Scanned history and each retainer's creation block survive leaving and re-entering the page. */
const cache = new Map<string, ActivityState>()

/**
 * What a claim row may say about a note it does not have yet.
 * loading: still being read. failed: a read failed and will be retried.
 * partial: everything that could be read has been, but the history started at a recent window.
 * ready: read from the retainer's first block to the head.
 */
export type HistoryStatus = 'loading' | 'failed' | 'partial' | 'ready'

export interface Activity extends ActivityState {
  /** True once everything from startBlock up to the chain head has been read. */
  complete: boolean
  /** Blocks still to read, or null before the first head is known. */
  blocksRemaining: bigint | null
  history: HistoryStatus
}

/**
 * Events of one retainer, newest first. Activity is informational: no action is ever gated on it
 * (ADR-007). Reading starts at the retainer's creation block, found by binary search on block timestamps
 * for `createdAt` between the deployment block and the head, and there is no cap on how far that is:
 * claim notes and objection reasons exist only in events (ADR-008). Only when the deployment block is
 * unknown does it fall back to a recent window, and then `partial` is true. `refreshKey` triggers an
 * immediate read after something changed (a confirmed transaction).
 */
export function useActivity(id: bigint, createdAt: bigint | undefined, refreshKey: string): Activity {
  const client = usePublicClient({ chainId: CHAIN_ID })
  const cacheKey = `${CHAIN_ID}:${id.toString()}`
  const [state, setState] = useState<ActivityState>(() => cache.get(cacheKey) ?? INITIAL)
  const scanRef = useRef<() => Promise<void>>(() => Promise.resolve())

  useEffect(() => {
    if (!client || createdAt === undefined) return
    let cancelled = false
    let running = false
    const topic = pad(toHex(id), { size: 32 })
    const { address } = retainerContract()

    const publish = (next: ActivityState) => {
      cache.set(cacheKey, next)
      if (!cancelled) setState(next)
    }

    const timestampOf = async (blockNumber: bigint) => Number((await client.getBlock({ blockNumber })).timestamp)

    const locateStart = async (head: bigint): Promise<{ startBlock: bigint; partial: boolean }> => {
      if (RETAINER_START_BLOCK === undefined) {
        const floor = head > FALLBACK_LOOKBACK_BLOCKS ? head - FALLBACK_LOOKBACK_BLOCKS : 0n
        return { startBlock: floor, partial: true }
      }
      const startBlock = await firstBlockAtOrAfter(timestampOf, RETAINER_START_BLOCK, head, Number(createdAt))
      return { startBlock, partial: false }
    }

    const readRange = async (from: bigint, to: bigint) => {
      const logs = (await client.request({
        method: 'eth_getLogs',
        params: [{ address, fromBlock: toHex(from), toBlock: toHex(to), topics: [null, topic] }],
      })) as RpcLogLike[]
      return logs.flatMap((log) => toActivityItem(log) ?? [])
    }

    const scan = async () => {
      if (running) return
      running = true
      let local = cache.get(cacheKey) ?? INITIAL
      try {
        const head = await client.getBlockNumber()
        if (local.startBlock === null) {
          local = { ...local, head, locating: true, failed: false }
          publish(local)
          const located = await locateStart(head)
          local = { ...local, ...located, locating: false }
        }
        const startBlock = local.startBlock ?? head
        let next = local.scannedTo === null ? startBlock : local.scannedTo + 1n
        local = { ...local, head, failed: false, scanning: next <= head }
        publish(local)

        while (next <= head && !cancelled) {
          const ranges: Array<[bigint, bigint]> = []
          for (let i = 0; i < PARALLEL_CHUNKS && next <= head; i++) {
            const to = next + CHUNK_BLOCKS - 1n > head ? head : next + CHUNK_BLOCKS - 1n
            ranges.push([next, to])
            next = to + 1n
          }
          const batches = await Promise.all(ranges.map(([from, to]) => readRange(from, to)))
          const found = batches.flat()

          const timestamps = { ...local.timestamps }
          const missing = [...new Set(found.map((item) => item.blockNumber))].filter((n) => timestamps[n.toString()] === undefined)
          const blocks = await Promise.all(missing.map((blockNumber) => client.getBlock({ blockNumber })))
          blocks.forEach((block, i) => {
            const number = missing[i]
            if (number !== undefined) timestamps[number.toString()] = Number(block.timestamp)
          })

          const known = new Set(local.items.map((item) => item.key))
          const items = [...local.items, ...found.filter((item) => !known.has(item.key))].sort(byNewest)
          const lastRange = ranges[ranges.length - 1]
          local = { ...local, items, timestamps, scannedTo: lastRange ? lastRange[1] : local.scannedTo }
          publish(local)
        }
        publish({ ...local, scanning: false, locating: false })
      } catch {
        publish({ ...local, scanning: false, locating: false, failed: true })
      } finally {
        running = false
      }
    }

    scanRef.current = scan
    void scan()
    const timer = setInterval(() => void scan(), POLL_MS)
    return () => {
      cancelled = true
      clearInterval(timer)
    }
  }, [client, id, createdAt, cacheKey])

  useEffect(() => {
    void scanRef.current()
  }, [refreshKey])

  const complete =
    state.startBlock !== null && state.scannedTo !== null && state.head !== null && state.scannedTo >= state.head && !state.scanning
  const blocksRemaining =
    state.head !== null && state.scannedTo !== null ? (state.head > state.scannedTo ? state.head - state.scannedTo : 0n) : null
  const history: HistoryStatus = complete ? (state.partial ? 'partial' : 'ready') : state.failed ? 'failed' : 'loading'
  return { ...state, complete, blocksRemaining, history }
}
