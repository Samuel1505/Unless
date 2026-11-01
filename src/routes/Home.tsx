import { useState, type FormEvent } from 'react'
import { IS_TESTNET, NETWORK_LABEL, RETAINER_ADDRESS } from '@/app-config/contracts'
import { AddressChip } from '@/components/AddressChip'
import { Link, navigate } from '@/lib/router'

export function Home() {
  const [number, setNumber] = useState('')
  const trimmed = number.trim()
  const valid = /^\d{1,30}$/.test(trimmed)

  const open = (event: FormEvent) => {
    event.preventDefault()
    if (valid) navigate(`/r/${BigInt(trimmed).toString()}`)
  }

  return (
    <div className="grid items-start gap-12 md:grid-cols-[1.35fr_1fr]">
      <section aria-labelledby="home-heading" className="min-w-0">
        <h1 id="home-heading" className="font-display text-step-3 font-bold sm:text-step-4">
          Claims pay out unless you object.
        </h1>
        <p className="mt-5 max-w-prose text-step-1">
          A retainer is money a client sets aside for one freelancer, in USDC. The freelancer claims what they have
          earned, and the client gets a window to object. Silence pays.
        </p>
        <ol className="mt-6 max-w-prose list-decimal space-y-2 pl-6 text-step-1">
          <li>The client funds a retainer for one freelancer.</li>
          <li>The freelancer files a claim for finished work.</li>
          <li>If the client stays silent, the claim pays out when its objection window ends.</li>
        </ol>
        <div className="mt-8">
          <Link to="/new" className="btn btn-primary">
            Start a retainer
          </Link>
        </div>

        <h2 className="mt-12 font-display text-step-2 font-bold">What the client keeps</h2>
        <dl className="mt-4 max-w-prose space-y-3">
          <div>
            <dt className="font-bold">Object</dt>
            <dd className="text-muted">Cancel a pending claim before its window ends. The money stays in the retainer.</dd>
          </div>
          <div>
            <dt className="font-bold">Approve now</dt>
            <dd className="text-muted">Pay a pending claim straight away, without waiting.</dd>
          </div>
          <div>
            <dt className="font-bold">Take money back</dt>
            <dd className="text-muted">
              Ask for what is not reserved. It comes back after the withdrawal notice, and claims filed in the meantime are
              paid first.
            </dd>
          </div>
        </dl>
        <p className="mt-6 max-w-prose text-muted">
          There is no administrator. The money moves only by these rules, and a payout that is due always goes to the
          freelancer.
        </p>
      </section>

      <aside className="panel perforated min-w-0 px-5 pb-6 sm:px-6">
        <form onSubmit={open}>
          <label htmlFor="retainer-number" className="block font-bold">
            Open a retainer by number
          </label>
          <div className="mt-2 flex flex-wrap gap-2">
            <input
              id="retainer-number"
              className="field num min-w-[8rem] flex-1"
              inputMode="numeric"
              enterKeyHint="go"
              autoComplete="off"
              autoCapitalize="none"
              autoCorrect="off"
              placeholder="12"
              value={number}
              onChange={(event) => setNumber(event.target.value)}
              aria-invalid={trimmed !== '' && !valid}
              aria-describedby={trimmed !== '' && !valid ? 'retainer-number-error' : undefined}
            />
            <button type="submit" className="btn btn-quiet" disabled={!valid}>
              Open retainer
            </button>
          </div>
          {trimmed !== '' && !valid && (
            <p id="retainer-number-error" className="mt-2 text-step--1 text-objected">
              Enter a whole number, like 12.
            </p>
          )}
        </form>
        <p className="mt-6 text-step--1 text-muted">
          {IS_TESTNET
            ? `This build runs on ${NETWORK_LABEL}. Testnet USDC has no value.`
            : `This build runs on ${NETWORK_LABEL} and uses real USDC. What you send can't be taken back by anyone but the rules. The code that holds the money is immutable and has no administrator.`}
        </p>
        {RETAINER_ADDRESS && (
          <p className="mt-3 flex flex-wrap items-center gap-x-2 text-step--1 text-muted">
            <span>Retainers are held at</span>
            <AddressChip address={RETAINER_ADDRESS} label="deployment address" />
          </p>
        )}
      </aside>
    </div>
  )
}
