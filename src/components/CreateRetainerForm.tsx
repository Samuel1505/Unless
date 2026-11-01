import { useMemo, useState, type FormEvent } from 'react'
import { useAccount } from 'wagmi'
import { IS_TESTNET, NETWORK_LABEL } from '@/app-config/contracts'
import { CreateActions } from '@/components/CreateActions'
import { DurationField } from '@/components/DurationField'
import { FormField, describedBy } from '@/components/FormField'
import { TermsSummary } from '@/components/TermsSummary'
import { UsdcAmount } from '@/components/UsdcAmount'
import { useChainTime } from '@/hooks/useChainTime'
import { useCreateFlow } from '@/hooks/useCreateFlow'
import { useRetainerLimits, useUsdcBalance } from '@/hooks/useCreateReads'
import {
  DEFAULT_NOTICE_ID,
  DEFAULT_WINDOW_ID,
  NOTICE_PRESETS,
  WINDOW_PRESETS,
  toDateInputValue,
  validateForm,
  type DurationChoice,
} from '@/lib/createRetainer'

const DEFAULT_END_DAYS = 30
const FULL_ADDRESS_LENGTH = 42

type FieldKey = 'freelancer' | 'amount' | 'window' | 'notice' | 'endDate'

export function CreateRetainerForm() {
  const { address } = useAccount()
  const { now } = useChainTime()
  const { limits, isError: limitsFailed } = useRetainerLimits()
  const balance = useUsdcBalance(address)

  const [freelancer, setFreelancer] = useState('')
  const [amount, setAmount] = useState('')
  const [windowChoice, setWindowChoice] = useState<DurationChoice>({ id: DEFAULT_WINDOW_ID, customHours: '' })
  const [noticeChoice, setNoticeChoice] = useState<DurationChoice>({ id: DEFAULT_NOTICE_ID, customHours: '' })
  // The default is a suggestion from the visitor's calendar; the check itself always uses chain time.
  const [endDate, setEndDate] = useState(() => toDateInputValue(new Date(Date.now() + DEFAULT_END_DAYS * 86_400_000)))
  const [touched, setTouched] = useState<Partial<Record<FieldKey, boolean>>>({})
  const touch = (key: FieldKey) => setTouched((current) => (current[key] ? current : { ...current, [key]: true }))

  const state = useMemo(
    () =>
      validateForm(
        { freelancer, amount, window: windowChoice, notice: noticeChoice, endDate },
        { connected: address, chainNow: now, limits, balance: balance.data },
      ),
    [freelancer, amount, windowChoice, noticeChoice, endDate, address, now, limits, balance.data],
  )

  const flow = useCreateFlow(state.terms)

  // A half-typed address is not an error yet: wait for the blur, or for a full-length paste.
  const freelancerTyped = freelancer.trim().length
  const showFreelancer = touched.freelancer === true || freelancerTyped >= FULL_ADDRESS_LENGTH
  const showWindow = touched.window === true || windowChoice.customHours !== ''
  const showNotice = touched.notice === true || noticeChoice.customHours !== ''

  const blockedReason = limitsFailed
    ? "Couldn't read the retainer limits. Check your connection and reload."
    : state.waiting === 'limits'
      ? 'Reading the retainer limits…'
      : state.waiting === 'time'
        ? 'Reading the network time…'
        : state.terms === null
          ? 'Complete the form to continue.'
          : null

  const submit = (event: FormEvent) => {
    event.preventDefault()
    if (state.terms === null || flow.needsApproval === undefined) return
    void (flow.needsApproval ? flow.approve() : flow.create())
  }

  const freelancerError = showFreelancer ? state.freelancer.error : null
  const amountError = state.amount.error
  const endDateError = state.endDate.error
  const todayMin = now === null ? undefined : toDateInputValue(new Date(now * 1000))

  return (
    <form className="space-y-8" noValidate onSubmit={submit}>
      <FormField
        id="freelancer"
        label="Freelancer address"
        hint="The one person who can file claims against this retainer."
        error={freelancerError}
      >
        <input
          id="freelancer"
          className="field num"
          inputMode="text"
          enterKeyHint="next"
          autoComplete="off"
          autoCapitalize="none"
          autoCorrect="off"
          spellCheck={false}
          placeholder="0x…"
          value={freelancer}
          aria-invalid={freelancerError !== null}
          aria-describedby={describedBy('freelancer', true, freelancerError !== null)}
          onChange={(event) => setFreelancer(event.target.value)}
          onBlur={() => touch('freelancer')}
        />
        {state.freelancer.value && (
          <p className="mt-2 text-step--1 text-muted [overflow-wrap:anywhere]">
            Paying: <span className="num">{state.freelancer.value}</span>
          </p>
        )}
      </FormField>

      <FormField
        id="amount"
        label="Starting amount (USDC)"
        hint={
          <>
            Your balance on {NETWORK_LABEL}:{' '}
            {balance.data !== undefined ? (
              <UsdcAmount raw={balance.data} />
            ) : balance.isError ? (
              "couldn't be read"
            ) : (
              'reading…'
            )}
          </>
        }
        error={amountError}
      >
        <input
          id="amount"
          className="field num"
          inputMode="decimal"
          enterKeyHint="next"
          autoComplete="off"
          autoCapitalize="none"
          autoCorrect="off"
          spellCheck={false}
          placeholder="0.00"
          value={amount}
          aria-invalid={amountError !== null}
          aria-describedby={describedBy('amount', true, amountError !== null)}
          onChange={(event) => setAmount(event.target.value)}
          onBlur={() => touch('amount')}
        />
        {balance.data === 0n && (
          <p className="mt-2 text-step--1">
            You have no USDC on {NETWORK_LABEL}.
            {IS_TESTNET && (
              <>
                {' '}
                <a href="https://faucet.circle.com" target="_blank" rel="noopener noreferrer">
                  Get test USDC
                </a>
              </>
            )}
          </p>
        )}
      </FormField>

      <DurationField
        legend="Objection window"
        hint="How long you have to object to a claim before it pays out."
        presets={WINDOW_PRESETS}
        value={windowChoice}
        onChange={setWindowChoice}
        onBlur={() => touch('window')}
        error={showWindow ? state.window.error : null}
      />

      <DurationField
        legend="Withdrawal notice"
        hint="How long before money you take back actually leaves the retainer."
        presets={NOTICE_PRESETS}
        value={noticeChoice}
        onChange={setNoticeChoice}
        onBlur={() => touch('notice')}
        error={showNotice ? state.notice.error : null}
      />

      <FormField
        id="end-date"
        label="End date"
        hint="Claims can be filed until the end of this day, in your time zone."
        error={endDateError}
      >
        <input
          id="end-date"
          type="date"
          className="field num"
          min={todayMin}
          value={endDate}
          aria-invalid={endDateError !== null}
          aria-describedby={describedBy('end-date', true, endDateError !== null)}
          onChange={(event) => setEndDate(event.target.value)}
          onBlur={() => touch('endDate')}
        />
      </FormField>

      {state.terms && <TermsSummary terms={state.terms} />}

      <CreateActions terms={state.terms} flow={flow} blockedReason={blockedReason} />
    </form>
  )
}
