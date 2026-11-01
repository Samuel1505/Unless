/**
 * Exact decimal handling for token amounts. Nothing here goes through a floating point number, and
 * nothing rounds: too many digits is an error, not a silent cut.
 */

export type AmountErrorCode = 'INVALID_NUMBER' | 'TOO_MANY_FRACTION_DIGITS'

export class AmountError extends Error {
  readonly code: AmountErrorCode

  constructor(code: AmountErrorCode, message: string) {
    super(message)
    this.name = 'AmountError'
    this.code = code
  }
}

const PLAIN_DECIMAL = /^(?:\d+(?:\.\d*)?|\.\d+)$/

/** "12.5" with 6 decimals is 12500000n. Rejects signs, exponents and any digit beyond `decimals`. */
export function parseUnitsExact(value: string, decimals: number): bigint {
  const trimmed = value.trim()
  if (!PLAIN_DECIMAL.test(trimmed)) {
    throw new AmountError('INVALID_NUMBER', `'${value}' is not a plain decimal number`)
  }
  const [whole = '', fraction = ''] = trimmed.split('.')
  if (fraction.length > decimals) {
    throw new AmountError('TOO_MANY_FRACTION_DIGITS', `'${value}' has ${fraction.length} fraction digits but the token has ${decimals}`)
  }
  return BigInt(`${whole === '' ? '0' : whole}${fraction.padEnd(decimals, '0')}`)
}

/** Every digit, without trailing zeros: 3000000n -> "3", 1284500000n -> "1284.5", 1n -> "0.000001". */
export function formatUnitsExact(raw: bigint, decimals: number): string {
  const digits = raw.toString().padStart(decimals + 1, '0')
  const whole = digits.slice(0, digits.length - decimals)
  const fraction = digits.slice(digits.length - decimals).replace(/0+$/, '')
  return fraction === '' ? whole : `${whole}.${fraction}`
}

/** A fixed number of decimals, cut off rather than rounded: 999999n at 2 places is "0.99", never "1.00". */
export function formatUnitsFixed(raw: bigint, decimals: number, fractionDigits: number): string {
  const digits = raw.toString().padStart(decimals + 1, '0')
  const whole = digits.slice(0, digits.length - decimals)
  const fraction = digits.slice(digits.length - decimals).padEnd(fractionDigits, '0').slice(0, fractionDigits)
  return fractionDigits === 0 ? whole : `${whole}.${fraction}`
}
