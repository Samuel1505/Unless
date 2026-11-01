import type { ReactNode } from 'react'
import { Link } from '@/lib/router'
import { ConnectButton } from './ConnectButton'
import { NetworkBadge } from './NetworkBadge'
import { NetworkBanner } from './NetworkBanner'

export function AppShell({ children }: { children: ReactNode }) {
  return (
    <div className="flex min-h-dvh flex-col">
      <a
        href="#main"
        onClick={(event) => {
          // Hash routing owns the URL hash, so move focus instead of navigating.
          event.preventDefault()
          document.getElementById('main')?.focus()
        }}
        className="sr-only focus:not-sr-only focus:absolute focus:left-2 focus:top-2 focus:bg-paper focus:px-3 focus:py-2"
      >
        Skip to content
      </a>
      <header className="shell-top border-b border-rule">
        <div className="shell-x mx-auto flex max-w-5xl flex-wrap items-center gap-x-6 gap-y-3 py-3">
          <Link to="/" className="pressable font-display text-step-2 font-bold tracking-tight text-ink no-underline">
            Unless
          </Link>
          <nav aria-label="Main" className="flex items-center gap-5 text-step-0">
            <Link to="/new" className="pressable">
              Start a retainer
            </Link>
            <Link to="/me" className="pressable">
              My retainers
            </Link>
          </nav>
          <div className="ml-auto flex items-center gap-3">
            <NetworkBadge />
            <ConnectButton />
          </div>
        </div>
      </header>
      <NetworkBanner />
      <main id="main" tabIndex={-1} className="shell-x shell-bottom mx-auto w-full max-w-5xl flex-1 pt-10 outline-none">
        {children}
      </main>
    </div>
  )
}
