import type { retainerAbi } from '../app-config/retainer-abi.generated'

/**
 * One human message for every custom error in the compiled ABI (05-FRONTEND-SPEC section 7).
 *
 * The key set is derived from the ABI: `satisfies Record<RetainerErrorName, string>` makes the
 * type check fail when an error has no message (or a message has no error), and
 * scripts/check-errors.ts re-checks the same thing against the compiled artifact before
 * every production build.
 */
type AbiError = Extract<(typeof retainerAbi)[number], { type: 'error' }>
export type RetainerErrorName = AbiError['name']

export const ERROR_MESSAGES = {
  ClaimNotFound: "This claim doesn't exist.",
  ClaimNotPending: 'This claim has already been resolved.',
  DepositMismatch: "The deposit didn't arrive as expected. No funds were recorded.",
  EndTimeNotLater: 'The new end date must be later than the current one.',
  EndTimeTooSoon: 'Choose an end date after the withdrawal notice period.',
  InsufficientAvailable: "That's more than the available balance.",
  InvalidFreelancer: "Enter a freelancer address that isn't yours.",
  InvalidToken: 'The USDC address for this deployment is invalid.',
  NoWithdrawalPending: "There's no withdrawal in progress.",
  NotClient: 'Only the client can do this.',
  NotFreelancer: 'Only the freelancer can do this.',
  NothingOwed: 'Nothing is owed to this address.',
  NoticeNotElapsed: "The withdrawal notice hasn't finished yet.",
  NoticeOutOfRange: 'The withdrawal notice must be between 1 minute and 60 days.',
  ObjectionWindowClosed: 'The objection window has closed. This claim can now be paid out.',
  ObjectionWindowOpen: "This claim can't be paid out until its objection window closes.",
  ReentrancyGuardReentrantCall: 'Another action on this retainer is still in progress. Try again in a moment.',
  RetainerEnded: 'This retainer has ended.',
  RetainerNotEnded: 'You can withdraw the remainder after the end date.',
  RetainerNotFound: "This retainer doesn't exist on this network.",
  SafeERC20FailedOperation:
    "The USDC transfer was rejected. Check your balance and that your address can receive USDC.",
  TextTooLong: 'Keep it under 280 bytes.',
  TooManyPendingClaims: 'There are already 20 claims waiting. Resolve one first.',
  WindowOutOfRange: 'The objection window must be between 1 minute and 30 days.',
  WithdrawalAlreadyPending: 'A withdrawal is already in progress.',
  ZeroAmount: 'Enter an amount greater than zero.',
} satisfies Record<RetainerErrorName, string>

/** Messages for failures that are not custom errors of the retainer. */
export const GENERIC_MESSAGES = {
  tokenAllowanceOrBalance: "You don't have enough USDC approved or available.",
  insufficientFee: "You don't have enough USDC to pay the network fee.",
  userRejected: 'Transaction cancelled in your wallet.',
  unknown: 'Something went wrong onchain. Check the transaction on the explorer.',
} as const
