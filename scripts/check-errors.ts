/**
 * Fails (exit 1) when a custom error in the retainer ABI has no human message, when a message has no
 * error, or when the generated ABI no longer matches the compiled artifact. Runs before every
 * production build (`bun run build`).
 *
 *   bun run check:errors          check
 *   bun run check:errors --list   also print every error with its message
 */
import { existsSync, readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { retainerAbi } from '../src/app-config/retainer-abi.generated'
import { ERROR_MESSAGES } from '../src/lib/error-messages'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const artifactPath = resolve(root, 'contracts/out/UnlessRetainer.sol/UnlessRetainer.json')

interface AbiItem {
  type: string
  name?: string
}

const problems: string[] = []
const names = (abi: readonly AbiItem[], type: string) =>
  abi.filter((item) => item.type === type && item.name !== undefined).map((item) => item.name as string)

// 1. The generated ABI must be the compiled one (skipped when no artifact is present, e.g. on a host
//    that builds without Foundry).
if (existsSync(artifactPath)) {
  const artifact = JSON.parse(readFileSync(artifactPath, 'utf8')) as { abi: AbiItem[] }
  for (const type of ['error', 'event', 'function']) {
    const compiled = new Set(names(artifact.abi, type))
    const generated = new Set(names(retainerAbi, type))
    for (const name of compiled) if (!generated.has(name)) problems.push(`ABI ${type} "${name}" is in the artifact but not in the generated ABI. Run "bun run sync:abi".`)
    for (const name of generated) if (!compiled.has(name)) problems.push(`ABI ${type} "${name}" is in the generated ABI but not in the artifact. Run "bun run sync:abi".`)
  }
} else {
  console.log('check-errors: no compiled artifact found, checking against the generated ABI only.')
}

// 2. Every error has a non-empty message and every message has an error.
const abiErrors = names(retainerAbi, 'error')
const messages = ERROR_MESSAGES as Record<string, string>
for (const name of abiErrors) {
  if (!messages[name] || messages[name].trim() === '') problems.push(`Error "${name}" has no message in src/lib/error-messages.ts.`)
}
for (const name of Object.keys(messages)) {
  if (!abiErrors.includes(name)) problems.push(`Message "${name}" does not match any error in the ABI.`)
}

if (process.argv.includes('--list')) {
  for (const name of [...abiErrors].sort()) console.log(`${name.padEnd(30)} ${messages[name] ?? '(missing)'}`)
}

if (problems.length > 0) {
  console.error(`check-errors: ${problems.length} problem(s):`)
  for (const problem of problems) console.error(`  - ${problem}`)
  process.exit(1)
}
console.log(`check-errors: all ${abiErrors.length} ABI errors have a message.`)
