import type { ReactNode } from 'react'

/** A real empty state: says what is true right now and what the person can do about it. */
export function EmptyState({
  title,
  children,
  action,
}: {
  title: string
  children?: ReactNode
  action?: ReactNode
}) {
  return (
    <section className="panel perforated max-w-xl px-6 pb-6">
      <h2 className="font-display text-step-2 font-bold">{title}</h2>
      {children && <div className="mt-2 text-muted">{children}</div>}
      {action && <div className="mt-5 flex flex-wrap items-center gap-3">{action}</div>}
    </section>
  )
}
