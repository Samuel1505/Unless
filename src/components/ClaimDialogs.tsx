import { useState } from 'react'
import { retainerContract } from '@/app-config/contracts'
import { ERROR_MESSAGES } from '@/lib/error-messages'
import { MAX_TEXT_BYTES, utf8Bytes } from '@/lib/claims'
import { formatUsdcPlain } from '@/lib/format'
import { FormField, describedBy } from './FormField'
import { TxDialog } from './TxDialog'

interface ClaimDialogProps {
  id: bigint
  claimId: number
  amount: bigint
}

/** Pays a pending claim immediately. The client cannot take it back afterwards, so it asks first. */
export function ApproveNowDialog({ id, claimId, amount }: ClaimDialogProps) {
  const label = `Approve ${formatUsdcPlain(amount)} USDC now`
  return (
    <TxDialog
      triggerLabel={label}
      triggerClassName="btn btn-quiet"
      title={`Approve claim ${claimId} now`}
      description={
        <p>
          The freelancer is paid {formatUsdcPlain(amount)} USDC straight away, without waiting for the objection window.
          This can't be undone.
        </p>
      }
      confirmLabel={label}
      call={{ ...retainerContract(), functionName: 'approveClaim', args: [id, BigInt(claimId)] }}
    />
  )
}

/** Objects to a pending claim, with an optional reason that stays public on the retainer page. */
export function ObjectDialog({ id, claimId, amount }: ClaimDialogProps) {
  const [reason, setReason] = useState('')
  const bytes = utf8Bytes(reason)
  const tooLong = bytes > MAX_TEXT_BYTES
  const label = `Object to ${formatUsdcPlain(amount)} USDC claim`
  const fieldId = `object-reason-${claimId}`

  return (
    <TxDialog
      triggerLabel="Object"
      triggerClassName="btn btn-quiet"
      title={`Object to claim ${claimId}`}
      description={
        <p>
          The claim is cancelled and {formatUsdcPlain(amount)} USDC stays in the retainer, available again. You can add a
          reason. Everyone who opens this retainer can read it.
        </p>
      }
      confirmLabel={label}
      danger
      blockedReason={tooLong ? ERROR_MESSAGES.TextTooLong : null}
      call={tooLong ? null : { ...retainerContract(), functionName: 'objectToClaim', args: [id, BigInt(claimId), reason] }}
      onClosed={() => setReason('')}
    >
      <FormField id={fieldId} label="Reason (optional)">
        <textarea
          id={fieldId}
          className="field field-area"
          value={reason}
          onChange={(event) => setReason(event.target.value)}
          aria-invalid={tooLong}
          aria-describedby={describedBy(fieldId, false, false)}
          autoCapitalize="sentences"
        />
        <p className={`mt-1 text-step--1 num ${tooLong ? 'text-objected' : 'text-muted'}`}>
          {bytes} of {MAX_TEXT_BYTES} bytes
        </p>
      </FormField>
    </TxDialog>
  )
}
