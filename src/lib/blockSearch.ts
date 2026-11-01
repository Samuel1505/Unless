/**
 * The first block in [low, high] whose timestamp is at or after `target`.
 *
 * Block timestamps never go down but they can repeat: Arc can seal several blocks with the same
 * second. A plain "find the block with this timestamp" would land anywhere inside such a run, so this
 * is a lower-bound search: it always returns the first block of the run, which is the safe place to
 * start reading history because nothing relevant can be before it.
 *
 * It takes about log2(high - low) lookups (26 for 69 million blocks). If even `high` is before
 * `target` it returns `high`, the best start there is.
 */
export async function firstBlockAtOrAfter(
  timestampOf: (blockNumber: bigint) => Promise<number>,
  low: bigint,
  high: bigint,
  target: number,
): Promise<bigint> {
  if (high < low) return low
  let lo = low
  let hi = high
  while (lo < hi) {
    const mid = lo + (hi - lo) / 2n
    if ((await timestampOf(mid)) >= target) hi = mid
    else lo = mid + 1n
  }
  return lo
}
