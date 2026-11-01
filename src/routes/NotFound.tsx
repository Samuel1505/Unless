import { EmptyState } from '@/components/EmptyState'
import { Link } from '@/lib/router'

export function NotFound() {
  return (
    <EmptyState
      title="That page doesn't exist"
      action={
        <Link to="/" className="btn btn-primary">
          Go to the start
        </Link>
      }
    >
      <p>Check the link, or open a retainer by its number from the start page.</p>
    </EmptyState>
  )
}
