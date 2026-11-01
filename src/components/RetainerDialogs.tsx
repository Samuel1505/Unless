import { useState, type ReactNode } from 'react'
import { useAccount } from 'wagmi'
import { retainerContract } from '@/app-config/contracts'
import { useUsdcBalance } from '@/hooks/useCreateReads'
import { amountMessage, endOfLocalDay, parseAmountText, toDateInputValue } from '@/lib/createRetainer'
import { ERROR_MESSAGES } from '@/lib/error-messages'
import { formatDate, formatUsdcPlain } from '@/lib/format'
import { FormField, describedBy } from './FormField'
import { TxDialog } from './TxDialog'

interface AmountDialogProps {
  id: bigint
  triggerLabel: string
  title: string
  description: ReactNode
  /** What the amount is capped by, and the sentence that says so. */
  max: bigint | undefined
  maxText: (max: bigint) => ReactNode
  tooMuchMessage: string
  /** "Top up 3.00 USDC": names the action and the amount. */
  confirmFor: (amountText: string) => string
  functionName: 'deposit' | 'requestWithdrawal'
  /** Approve the exact amount before sending (a top-up pulls USDC from the wallet). */
  approveExact?: boolean
  triggerDisabled?: boolean
}

/** One USDC amount, checked against its cap, sent as a deposit or a withdrawal request. */
function AmountDialog(props: AmountDialogProps) {
  const { id, max, functionName, approveExact = false } = props
  const [text, setText] = useState('')
  const parsed = parseAmountText(text)
  const fieldId = `${functionName}-amount-${id.toString()}`

  let error: string | null = null
  if (!parsed.ok) error = amountMessage(parsed.reason)
  else if (parsed.raw === 0n) error = ERROR_MESSAGES.ZeroAmount
  else if (max !== undefined && parsed.raw > max) error = props.tooMuchMessage
  const amount = parsed.ok && error === null ? parsed.raw : null

  return (
    <TxDialog
      triggerLabel={props.triggerLabel}
      triggerDisabled={props.triggerDisabled}
      title={props.title}
      description={props.description}
      confirmLabel={amount === null ? props.confirmFor('') : props.confirmFor(formatUsdcPlain(amount))}
      call={amount === null ? null : { ...retainerContract(), functionName, args: [id, amount] }}
      approveAmount={approveExact && amount !== null ? amount : undefined}
      onClosed={() => setText('')}
    >
      <FormField
        id={fieldId}
        label="Amount (USDC)"
        hint={max === undefined ? 'Reading the limit…' : props.maxText(max)}
        error={error}
      >
        <input
          id={fieldId}
          className="field num"
          inputMode="decimal"
          enterKeyHint="go"
          autoComplete="off"
          autoCapitalize="none"
          autoCorrect="off"
          spellCheck={false}
          value={text}
          onChange={(event) => setText(event.target.value)}
          aria-invalid={error !== null}
          aria-describedby={describedBy(fieldId, true, error !== null)}
        />
      </FormField>
    </TxDialog>
  )
}

export function TopUpDialog({ id }: { id: bigint }) {
  const { address } = useAccount()
  const balance = useUsdcBalance(address)
  return (
    <AmountDialog
      id={id}
      triggerLabel="Top up"
      title={`Top up retainer ${id.toString()}`}
      description={<p>Adds USDC from your wallet. The freelancer can claim against it straight away.</p>}
      max={balance.data}
      maxText={(max) => <>Your balance: {formatUsdcPlain(max)} USDC</>}
      tooMuchMessage="That's more than your USDC balance."
      confirmFor={(amount) => (amount === '' ? 'Top up' : `Top up ${amount} USDC`)}
      functionName="deposit"
      approveExact
    />
  )
}

export function RequestWithdrawalDialog({ id, available, noticeText }: { id: bigint; available: bigint; noticeText: string }) {
  return (
    <AmountDialog
      id={id}
      triggerLabel="Request withdrawal"
      triggerDisabled={available === 0n}
      title="Take money back"
      description={
        <>
          <p>This starts a {noticeText} notice. When it ends, the money comes back to you.</p>
          <p>Nothing is held back during the notice. The freelancer can still file claims, and those are paid first.</p>
        </>
      }
      max={available}
      maxText={(max) => <>Available now: {formatUsdcPlain(max)} USDC</>}
      tooMuchMessage="That's more than the available balance."
      confirmFor={(amount) => (amount === '' ? 'Request withdrawal' : `Request withdrawal of ${amount} USDC`)}
      functionName="requestWithdrawal"
    />
  )
}

/** Moves the end date later. It can also reopen a retainer that has ended. */
export function ExtendDialog({ id, endTime }: { id: bigint; endTime: bigint }) {
  const [date, setDate] = useState(() => toDateInputValue(new Date((Number(endTime) + 86_400) * 1000)))
  const newEnd = endOfLocalDay(date)
  let error: string | null = null
  if (newEnd === null) error = 'Choose a date from the calendar.'
  else if (BigInt(newEnd) <= endTime) error = ERROR_MESSAGES.EndTimeNotLater
  const fieldId = `extend-date-${id.toString()}`
  const valid = newEnd !== null && error === null

  return (
    <TxDialog
      triggerLabel="Extend end date"
      title="Extend the end date"
      description={
        <p>
          The retainer currently ends {formatDate(endTime)}. A later end date keeps it open for new claims and top-ups,
          or opens it again if it has ended.
        </p>
      }
      confirmLabel={valid ? `Extend end date to ${formatDate(newEnd)}` : 'Extend end date'}
      call={valid ? { ...retainerContract(), functionName: 'extendEndTime', args: [id, BigInt(newEnd)] } : null}
      onClosed={() => setDate(toDateInputValue(new Date((Number(endTime) + 86_400) * 1000)))}
    >
      <FormField id={fieldId} label="New end date" hint="Claims can be filed until the end of this day, in your time zone." error={error}>
        <input
          id={fieldId}
          type="date"
          className="field num"
          value={date}
          onChange={(event) => setDate(event.target.value)}
          aria-invalid={error !== null}
          aria-describedby={describedBy(fieldId, true, error !== null)}
        />
      </FormField>
    </TxDialog>
  )
}

/** Takes back everything that is not reserved for a pending claim, once the retainer has ended. */
export function RemainderDialog({ id, available }: { id: bigint; available: bigint }) {
  const label = `Withdraw ${formatUsdcPlain(available)} USDC remainder`
  return (
    <TxDialog
      triggerLabel={label}
      title="Withdraw the remainder"
      description={
        <>
          <p>
            Takes back {formatUsdcPlain(available)} USDC, everything that is not reserved for a pending claim. Pending
            claims still pay out afterwards.
          </p>
          <p>A withdrawal you already asked for is cancelled.</p>
        </>
      }
      confirmLabel={label}
      call={{ ...retainerContract(), functionName: 'withdrawRemainder', args: [id] }}
    />
  )
}
