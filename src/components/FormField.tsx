import type { ReactNode } from 'react'

/** The ids a field's input should reference with aria-describedby, in reading order. */
export function describedBy(id: string, hasHint: boolean, hasError: boolean): string | undefined {
  const ids = [hasHint ? `${id}-hint` : null, hasError ? `${id}-error` : null].filter(Boolean)
  return ids.length > 0 ? ids.join(' ') : undefined
}

interface FormFieldProps {
  id: string
  label: string
  hint?: ReactNode
  error?: string | null
  children: ReactNode
}

/** A label, optional hint above the control, and the error below it. Text wraps; nothing is truncated. */
export function FormField({ id, label, hint, error, children }: FormFieldProps) {
  return (
    <div className="min-w-0">
      <label htmlFor={id} className="block font-bold">
        {label}
      </label>
      {hint && (
        <p id={`${id}-hint`} className="mb-2 mt-1 text-step--1 text-muted">
          {hint}
        </p>
      )}
      <div className={hint ? '' : 'mt-2'}>{children}</div>
      {error && (
        <p id={`${id}-error`} className="mt-2 text-step--1 text-objected [overflow-wrap:anywhere]">
          {error}
        </p>
      )}
    </div>
  )
}
