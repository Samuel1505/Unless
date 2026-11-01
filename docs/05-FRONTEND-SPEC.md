# 05 — Frontend Specification

The app is built in Arc Studio on its Vite scaffold, exported, and hosted as a static site. It has one job: make the state of a retainer obvious to both parties and make each permitted action one clear button.

## 1. Stack

- **Use what Studio scaffolds.** If Studio offers a choice: React + TypeScript + Vite, `viem` for chain access, `wagmi` for wallet connection (injected connector; WalletConnect optional and out of scope if it needs a project id/secret).
- **Routing:** hash-based (`/#/…`) so any static host works without rewrite rules.
- **No backend, no analytics, no external API calls** other than JSON-RPC and Google Fonts.
- **State:** server state from the chain via polling hooks; local UI state in components. No global store needed.

## 2. Configuration

### 2.1 `config/chains.ts`

```ts
export const arcMainnet = {
  id: 5042,
  name: 'Arc',
  nativeCurrency: { name: 'USDC', symbol: 'USDC', decimals: 18 }, // native gas unit; never use for amounts
  rpcUrls: { default: { http: ['https://rpc.mainnet.arc.io'] } },
  blockExplorers: { default: { name: 'Arc Explorer', url: 'https://explorer.arc.io' } },
} as const;

export const arcTestnet = {
  id: 5042002,
  name: 'Arc Testnet',
  nativeCurrency: { name: 'USDC', symbol: 'USDC', decimals: 18 },
  rpcUrls: { default: { http: ['https://rpc.testnet.arc.io'] } },
  blockExplorers: { default: { name: 'Arc Testnet Explorer', url: 'https://explorer.testnet.arc.io' } },
} as const;
```
Verify every value against docs.arc.io "Connect to Arc" before Phase 5 (06-ARC-PLATFORM-NOTES §1). Provider fallback RPCs may be listed as secondary `http` entries.

### 2.2 `config/contracts.ts`

```ts
export const NETWORK = import.meta.env.VITE_NETWORK === 'mainnet' ? 'mainnet' : 'testnet';
export const USDC_ADDRESS = '0x3600000000000000000000000000000000000000';
export const RETAINER_ADDRESS = {
  testnet: import.meta.env.VITE_RETAINER_TESTNET,
  mainnet: import.meta.env.VITE_RETAINER_MAINNET,
}[NETWORK];
```
The app shows a visible network badge ("Arc mainnet" / "Arc testnet") at all times. If `RETAINER_ADDRESS` is unset, the app renders a configuration error page, not a broken UI.

### 2.3 Amounts

- All amounts are `bigint` in 6-decimal base units. Parse with `parseUnits(input, 6)`, format with `formatUnits(value, 6)`.
- Display with exactly two decimals and the unit: `3.00 USDC`. Show full precision in a tooltip if the value has more.
- **Never** use the chain's `nativeCurrency.decimals` (18) for amounts. Wallet "native balance" shown by some wallets is the same USDC at 18 dp; the app displays the ERC-20 balance.

## 3. Routes

| Route | Screen | Who sees what |
|---|---|---|
| `/#/` | Home | Explainer + "Start a retainer" + "Open a retainer by number" |
| `/#/new` | Create retainer | Requires wallet; caller becomes client |
| `/#/r/:id` | Retainer page | Public. Role-aware panels when the connected wallet is the client or freelancer |
| `/#/me` | My retainers | Lists ids from `retainersOfClient` and `retainersOfFreelancer` |

## 4. Screens and states

### 4.1 Home
- Headline states the rule in plain words: "Claims pay out unless you object."
- Three short lines explain the mechanism in sequence: client funds, freelancer claims, silence pays. (This is a real sequence, so numbering is appropriate.)
- Primary action: **Start a retainer**. Secondary: retainer number field + **Open**.
- Network badge and **Connect wallet**.

### 4.2 Create retainer (`/#/new`)
Fields:
- Freelancer address (validated checksum; cannot equal connected address)
- Starting amount (USDC) — shows the connected wallet's USDC balance beneath
- Objection window — presets: 5 minutes (demo), 24 hours, 48 hours (default), 7 days; custom in hours
- Withdrawal notice — presets identical; default 72 hours
- End date — date picker; default 30 days; must exceed now + notice

A live summary sentence restates the terms: "Mara can claim up to 10.00 USDC until 24 Nov. Each claim pays out 48 hours after it's filed unless you object. Taking money back needs 72 hours' notice."

Actions: two-step button group, **Approve 10.00 USDC** → **Create retainer**. The approve step is skipped if the current allowance already covers the exact amount. On success: navigate to `/#/r/:id`.

### 4.3 Retainer page (`/#/r/:id`) — the core screen

Layout, top to bottom:

