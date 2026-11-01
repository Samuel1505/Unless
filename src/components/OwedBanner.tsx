import type { Address } from 'viem'
import { retainerContract } from '@/app-config/contracts'
import { useOwed } from '@/hooks/useRetainer'
import { formatUsdcPlain } from '@/lib/format'
import { TxButton } from './TxButton'

/**
 * Money that could not be sent to this wallet (for example while it was blocked from receiving USDC)
 * is kept for it. It is the connected wallet's own credit, whoever the retainer belongs to.
 */
export function OwedBanner({ account }: { account: Address | undefined }) {
  const owed = useOwed(account)
  if (owed.data === undefined || owed.data === 0n) return null
  const amount = formatUsdcPlain(owed.data)

  return (
    <section aria-label="Money owed to you" className="enter-fade panel perforated px-5 pb-4 sm:px-6">
      <p className="font-display text-step-1 font-bold">{amount} USDC is owed to you</p>
      <p className="mt-1 text-muted">A payment to your wallet could not be delivered, so it was kept for you. Withdraw it here.</p>
      <div className="mt-3">
        <TxButton
          label={`Withdraw ${amount} USDC owed to you`}
          className="btn btn-primary"
          call={{ ...retainerContract(), functionName: 'withdrawOwed' }}
        />
      </div>
    </section>
  )
}
