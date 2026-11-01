import { retainerContract } from '@/app-config/contracts'
import { formatUsdcPlain } from '@/lib/format'
import { describeSpan } from '@/lib/createRetainer'
import { ExtendDialog, RemainderDialog, RequestWithdrawalDialog, TopUpDialog } from './RetainerDialogs'
import { FileClaimForm } from './FileClaimForm'
import { TxButton } from './TxButton'

interface PanelBase {
  id: bigint
  available: bigint
  ended: boolean
}

interface ClientPanelProps extends PanelBase {
  endTime: bigint
  noticePeriod: number
  withdrawalPending: boolean
  withdrawalAmount: bigint
}

/** What only the client can do. Each button is shown only when the contract would accept it. */
export function ClientPanel(props: ClientPanelProps) {
  const { id, available, ended, endTime, noticePeriod, withdrawalPending, withdrawalAmount } = props
  return (
    <section aria-labelledby="client-actions" className="panel perforated px-5 pb-5 sm:px-6">
      <h2 id="client-actions" className="font-display text-step-1 font-bold">
        You are the client
      </h2>
      {ended && (
        <p className="mt-2 text-muted">
          This retainer has ended. Claims already filed still pay out. You can take back what is not reserved, or extend
          the end date to open it again.
        </p>
      )}
      <div className="mt-4 flex flex-wrap items-start gap-3">
        {!ended && <TopUpDialog id={id} />}
        {!ended && !withdrawalPending && (
          <RequestWithdrawalDialog id={id} available={available} noticeText={describeSpan(noticePeriod)} />
        )}
        {withdrawalPending && (
          <TxButton
            label={`Cancel withdrawal of ${formatUsdcPlain(withdrawalAmount)} USDC`}
            call={{ ...retainerContract(), functionName: 'cancelWithdrawal', args: [id] }}
          />
        )}
        <ExtendDialog id={id} endTime={endTime} />
        {ended && available > 0n && <RemainderDialog id={id} available={available} />}
      </div>
    </section>
  )
}

interface FreelancerPanelProps extends PanelBase {
  pendingClaims: number
}

export function FreelancerPanel({ id, available, ended, pendingClaims }: FreelancerPanelProps) {
  return (
    <section aria-labelledby="freelancer-actions" className="panel perforated max-w-xl px-5 pb-5 sm:px-6">
      <h2 id="freelancer-actions" className="mb-4 font-display text-step-1 font-bold">
        File a claim
      </h2>
      <FileClaimForm id={id} available={available} ended={ended} pendingClaims={pendingClaims} />
    </section>
  )
}
