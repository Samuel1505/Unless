import { ACTIVE_FACTS } from '@/app-config/contracts'
import { AmountError, formatUnitsExact, formatUnitsFixed, parseUnitsExact } from '@/lib/money'

/** USDC as people use it: the 6-decimal ERC-20 view. Never the 18-decimal native gas view. */
const USDC_DECIMALS = ACTIVE_FACTS.usdc.decimals

/** "1,284.50": thousands separators on the whole part only, for reading; never fed back into a parser. */
function groupThousands(decimal: string): string {
  const [whole = '0', fraction] = decimal.split('.')
  const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ',')
  return fraction === undefined ? grouped : `${grouped}.${fraction}`
}

/** "3.00": exactly two decimals, never rounded up, with thousands separators. */
export function formatUsdcFixed(raw: bigint): string {
  return groupThousands(formatUnitsFixed(raw, USDC_DECIMALS, 2))
}

/** Full precision, used for the tooltip when the value has more than two decimals. */
export function formatUsdcFull(raw: bigint): string {
  return formatUnitsExact(raw, USDC_DECIMALS)
}

export function hasExtraPrecision(raw: bigint): boolean {
  const extraDigits = USDC_DECIMALS - 2
  return raw % 10n ** BigInt(extraDigits) !== 0n
}

/**
 * For sentences and button labels, where there is no tooltip: two decimals, unless the value has more,
 * in which case the exact value is shown. 0.000001 USDC never reads as "0.00 USDC".
 */
export function formatUsdcPlain(raw: bigint): string {
  return hasExtraPrecision(raw) ? groupThousands(formatUsdcFull(raw)) : formatUsdcFixed(raw)
}

export type ParsedUsdcInput = { ok: true; raw: bigint } | { ok: false; reason: 'empty' | 'invalid' | 'too-precise' }

/** Parses what a person typed into base units. Never goes through a floating point number. */
export function parseUsdcInput(text: string): ParsedUsdcInput {
  const trimmed = text.trim()
  if (trimmed === '') return { ok: false, reason: 'empty' }
  try {
    return { ok: true, raw: parseUnitsExact(trimmed, USDC_DECIMALS) }
  } catch (error: unknown) {
    if (error instanceof AmountError && error.code === 'TOO_MANY_FRACTION_DIGITS') {
      return { ok: false, reason: 'too-precise' }
    }
    return { ok: false, reason: 'invalid' }
  }
}

/** 0x7C3a…9F22 */
export function shortAddress(address: string): string {
  return `${address.slice(0, 6)}…${address.slice(-4)}`
}

export function explorerAddressUrl(address: string): string {
  return `${ACTIVE_FACTS.explorerBase}/address/${address}`
}

export function explorerTxUrl(hash: string): string {
  return `${ACTIVE_FACTS.explorerBase}/tx/${hash}`
}

/** "4m 08s", "1h 02m", "2d 4h". Rounds down; 0 or less reads "0s". */
export function formatCountdown(totalSeconds: number): string {
  const s = Math.max(0, Math.floor(totalSeconds))
  const days = Math.floor(s / 86_400)
  const hours = Math.floor((s % 86_400) / 3_600)
  const minutes = Math.floor((s % 3_600) / 60)
  const seconds = s % 60
  if (days > 0) return `${days}d ${hours}h`
  if (hours > 0) return `${hours}h ${String(minutes).padStart(2, '0')}m`
  if (minutes > 0) return `${minutes}m ${String(seconds).padStart(2, '0')}s`
  return `${seconds}s`
}

const dateFormat = new Intl.DateTimeFormat('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })
const dateTimeFormat = new Intl.DateTimeFormat('en-GB', {
  day: 'numeric',
  month: 'short',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
})

export function formatDate(unixSeconds: bigint | number): string {
  return dateFormat.format(new Date(Number(unixSeconds) * 1000))
}

export function formatDateTime(unixSeconds: bigint | number): string {
  return dateTimeFormat.format(new Date(Number(unixSeconds) * 1000))
}
