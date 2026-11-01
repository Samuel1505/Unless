import { NETWORK_LABEL } from '@/app-config/contracts'

/** Always visible: the person must never be unsure which network they are on (05-FRONTEND-SPEC 2.2). */
export function NetworkBadge() {
  return (
    <span
      className="inline-flex items-center gap-2 border border-rule px-2.5 py-1 text-step--1 text-muted"
      title={`This app is reading and writing on ${NETWORK_LABEL}`}
    >
      <span aria-hidden="true" className="h-2 w-2 rounded-full bg-settled" />
      <span>{NETWORK_LABEL}</span>
    </span>
  )
}
