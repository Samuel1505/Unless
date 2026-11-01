import { useEffect, useRef, useState, type FormEvent, type ReactNode } from 'react'
import { Dialog } from '@base-ui/react/dialog'
import { useAccount } from 'wagmi'
import { useUsdcAllowance } from '@/hooks/useCreateReads'
import { useApproveExact, useTransaction, type ContractCall } from '@/hooks/useTransaction'
import { formatUsdcPlain } from '@/lib/format'
import { IN_FLIGHT, TxFailure, TxSubmitted, submittedHash, txLabel } from './TxStatus'

interface TxDialogProps {
  triggerLabel: string
  triggerClassName?: string
  triggerDisabled?: boolean
  title: string
  description: ReactNode
  /** Names the action and the amount: "Approve 3.00 USDC now". Shown on the confirm button. */
  confirmLabel: string
  /** The write to send. Null while the fields are not valid. */
  call: ContractCall | null
  /** USDC to approve first, exactly this amount and no more. Skipped when the allowance already covers it. */
  approveAmount?: bigint
  /** Marks a decision that cannot be undone. */
  danger?: boolean
  /** Why the confirm button is disabled, when the fields are the reason. */
  blockedReason?: string | null
  /** Called when the dialog closes, so the fields can reset. */
  onClosed?: () => void
  children?: ReactNode
}

/**
 * A confirmation dialog for one write. The wallet and transaction hooks live in the body, which only
 * exists while the dialog is open, so a page full of claim rows does not carry a set per closed dialog.
 * The dialog will not close while a transaction is waiting on the wallet or the chain.
 */
export function TxDialog(props: TxDialogProps) {
  const { triggerLabel, triggerClassName = 'btn btn-quiet', triggerDisabled = false, title, description, onClosed } = props
  const [open, setOpen] = useState(false)
  const busyRef = useRef(false)

  const change = (next: boolean) => {
    if (!next && busyRef.current) return
    setOpen(next)
    if (!next) onClosed?.()
  }

  return (
    <Dialog.Root open={open} onOpenChange={change} disablePointerDismissal>
      <Dialog.Trigger className={triggerClassName} disabled={triggerDisabled}>
        {triggerLabel}
      </Dialog.Trigger>
      <Dialog.Portal>
        <Dialog.Backdrop className="dialog-backdrop" />
        <Dialog.Viewport className="dialog-viewport">
          <Dialog.Popup className="dialog-popup">
            <Dialog.Title className="font-display text-step-2 font-bold">{title}</Dialog.Title>
            <Dialog.Description render={<div />} className="mt-2 space-y-2 text-muted">
              {description}
            </Dialog.Description>
            <DialogBody {...props} busyRef={busyRef} onDone={() => change(false)} />
          </Dialog.Popup>
        </Dialog.Viewport>
      </Dialog.Portal>
    </Dialog.Root>
  )
}

interface BodyProps extends TxDialogProps {
  busyRef: { current: boolean }
  onDone: () => void
}

function DialogBody({ confirmLabel, call, approveAmount, danger = false, blockedReason = null, children, busyRef, onDone }: BodyProps) {
  const { address } = useAccount()
  const action = useTransaction()
  const approval = useApproveExact()
  const allowance = useUsdcAllowance(approveAmount !== undefined && approveAmount > 0n ? address : undefined)

  const busy = IN_FLIGHT.has(action.state.status) || IN_FLIGHT.has(approval.state.status)
  useEffect(() => {
    busyRef.current = busy
  }, [busy, busyRef])
  const needsApproval =
    approveAmount === undefined || approveAmount === 0n ? false : allowance.data === undefined ? undefined : allowance.data < approveAmount
  const ready = call !== null && needsApproval !== undefined && blockedReason === null

  const approve = async () => {
    if (approveAmount === undefined) return
    await approval.ensureAllowance(approveAmount)
    await allowance.refetch()
  }

  const confirm = async () => {
    if (!call) return
    const hash = await action.run(call)
    if (hash) {
      busyRef.current = false
      onDone()
    }
  }

  const submit = (event: FormEvent) => {
    event.preventDefault()
    if (!ready || busy) return
    void (needsApproval ? approve() : confirm())
  }

  return (
    <form className="mt-5 space-y-5" onSubmit={submit} noValidate>
      {children}
      {blockedReason && <p className="text-step--1 text-objected [overflow-wrap:anywhere]">{blockedReason}</p>}
      <div className="flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
        <Dialog.Close className="btn btn-quiet" disabled={busy}>
          Not now
        </Dialog.Close>
        {needsApproval && approveAmount !== undefined && (
          <button type="submit" className="btn btn-primary" disabled={!ready || busy} aria-busy={busy}>
            {txLabel(approval.state, `Approve ${formatUsdcPlain(approveAmount)} USDC`, 'Approving…')}
          </button>
        )}
        <button
          type={needsApproval ? 'button' : 'submit'}
          className={needsApproval ? 'btn btn-quiet' : danger ? 'btn btn-danger' : 'btn btn-primary'}
          disabled={!ready || busy || needsApproval === true}
          aria-busy={busy}
        >
          {txLabel(action.state, confirmLabel, 'Sent, waiting for Arc…')}
        </button>
      </div>
      <div className="space-y-1">
        <TxSubmitted hash={submittedHash(action.state, approval.state)} />
        <TxFailure state={approval.state} />
        <TxFailure state={action.state} />
      </div>
    </form>
  )
}
