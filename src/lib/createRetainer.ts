import { getAddress, type Address } from 'viem'
import { ERROR_MESSAGES } from '@/lib/error-messages'
import { formatDate, formatUsdcPlain, parseUsdcInput, shortAddress } from '@/lib/format'

/**
 * Everything the Create retainer form decides, as plain functions with no React in them.
 * The checks mirror createRetainer in the deployed contract, in the same order:
 * freelancer, objection window, withdrawal notice, end time. Amounts never touch a floating point number.
 */

const MAX_UINT128 = 2n ** 128n - 1n
const HOUR = 3_600
const DAY = 86_400

// ---------------------------------------------------------------------------------------------
// Durations
// ---------------------------------------------------------------------------------------------

export interface DurationPreset {
  id: string
  label: string
  seconds: number
}

const DEMO: DurationPreset = { id: 'demo', label: '5 minutes (demo)', seconds: 5 * 60 }

/** Objection window presets (05-FRONTEND-SPEC 4.2). 48 hours is the default. */
export const WINDOW_PRESETS: readonly DurationPreset[] = [
  DEMO,
  { id: '24h', label: '24 hours', seconds: 24 * HOUR },
  { id: '48h', label: '48 hours', seconds: 48 * HOUR },
  { id: '7d', label: '7 days', seconds: 7 * DAY },
]

/** Same presets plus 72 hours, because 72 hours is the spec's default notice and has to be selectable. */
export const NOTICE_PRESETS: readonly DurationPreset[] = [
  DEMO,
  { id: '24h', label: '24 hours', seconds: 24 * HOUR },
  { id: '48h', label: '48 hours', seconds: 48 * HOUR },
  { id: '72h', label: '72 hours', seconds: 72 * HOUR },
  { id: '7d', label: '7 days', seconds: 7 * DAY },
]

export const DEFAULT_WINDOW_ID = '48h'
export const DEFAULT_NOTICE_ID = '72h'
export const CUSTOM_ID = 'custom'

export interface DurationChoice {
  /** A preset id, or CUSTOM_ID. */
  id: string
  /** Hours typed by the person, used only when id is CUSTOM_ID. */
  customHours: string
}

export type DurationParse = { ok: true; seconds: number } | { ok: false; reason: 'empty' | 'invalid' | 'too-precise' }

/**
 * Hours with at most two decimals, as whole seconds: 0.01 hours is exactly 36 seconds, so the result is
 * always an integer and no floating point is involved.
 */
export function parseHours(text: string): DurationParse {
  const cleaned = stripInvisible(text).trim()
  if (cleaned === '') return { ok: false, reason: 'empty' }
  const match = /^(\d+)(?:\.(\d*))?$/.exec(cleaned) ?? /^\.(\d+)$/.exec(cleaned)
  if (!match) return { ok: false, reason: 'invalid' }
  const dotted = cleaned.startsWith('.')
  const whole = dotted ? '0' : (match[1] ?? '0')
  const fraction = (dotted ? match[1] : match[2]) ?? ''
  if (fraction.length > 2) return { ok: false, reason: 'too-precise' }
  // A value this long is far beyond any limit; clamp so the range check reports it.
  if (whole.length > 9) return { ok: true, seconds: Number.MAX_SAFE_INTEGER }
  const centiHours = Number(whole) * 100 + Number(fraction.padEnd(2, '0'))
  return { ok: true, seconds: centiHours * 36 }
}

export function resolveDuration(choice: DurationChoice, presets: readonly DurationPreset[]): DurationParse {
  if (choice.id === CUSTOM_ID) return parseHours(choice.customHours)
  const preset = presets.find((candidate) => candidate.id === choice.id)
  return preset ? { ok: true, seconds: preset.seconds } : { ok: false, reason: 'invalid' }
}

function plural(count: number, unit: string): string {
  return `${count} ${unit}${count === 1 ? '' : 's'}`
}

