import { buildSummary, type CreateTerms } from '@/lib/createRetainer'

/** The terms restated as sentences, so the client reads the consequence of each choice before signing. */
export function TermsSummary({ terms }: { terms: CreateTerms }) {
  const summary = buildSummary(terms)
  return (
    <section className="panel perforated px-5 pb-5 sm:px-6" aria-labelledby="terms-summary">
      <h2 id="terms-summary" className="font-display text-step-1 font-bold">
        Your retainer in plain words
      </h2>
      <div className="mt-3 space-y-2 [overflow-wrap:anywhere]">
        {summary.lines.map((line) => (
          <p key={line}>{line}</p>
        ))}
      </div>
      {summary.caution && <p className="mt-4 font-bold text-objected">{summary.caution}</p>}
    </section>
  )
}
