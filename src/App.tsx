import { CONFIG_ERROR } from '@/app-config/contracts'
import { AppShell } from '@/components/AppShell'
import { ConfigErrorPage } from '@/components/ConfigErrorPage'
import { ChainTimeProvider } from '@/hooks/useChainTime'
import { useRoute } from '@/lib/router'
import { Home } from '@/routes/Home'
import { MyRetainers } from '@/routes/MyRetainers'
import { NewRetainer } from '@/routes/NewRetainer'
import { NotFound } from '@/routes/NotFound'
import { RetainerPage } from '@/routes/RetainerPage'

/** Composition root: configuration gate, shell, hash routes. */
export default function App() {
  const route = useRoute()

  if (CONFIG_ERROR) return <ConfigErrorPage message={CONFIG_ERROR} />

  return (
    <ChainTimeProvider>
      <AppShell>
      {route.name === 'home' && <Home />}
      {route.name === 'new' && <NewRetainer />}
      {route.name === 'retainer' && <RetainerPage key={route.id.toString()} id={route.id} />}
      {route.name === 'me' && <MyRetainers />}
      {route.name === 'notFound' && <NotFound />}
      </AppShell>
    </ChainTimeProvider>
  )
}