/** "5 minutes", "1 hour", "48 hours", "7 days". Hours are used up to a week, as the presets are labelled. */
export function describeSpan(seconds: number): string {
  if (seconds % HOUR === 0 && seconds < 7 * DAY) return plural(seconds / HOUR, 'hour')
  if (seconds % DAY === 0) return plural(seconds / DAY, 'day')
  if (seconds % HOUR === 0) return plural(seconds / HOUR, 'hour')
  if (seconds % 60 === 0) return plural(seconds / 60, 'minute')
  return plural(seconds, 'second')
}

// ---------------------------------------------------------------------------------------------
// Freelancer address
// ---------------------------------------------------------------------------------------------

export type FreelancerParse =
  | { ok: true; address: Address }
  | { ok: false; reason: 'empty' | 'ens' | 'prefix' | 'length' | 'invalid' | 'checksum' | 'zero' | 'self' }

/** Zero-width characters and byte-order marks come along when an address is copied from some pages. */
function stripInvisible(text: string): string {
  return text.replace(/[\u200b-\u200d\u2060\ufeff]/g, '')
}

export function parseFreelancer(text: string, connected: Address | undefined): FreelancerParse {
  const cleaned = stripInvisible(text).trim()
  if (cleaned === '') return { ok: false, reason: 'empty' }
  if (/^[^\s]+\.[a-z]{2,}$/i.test(cleaned) && !cleaned.startsWith('0x')) return { ok: false, reason: 'ens' }
  if (!/^0x/i.test(cleaned)) {
    return { ok: false, reason: /^[0-9a-f]{40}$/i.test(cleaned) ? 'prefix' : 'invalid' }
  }
  if (!cleaned.startsWith('0x')) return { ok: false, reason: 'invalid' }
  if (!/^0x[0-9a-fA-F]*$/.test(cleaned)) return { ok: false, reason: 'invalid' }
  if (cleaned.length !== 42) return { ok: false, reason: 'length' }

  // A mixed-case address carries an EIP-55 checksum, so it has to match. All lower or all upper case has none.
  const hex = cleaned.slice(2)
  const mixed = /[a-f]/.test(hex) && /[A-F]/.test(hex)
  const address = getAddress(cleaned.toLowerCase())
  if (mixed && address !== cleaned) return { ok: false, reason: 'checksum' }

  if (/^0x0{40}$/.test(cleaned)) return { ok: false, reason: 'zero' }
  if (connected !== undefined && address.toLowerCase() === connected.toLowerCase()) return { ok: false, reason: 'self' }
  return { ok: true, address }
}

export function freelancerMessage(parse: Extract<FreelancerParse, { ok: false }>, typedLength: number): string | null {
  switch (parse.reason) {
    case 'empty':
      return null
    case 'ens':
      return "Names like mara.eth aren't supported. Paste the 42-character address."
    case 'prefix':
      return 'An address starts with 0x. Paste the whole address.'
    case 'length':
      return `An address has 42 characters, including the 0x. This one has ${typedLength}.`
    case 'invalid':
      return 'An address is 0x followed by 40 letters and digits (0 to 9, a to f).'
    case 'checksum':
      return 'The capital letters in this address are wrong, which usually means a typo. Copy it again.'
    case 'zero':
      return "That's the empty address. Enter the freelancer's address."
    case 'self':
      return ERROR_MESSAGES.InvalidFreelancer
  }
}

// ---------------------------------------------------------------------------------------------
// Amount
// ---------------------------------------------------------------------------------------------

export type AmountParse =
  | { ok: true; raw: bigint }
  | { ok: false; reason: 'empty' | 'invalid' | 'comma' | 'too-precise' | 'too-large' }

/**
 * What a person typed into base units. Commas are accepted only as thousands separators in the
 * 1,000,000.50 shape; any other comma is rejected, never guessed at ("1,5" could mean 1.5 or 15).
 */
