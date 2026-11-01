import { useState } from 'react'
import { retainerContract } from '@/app-config/contracts'
import { MAX_PENDING_CLAIMS, MAX_TEXT_BYTES, utf8Bytes } from '@/lib/claims'
import { amountMessage, parseAmountText } from '@/lib/createRetainer'
import { ERROR_MESSAGES } from '@/lib/error-messages'
import { formatUsdcPlain } from '@/lib/format'
import { FormField, describedBy } from './FormField'
import { TxButton } from './TxButton'

interface FileClaimFormProps {
  id: bigint
  available: bigint
  ended: boolean
  pendingClaims: number
}

/** The freelancer asks to be paid an amount for finished work. The note is public and capped in bytes. */
export function FileClaimForm({ id, available, ended, pendingClaims }: FileClaimFormProps) {
  const [amountText, setAmountText] = useState('')
  const [note, setNote] = useState('')

  if (ended) {
    return <p>This retainer has ended, so new claims can't be filed. Ask the client to extend the end date.</p>
  }
  if (pendingClaims >= MAX_PENDING_CLAIMS) {
    return <p>{ERROR_MESSAGES.TooManyPendingClaims}</p>
  }
  if (available === 0n) {
    return <p>Nothing is available to claim right now. The client can top up the retainer.</p>
  }

  const parsed = parseAmountText(amountText)
  let amountError: string | null = null
  if (!parsed.ok) amountError = amountMessage(parsed.reason)
  else if (parsed.raw === 0n) amountError = ERROR_MESSAGES.ZeroAmount
  else if (parsed.raw > available) amountError = ERROR_MESSAGES.InsufficientAvailable
  const amount = parsed.ok && amountError === null ? parsed.raw : null

  const bytes = utf8Bytes(note)
  const noteError = bytes > MAX_TEXT_BYTES ? ERROR_MESSAGES.TextTooLong : null
  const valid = amount !== null && noteError === null
  const amountId = `claim-amount-${id.toString()}`
  const noteId = `claim-note-${id.toString()}`

  return (
    <form className="space-y-5" onSubmit={(event) => event.preventDefault()} noValidate>
      <FormField id={amountId} label="Amount (USDC)" hint={<>Available to claim: {formatUsdcPlain(available)} USDC</>} error={amountError}>
        <input
          id={amountId}
          className="field num"
          inputMode="decimal"
          enterKeyHint="next"
          autoComplete="off"
          autoCapitalize="none"
          autoCorrect="off"
          spellCheck={false}
          value={amountText}
          onChange={(event) => setAmountText(event.target.value)}
          aria-invalid={amountError !== null}
          aria-describedby={describedBy(amountId, true, amountError !== null)}
        />
      </FormField>
      <FormField id={noteId} label="What it's for (optional)" hint="The client and everyone who opens this retainer can read it." error={noteError}>
        <textarea
          id={noteId}
          className="field field-area"
          value={note}
          onChange={(event) => setNote(event.target.value)}
          aria-invalid={noteError !== null}
          aria-describedby={describedBy(noteId, true, noteError !== null)}
        />
        <p className={`mt-1 text-step--1 num ${noteError ? 'text-objected' : 'text-muted'}`}>
          {bytes} of {MAX_TEXT_BYTES} bytes
        </p>
      </FormField>
      <TxButton
        label={amount === null ? 'File claim' : `File claim for ${formatUsdcPlain(amount)} USDC`}
        className="btn btn-primary"
        disabled={!valid}
        call={valid ? { ...retainerContract(), functionName: 'fileClaim', args: [id, amount, note] } : null}
        onConfirmed={() => {
          setAmountText('')
          setNote('')
        }}
      />
    </form>
  )
}
