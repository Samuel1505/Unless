import { BaseError, ContractFunctionRevertedError, toFunctionSelector } from 'viem'
import { ERROR_MESSAGES, GENERIC_MESSAGES, type RetainerErrorName } from './error-messages'

export type DescribedError =
  | { kind: 'rejected'; message: string }
  | { kind: 'retainer'; name: RetainerErrorName; message: string }
  | { kind: 'token' | 'fee' | 'unknown'; message: string }

// Revert selectors of the standard ERC-20 errors a token can raise inside transferFrom.
const TOKEN_ERROR_SELECTORS = new Set<string>([
  toFunctionSelector('ERC20InsufficientAllowance(address,uint256,uint256)'),
  toFunctionSelector('ERC20InsufficientBalance(address,uint256,uint256)'),
])

function isRetainerError(name: string | undefined): name is RetainerErrorName {
  return name !== undefined && Object.prototype.hasOwnProperty.call(ERROR_MESSAGES, name)
}

function hasCode(value: unknown, code: number): boolean {
  return typeof value === 'object' && value !== null && (value as { code?: unknown }).code === code
}

/**
 * Turns anything a wallet or RPC can throw into one human message.
 * A wallet rejection is reported as `rejected`: it is not an error and callers reset quietly.
 */
export function describeError(error: unknown): DescribedError {
  if (error instanceof BaseError) {
    const rejection = error.walk((e) => hasCode(e, 4001) || /user rejected|user denied/i.test(String((e as Error).message)))
    if (rejection) return { kind: 'rejected', message: GENERIC_MESSAGES.userRejected }

    const revert = error.walk((e) => e instanceof ContractFunctionRevertedError)
    if (revert instanceof ContractFunctionRevertedError) {
      const name = revert.data?.errorName
      if (isRetainerError(name)) return { kind: 'retainer', name, message: ERROR_MESSAGES[name] }
      const selector = revert.raw?.slice(0, 10).toLowerCase()
      if (selector && TOKEN_ERROR_SELECTORS.has(selector)) {
        return { kind: 'token', message: GENERIC_MESSAGES.tokenAllowanceOrBalance }
      }
      if (/allowance|exceeds balance|insufficient balance/i.test(revert.reason ?? revert.shortMessage)) {
        return { kind: 'token', message: GENERIC_MESSAGES.tokenAllowanceOrBalance }
      }
    }
    if (/insufficient funds/i.test(error.shortMessage)) {
      return { kind: 'fee', message: GENERIC_MESSAGES.insufficientFee }
    }
  } else if (hasCode(error, 4001)) {
    return { kind: 'rejected', message: GENERIC_MESSAGES.userRejected }
  }
  return { kind: 'unknown', message: GENERIC_MESSAGES.unknown }
}

/** True when a read reverted with RetainerNotFound (an id that was never created). */
export function isRetainerNotFound(error: unknown): boolean {
  if (!(error instanceof BaseError)) return false
  const revert = error.walk((e) => e instanceof ContractFunctionRevertedError)
  return revert instanceof ContractFunctionRevertedError && revert.data?.errorName === 'RetainerNotFound'
}
