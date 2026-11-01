import { formatUsdcFixed, formatUsdcFull, hasExtraPrecision } from '@/lib/format'

/** Past this many characters the number may break across lines instead of running off a narrow screen. */
const KEEP_TOGETHER_UP_TO = 16

/** "3.00 USDC", two decimals, tabular digits. Full precision is in the tooltip when there is more. */
export function UsdcAmount({ raw, className = '' }: { raw: bigint; className?: string }) {
  const text = formatUsdcFixed(raw)
  return (
    <span className={`num [overflow-wrap:anywhere] ${className}`} title={hasExtraPrecision(raw) ? `${formatUsdcFull(raw)} USDC` : undefined}>
      <span className={text.length <= KEEP_TOGETHER_UP_TO ? 'whitespace-nowrap' : undefined}>{text}</span> USDC
    </span>
  )
}