export function parseAmountText(text: string): AmountParse {
  const cleaned = stripInvisible(text).trim()
  if (cleaned === '') return { ok: false, reason: 'empty' }
  let normalized = cleaned
  if (cleaned.includes(',')) {
    if (!/^\d{1,3}(?:,\d{3})+(?:\.\d*)?$/.test(cleaned)) return { ok: false, reason: 'comma' }
    normalized = cleaned.replace(/,/g, '')
  }
  // Plain digits with one optional dot. This also rejects signs, exponents and spaces inside the number.
  if (!/^(?:\d+(?:\.\d*)?|\.\d+)$/.test(normalized)) return { ok: false, reason: 'invalid' }
  const parsed = parseUsdcInput(normalized)
  if (!parsed.ok) return { ok: false, reason: parsed.reason === 'too-precise' ? 'too-precise' : 'invalid' }
  if (parsed.raw > MAX_UINT128) return { ok: false, reason: 'too-large' }
  return { ok: true, raw: parsed.raw }
}

export function amountMessage(reason: Extract<AmountParse, { ok: false }>['reason']): string | null {
  switch (reason) {
    case 'empty':
      return null
    case 'invalid':
      return 'Enter the amount in digits, like 1250.50.'
    case 'comma':
      return 'Use a dot for decimals, like 1250.50.'
    case 'too-precise':
      return 'USDC has 6 decimal places. Remove the extra digits.'
    case 'too-large':
      return 'That amount is too large.'
  }
}

// ---------------------------------------------------------------------------------------------
// End date
// ---------------------------------------------------------------------------------------------

/** "2026-11-24" in the viewer's own time zone. */
export function toDateInputValue(date: Date): string {
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  return `${String(date.getFullYear()).padStart(4, '0')}-${month}-${day}`
}

/** The last second of the chosen local day, as unix seconds. Null when the text is not a real calendar date. */
export function endOfLocalDay(value: string): number | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value)
  if (!match) return null
  const year = Number(match[1])
  const month = Number(match[2])
  const day = Number(match[3])
  const date = new Date(year, month - 1, day, 23, 59, 59)
  if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) return null
  return Math.floor(date.getTime() / 1000)
}

// ---------------------------------------------------------------------------------------------
// The whole form
// ---------------------------------------------------------------------------------------------

export interface Limits {
  minWindow: number
  maxWindow: number
  minNotice: number
  maxNotice: number
}

export interface FormInputs {
  freelancer: string
  amount: string
  window: DurationChoice
  notice: DurationChoice
  endDate: string
}

export interface FormContext {
  connected: Address | undefined
  /** Unix seconds from the chain-time hook, or null until the first block has been read. */
  chainNow: number | null
  limits: Limits | undefined
  /** The connected wallet's USDC balance in base units, when known. */
  balance: bigint | undefined
}

export interface CreateTerms {
  freelancer: Address
  amount: bigint
  window: number
  notice: number
  endTime: number
}

export interface FieldState<T> {
  value: T | null
  /** What to show under the field, or null when there is nothing to say (including "still empty"). */
  error: string | null
  empty: boolean
}

export interface FormState {
  freelancer: FieldState<Address>
  amount: FieldState<bigint>
  window: FieldState<number>
  notice: FieldState<number>
  endDate: FieldState<number>
  /** Complete, contract-valid terms, or null. */
  terms: CreateTerms | null
  /** Why validation cannot finish yet, when it is waiting on the chain. */
  waiting: 'limits' | 'time' | null
}

function checkDuration(
  choice: DurationChoice,
  presets: readonly DurationPreset[],
  range: { min: number; max: number } | undefined,
  rangeMessage: string,
): FieldState<number> {
  const parsed = resolveDuration(choice, presets)
  if (!parsed.ok) {
    if (parsed.reason === 'empty') return { value: null, error: null, empty: true }
    const error =
      parsed.reason === 'too-precise'
        ? 'Use at most two decimal places, like 36 or 0.5.'
        : 'Enter hours as a number, like 36 or 0.5.'
    return { value: null, error, empty: false }
  }
  if (range === undefined) return { value: null, error: null, empty: false }
  if (parsed.seconds < range.min || parsed.seconds > range.max) return { value: null, error: rangeMessage, empty: false }
  return { value: parsed.seconds, error: null, empty: false }
}