```
┌────────────────────────────────────────────────────────────┐
│ Retainer 12 · Arc mainnet badge · contract link             │
│ Client 0xA1…9F   Freelancer 0x7C…22   Ends 24 Nov           │
│                                                            │
│  Available            Reserved           Paid to date       │
│  6.00 USDC            1.00 USDC          4.00 USDC          │
│                                                            │
│ ▸ Notice banner (if withdrawal pending):                    │
│   "The client asked to take back 7.00 USDC. It completes    │
│    in 3m 12s. Claims filed before then are still paid."     │
├────────────────────────────────────────────────────────────┤
│ Role panel (client or freelancer actions)                   │
├────────────────────────────────────────────────────────────┤
│ Claims (newest first) — each row has the fuse (§5.3)        │
├────────────────────────────────────────────────────────────┤
│ Activity — every event with time and explorer link          │
└────────────────────────────────────────────────────────────┘
```

**Client panel:** Top up · Request withdrawal (or Cancel / Complete if pending) · Extend end date · Withdraw remainder (only when ended). Per pending claim row: **Approve now** and **Object** (with optional reason).

**Freelancer panel:** File a claim (amount ≤ available, note ≤ 280 bytes with live byte counter) · per own pending claim: **Cancel claim**.

**Everyone:** per payable claim: **Pay out**. Per matured withdrawal: **Complete withdrawal**. If `owed[connected] > 0`: banner with **Withdraw 3.00 USDC owed to you**.

**Claim row states:**

| State | Visual | Actions |
|---|---|---|
| Pending, window open | Fuse burning, time left | Client: Approve now, Object · Freelancer: Cancel |
| Pending, payable | Fuse complete, "Ready to pay out" | Anyone: Pay out · Client: Approve now · Freelancer: Cancel |
| Paid (PaidOut) | "Paid out — no objection" with tx link | — |
| Paid (ApprovedNow) | "Approved by client" with tx link | — |
| Objected | "Client objected" + reason | — |
| Cancelled | "Cancelled by freelancer" | — |

**Empty states:** no claims → for freelancer "File your first claim when work is done"; for client "Claims from the freelancer will appear here"; for visitors "No claims yet".

**Not found:** "There's no retainer 99 on Arc mainnet." with a link home.

### 4.4 My retainers (`/#/me`)
Two lists: "You fund" and "You're paid from". Each row: id, counterparty, available, pending claims count, next event time. Empty: "You don't have any retainers yet" + Start a retainer.

## 5. Design system

### 5.1 Direction

The subject is a working agreement over time between two people. The visual language borrows from **carbon-copy job tickets and time cards**: duplicate-form blue ink, punched timestamps, perforated edges. It must read as calm and trustworthy, not as crypto. The one memorable element is the **fuse**: a claim's objection window drawn as a line that burns down to payout. Everything else stays quiet.

Avoid: cream background with terracotta accent; near-black with acid accent; uniform rounded cards with grey shadows; all-caps labels; monospace data labels; arrows appended to buttons; gradient washes.

### 5.2 Tokens

| Token | Hex | Use |
|---|---|---|
| `--paper` | `#F2F4F1` | Page background (cool, slightly green-grey) |
| `--ink` | `#1D2420` | Primary text |
| `--carbon` | `#2F45A6` | Primary actions, fuse, links (duplicate-form blue) |
| `--settled` | `#2D7A4E` | Paid states |
| `--objected` | `#B0322A` | Objections, destructive confirmations |
| `--rule` | `#C9D0CB` | Hairline dividers, perforation dots |
| `--muted` | `#5F6B64` | Secondary text |

Dark mode: `--paper #151A17`, `--ink #E6EBE7`, `--carbon #8FA2F2`, `--settled #6CC394`, `--objected #EE8A82`, `--rule #2C3530`, `--muted #9AA59E`. Respect `prefers-color-scheme`.

**Type:** Bricolage Grotesque (headings, the headline treatment) and Atkinson Hyperlegible (body, controls). Amounts use `font-variant-numeric: tabular-nums`; if Atkinson's tabular figures are unsatisfactory, use IBM Plex Sans for amount cells only. Fallback stacks: `system-ui, sans-serif`. Scale (rem): 0.875 / 1 / 1.25 / 1.563 / 2.441 / 3.815. Body line length ≤ 70ch.

**Shape:** perforated top edge (row of `--rule` dots) on the summary panel and on each claim row, like a tear-off ticket. Radii: 2 px on inputs, 0 on panels. One weight of border (1 px `--rule`).

### 5.3 The fuse

