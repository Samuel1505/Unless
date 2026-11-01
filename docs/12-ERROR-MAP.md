# Error map

Generated from `bun run check:errors --list`. Source of truth: `src/lib/error-messages.ts`; keys come from the compiled ABI of the deployed source.

26 custom errors in the ABI, 26 messages.

| Error | Message | Note |
|---|---|---|
| `ClaimNotFound` | This claim doesn't exist. |  |
| `ClaimNotPending` | This claim has already been resolved. |  |
| `DepositMismatch` | The deposit didn't arrive as expected. No funds were recorded. |  |
| `EndTimeNotLater` | The new end date must be later than the current one. |  |
| `EndTimeTooSoon` | Choose an end date after the withdrawal notice period. |  |
| `InsufficientAvailable` | That's more than the available balance. |  |
| `InvalidFreelancer` | Enter a freelancer address that isn't yours. |  |
| `InvalidToken` | The USDC address for this deployment is invalid. | Reworded to avoid the word "contract" in UI copy. |
| `NoWithdrawalPending` | There's no withdrawal in progress. |  |
| `NotClient` | Only the client can do this. |  |
| `NotFreelancer` | Only the freelancer can do this. |  |
| `NothingOwed` | Nothing is owed to this address. |  |
| `NoticeNotElapsed` | The withdrawal notice hasn't finished yet. |  |
| `NoticeOutOfRange` | The withdrawal notice must be between 1 minute and 60 days. |  |
| `ObjectionWindowClosed` | The objection window has closed. This claim can now be paid out. |  |
| `ObjectionWindowOpen` | This claim can't be paid out until its objection window closes. |  |
| `ReentrancyGuardReentrantCall` | Another action on this retainer is still in progress. Try again in a moment. | Added: not in the 05 table (raised by the OpenZeppelin guard in the ABI). |
| `RetainerEnded` | This retainer has ended. |  |
| `RetainerNotEnded` | You can withdraw the remainder after the end date. |  |
| `RetainerNotFound` | This retainer doesn't exist on this network. |  |
| `SafeERC20FailedOperation` | The USDC transfer was rejected. Check your balance and that your address can receive USDC. | Added: not in the 05 table (raised by withdrawOwed when the token transfer fails). |
| `TextTooLong` | Keep it under 280 bytes. | Wording changed from "characters" to "bytes" (P0 item 10). |
| `TooManyPendingClaims` | There are already 20 claims waiting. Resolve one first. |  |
| `WindowOutOfRange` | The objection window must be between 1 minute and 30 days. |  |
| `WithdrawalAlreadyPending` | A withdrawal is already in progress. |  |
| `ZeroAmount` | Enter an amount greater than zero. |  |

Not custom errors of the retainer (handled in `src/lib/errors.ts`):

| Case | Message |
|---|---|
| Token allowance or balance revert | You don't have enough USDC approved or available. |
| Not enough USDC for the network fee (added) | You don't have enough USDC to pay the network fee. |
| User rejected in wallet | Transaction cancelled in your wallet. (shown as idle, not as an error) |
| Anything else | Something went wrong onchain. Check the transaction on the explorer. |
