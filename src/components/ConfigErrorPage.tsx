/** Rendered instead of the routes when the build cannot run, so a bad setting never shows a half-working app. */
export function ConfigErrorPage({ message }: { message: string }) {
  return (
    <main className="shell-x shell-top shell-bottom mx-auto flex min-h-dvh max-w-xl flex-col justify-center">
      <section className="panel perforated px-6 pb-6">
        <h1 className="font-display text-step-2 font-bold">This app isn't set up correctly</h1>
        <p className="mt-3">{message}</p>
        <p className="mt-3 text-muted">
          Nothing was sent to your wallet. Fix the setting and reload the page.
        </p>
      </section>
    </main>
  )
}