- A 2 px line in `--carbon` spanning the row width; the burned portion fades to `--rule`.
- Length = `(payableAt − chainNow) / objectionWindow`. Updates once per second.
- At zero, the line becomes a solid `--settled` bar with a small punched-timestamp mark showing `payableAt`.
- On a confirmed payout, one orchestrated moment: the bar fills and a "Paid" stamp appears with a 300 ms ease-out. Under `prefers-reduced-motion`, no animation; state changes instantly.

### 5.4 Accessibility floor
- WCAG AA contrast for all text on both themes.
- Visible focus rings (2 px `--carbon` outline, offset 2 px).
- Every countdown also renders as text ("Pays out in 4m 08s") and has an `aria-live="polite"` region that announces only state changes, not each tick.
- Buttons describe the action and amount: "Pay out 3.00 USDC".

### 5.5 Motion and polish: Emil Kowalski design references

Adopted 2026-10-25. The full skill set is vendored, unedited, in `docs/design-references/emil-kowalski/` (MIT, upstream commit `2d22863`). Use it as the standard for motion, interaction feel, mobile behaviour and edge cases.

**Precedence.** These references fill gaps; they never override this spec. Where they disagree with §5.1–5.4, the accessibility floor, or CLAUDE.md, the spec wins. Visual identity (tokens, type, perforations, the fuse) comes only from §5.1–5.3.

**Adopted as rules**

| Area | Rule | Source |
|---|---|---|
| Easing tokens | `--ease-out: cubic-bezier(0.23, 1, 0.32, 1)` for enter/exit and feedback; `--ease-in-out: cubic-bezier(0.77, 0, 0.175, 1)` for on-screen movement; `ease` for colour/hover; `linear` only for the fuse burn-down. Never `ease-in`. Never `transition: all`. | emil-design-eng |
| Durations | Press 100–160 ms; tooltips/popovers 125–200 ms; dialogs 200–250 ms; nothing in the UI above 300 ms. The §5.3 "Paid" stamp is 300 ms with `--ease-out`. Exits faster than enters. | emil-design-eng |
| Press feedback | Every button and pressable row: `transform: scale(0.97)` on `:active`, 160 ms `--ease-out`. | emil-design-eng |
| What animates | Only `transform` and `opacity` (the fuse may also animate its own colour). No animation on keyboard-initiated actions. Entries never start from `scale(0)`; use `scale(0.95)` + `opacity: 0`. Popovers scale from their trigger; dialogs stay centred. | emil-design-eng, animation-performance |
| Interruptibility | CSS transitions, not keyframes, for anything that can retrigger (claim rows changing state, transaction status). | emil-design-eng |
| Hover | Gate hover effects behind `@media (hover: hover) and (pointer: fine)`. | emil-design-eng, mobile-native |
| Reduced motion | §5.3 is stricter and wins: under `prefers-reduced-motion`, state changes instantly, with no movement. | spec §5.3 |
| Mobile | Inputs at least 16 px (no iOS zoom); `100dvh`, not `100vh`; safe-area insets; no tap-highlight flash; no sticky hover on touch. | mobile-native |
| Performance | Fuse updates once per second via `transform: scaleX()` on its own layer, not by changing `width`. | animation-performance |
| Libraries | Use what the scaffold already ships. If a primitive is missing, use the curated picks: base-ui for dialogs/popovers/menus, Sonner for transaction toasts, clsx for class composition. No hand-rolled dialogs or toasts. | pick-ui-library, ask-sonner |
| Edge cases | Before Gate 4, run the break-ui catalogue against every screen: long ENS-less addresses, 0.000001 and 1,000,000,000 USDC, 280-byte notes and reasons (multibyte), 0 and 20 pending claims, ended and never-funded retainers, `owed` credit present. Fix what breaks. | break-ui |
| Review | After each screen prompt, review its motion with review-animations, then find-animation-opportunities. Accept only additions that serve state indication or feedback. | review-animations, find-animation-opportunities |

**Not adopted for Unless**

- apple-design glass, translucency, depth shadows and scroll-edge fades instead of dividers. These conflict with §5.1–5.2: hairline 1 px `--rule` borders, 0 radius on panels, no grey shadows.
- Replacing borders with semi-transparent shadows. §5.2 sets one 1 px border weight.
- Decorative motion: stagger cascades, springs and bounce, 3D, clip-path showpieces, animated digit counters. §5.1 says the fuse is the one memorable element and everything else stays quiet.
- break-ui's "Demo data / Worst case" toggle, and prototype's variant switcher, in the shipped app. They may exist only in tests or a dev-only route excluded from the production build (CLAUDE.md rule 4).
- write-swift and animate-expo: native iOS / React Native only, not applicable to this web app. They are vendored for completeness.

## 6. Transaction UX

### 6.1 Lifecycle per action
`idle → preparing (simulate) → awaiting signature → submitted (hash + explorer link) → confirmed → refetch`. Each state is visible on the button that started it. Failures return to idle with an inline error under the button.

