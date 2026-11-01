import { useMemo, useSyncExternalStore, type AnchorHTMLAttributes, type ReactNode } from 'react'

/** Hash routing (/#/…) so any static host works without rewrite rules (05-FRONTEND-SPEC section 3). */
export type Route =
  | { name: 'home' }
  | { name: 'new' }
  | { name: 'retainer'; id: bigint }
  | { name: 'me' }
  | { name: 'notFound'; path: string }

export function parseHash(hash: string): Route {
  const path = '/' + hash.replace(/^#\/?/, '').replace(/\/+$/, '')
  const parts = path.split('/').filter(Boolean)
  if (parts.length === 0) return { name: 'home' }
  if (parts.length === 1 && parts[0] === 'new') return { name: 'new' }
  if (parts.length === 1 && parts[0] === 'me') return { name: 'me' }
  if (parts.length === 2 && parts[0] === 'r' && /^\d{1,30}$/.test(parts[1])) {
    return { name: 'retainer', id: BigInt(parts[1]) }
  }
  return { name: 'notFound', path }
}

function subscribe(onChange: () => void): () => void {
  window.addEventListener('hashchange', onChange)
  return () => window.removeEventListener('hashchange', onChange)
}

function snapshot(): string {
  return window.location.hash
}

export function useRoute(): Route {
  const hash = useSyncExternalStore(subscribe, snapshot)
  return useMemo(() => parseHash(hash), [hash])
}

export function navigate(path: string): void {
  window.location.hash = path.startsWith('/') ? path : `/${path}`
}

interface LinkProps extends Omit<AnchorHTMLAttributes<HTMLAnchorElement>, 'href'> {
  to: string
  children: ReactNode
}

export function Link({ to, children, ...rest }: LinkProps) {
  return (
    <a href={`#${to.startsWith('/') ? to : `/${to}`}`} {...rest}>
      {children}
    </a>
  )
}
