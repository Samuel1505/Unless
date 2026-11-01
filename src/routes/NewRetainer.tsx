import { CreateRetainerForm } from '@/components/CreateRetainerForm'
import { WalletGate } from '@/components/WalletGate'

export function NewRetainer() {
  return (
    <div className="max-w-xl">
      <h1 className="font-display text-step-3 font-bold">Start a retainer</h1>
      <p className="mb-8 mt-3 text-step-1 text-muted">
        You fund a retainer for one freelancer, and you become its client.
      </p>
      <WalletGate needed="You fund a retainer from your wallet, so connect one first.">
        <CreateRetainerForm />
      </WalletGate>
    </div>
  )
}