### 6.2 Simulation first
Every write calls `simulateContract` first. If simulation reverts, decode the custom error and show the message (§7) without opening the wallet.

### 6.3 Fee floor
```ts
const MIN_FEE = 20n * 10n ** 9n; // 20 gwei
const fees = await publicClient.estimateFeesPerGas();
const maxFeePerGas = fees.maxFeePerGas < MIN_FEE ? MIN_FEE : fees.maxFeePerGas;
const maxPriorityFeePerGas = fees.maxPriorityFeePerGas ?? 0n;
```
Pass both explicitly on every write. Arc drops transactions below 20 gwei silently.

### 6.4 Approvals
Exact amount only. Read `allowance(owner, RETAINER_ADDRESS)` first; skip approval if sufficient. Never approve more than the amount entered.

### 6.5 Network guard
Before any write: if `chainId !== expected`, show "Switch to Arc mainnet" which calls `wallet_switchEthereumChain` and, on error 4902, `wallet_addEthereumChain` with the config in §2.1.

### 6.6 Confirmation
Arc has deterministic sub-second finality: one receipt = final. Do not show "waiting for confirmations".

## 7. Error map (`lib/errors.ts`)

| Error | Message |
|---|---|
| `InvalidFreelancer` | Enter a freelancer address that isn't yours. |
| `WindowOutOfRange` | The objection window must be between 1 minute and 30 days. |
| `NoticeOutOfRange` | The withdrawal notice must be between 1 minute and 60 days. |
| `EndTimeTooSoon` | Choose an end date after the withdrawal notice period. |
| `EndTimeNotLater` | The new end date must be later than the current one. |
| `RetainerNotFound` | This retainer doesn't exist on this network. |
| `ClaimNotFound` | This claim doesn't exist. |
| `NotClient` | Only the client can do this. |
| `NotFreelancer` | Only the freelancer can do this. |
| `RetainerEnded` | This retainer has ended. |
| `RetainerNotEnded` | You can withdraw the remainder after the end date. |
| `ZeroAmount` | Enter an amount greater than zero. |
| `TextTooLong` | Keep it under 280 characters. |
| `TooManyPendingClaims` | There are already 20 claims waiting. Resolve one first. |
| `InsufficientAvailable` | That's more than the available balance. |
| `ClaimNotPending` | This claim has already been resolved. |
| `ObjectionWindowClosed` | The objection window has closed. This claim can now be paid out. |
| `ObjectionWindowOpen` | This claim can't be paid out until its objection window closes. |
| `WithdrawalAlreadyPending` | A withdrawal is already in progress. |
| `NoWithdrawalPending` | There's no withdrawal in progress. |
| `NoticeNotElapsed` | The withdrawal notice hasn't finished yet. |
| `NothingOwed` | Nothing is owed to this address. |
| `DepositMismatch` | The deposit didn't arrive as expected. No funds were recorded. |
| `InvalidToken` | Contract misconfigured. |
| ERC-20 allowance/balance revert | You don't have enough USDC approved or available. |
| User rejected | Transaction cancelled in your wallet. |
| Unknown | Something went wrong onchain. Check the transaction on the explorer. |

Keep the error ABI in sync with the contract: derive the map from the compiled ABI's error list and fail the build if any error lacks a message.

## 8. Data fetching

- `useRetainer(id)`: `getRetainer` every 4 s and after every confirmed tx.
- `useClaims(id)`: `getClaims(id, 0, claimCount)` (page in 20s if > 20).
- `useChainTime()`: fetch latest block timestamp every 10 s; between fetches, extrapolate with `performance.now()`. All "is it payable yet" logic uses chain time.
- `useActivity(id)`: `getLogs` for the contract's events filtered by `id`, starting at **the retainer's creation block**, read in chunks the RPC accepts. Find the creation block by binary search on block timestamps for `createdAt`, bounded below by the deployment block in `deployments/*.json`. There is no fixed lookback cap: claim notes and objection reasons exist only in events (ADR-008), so a capped range would silently drop them from older claims. A recent-window fallback is allowed only when the deployment block is unknown (address override), and the UI must then say history may be incomplete. Activity is informational; never gate actions on it.
  - *Corrected 2026-10-25:* the earlier default of "~200k blocks" assumed slow blocks. Arc testnet makes about 2 blocks per second (measured: 200,000 blocks = 28 h), so that default would have hidden notes after about a day.

## 9. Copy rules
- Sentence case everywhere. Active voice. Name the action and amount.
- The same action keeps its name end-to-end: button **Pay out 3.00 USDC** → toast "Paid out 3.00 USDC".
- No exclamation marks. No "Oops". Errors state what happened and what to do.
- Addresses shortened as `0x7C3a…9F22` with copy button and explorer link.