export function validateForm(inputs: FormInputs, context: FormContext): FormState {
  const typedFreelancer = stripInvisible(inputs.freelancer).trim()
  const freelancerParse = parseFreelancer(inputs.freelancer, context.connected)
  const freelancer: FieldState<Address> = freelancerParse.ok
    ? { value: freelancerParse.address, error: null, empty: false }
    : {
        value: null,
        error: freelancerMessage(freelancerParse, typedFreelancer.length),
        empty: freelancerParse.reason === 'empty',
      }

  const window = checkDuration(
    inputs.window,
    WINDOW_PRESETS,
    context.limits && { min: context.limits.minWindow, max: context.limits.maxWindow },
    ERROR_MESSAGES.WindowOutOfRange,
  )
  const notice = checkDuration(
    inputs.notice,
    NOTICE_PRESETS,
    context.limits && { min: context.limits.minNotice, max: context.limits.maxNotice },
    ERROR_MESSAGES.NoticeOutOfRange,
  )

  const amountParse = parseAmountText(inputs.amount)
  let amount: FieldState<bigint>
  if (!amountParse.ok) {
    amount = { value: null, error: amountMessage(amountParse.reason), empty: amountParse.reason === 'empty' }
  } else if (context.balance !== undefined && amountParse.raw > context.balance) {
    amount = { value: null, error: "That's more than your USDC balance.", empty: false }
  } else {
    amount = { value: amountParse.raw, error: null, empty: false }
  }

  // endTime must be strictly later than now + notice, using chain time (never the visitor's clock).
  const endTime = endOfLocalDay(inputs.endDate)
  let endDate: FieldState<number>
  if (inputs.endDate === '') {
    endDate = { value: null, error: null, empty: true }
  } else if (endTime === null) {
    endDate = { value: null, error: 'Choose a date from the calendar.', empty: false }
  } else if (context.chainNow === null) {
    endDate = { value: null, error: null, empty: false }
  } else if (endTime <= Math.floor(context.chainNow)) {
    endDate = { value: null, error: 'Choose an end date in the future.', empty: false }
  } else if (notice.value !== null && endTime <= Math.floor(context.chainNow) + notice.value) {
    endDate = { value: null, error: ERROR_MESSAGES.EndTimeTooSoon, empty: false }
  } else {
    endDate = { value: endTime, error: null, empty: false }
  }

  const waiting = context.limits === undefined ? 'limits' : context.chainNow === null ? 'time' : null
  const terms =
    freelancer.value !== null &&
    amount.value !== null &&
    window.value !== null &&
    notice.value !== null &&
    endDate.value !== null
      ? {
          freelancer: freelancer.value,
          amount: amount.value,
          window: window.value,
          notice: notice.value,
          endTime: endDate.value,
        }
      : null

  return { freelancer, amount, window, notice, endDate, terms, waiting }
}

// ---------------------------------------------------------------------------------------------
// Summary sentence (01-PRODUCT vocabulary, ADR-010)
// ---------------------------------------------------------------------------------------------

/** A window this short can pay out before a client who is not watching has time to object. */
export const SHORT_WINDOW_SECONDS = HOUR

export interface Summary {
  lines: string[]
  /** Said plainly when the objection window is short (ADR-010). */
  caution: string | null
}

export function buildSummary(terms: CreateTerms): Summary {
  const freelancer = shortAddress(terms.freelancer)
  const until = formatDate(terms.endTime)
  const first =
    terms.amount > 0n
      ? `The freelancer (${freelancer}) can claim up to ${formatUsdcPlain(terms.amount)} USDC until ${until}.`
      : `You're not putting any USDC in yet, so the freelancer (${freelancer}) can't claim until you add some. Claims can be filed until ${until}.`
  return {
    lines: [
      first,
      `Each claim pays out ${describeSpan(terms.window)} after it's filed unless you object. If you stay silent, it pays out on its own.`,
      `Taking money back needs ${describeSpan(terms.notice)} of notice, and claims filed during that time are paid first.`,
    ],
    caution:
      terms.window <= SHORT_WINDOW_SECONDS
        ? `A window of ${describeSpan(terms.window)} is short. If you're not watching, a claim can pay out before you see it.`
        : null,
  }
}
