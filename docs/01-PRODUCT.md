# 01 — Product Specification: Unless

## 1. The one-sentence product

A client prefunds a USDC retainer; the freelancer's claims for finished work pay out automatically **unless** the client objects within a set window.

## 2. The problem

Freelancers are paid late because payment requires the client to act. The work is done, the invoice is sent, and then the freelancer waits for someone else to click "pay". Survey data is consistent on the scale: in an Upwork/Censuswide study, 81% of offline freelancers had been paid late and they spent about 30 hours a year chasing payments; a Freelancers Union/Authors Guild survey found 91% of New York freelancers had been paid late at least once.

The known offline fix is the **retainer**: the client pays in advance and the freelancer draws against it. Prepayment largely removes late-payment risk, but it moves the risk to the client, who has handed over money and lost control of it. So most clients refuse, and most freelancers keep chasing invoices.

**The root cause is not cash, it is permission.** Every existing payment flow, including escrow, makes the client's approval the trigger. Unless removes the approval as the trigger and keeps it only as a veto.

## 3. Users

### 3.1 Primary: the freelancer
An independent professional (developer, designer, writer, consultant) with at least one **repeat** client, already paid in or comfortable with stablecoins. Typically paid across borders. Their pain: weeks of waiting, chasing emails, uncertainty about whether the next invoice will be honored.

**What they want from Unless:** to know the money for work exists before doing the work, and to be paid without having to ask twice.

### 3.2 Primary: the client
A small company, startup, or individual who hires the same freelancer repeatedly. Their pain with prepayment: losing control of money; paying for work that was not done; being unable to get unused money back.

**What they want from Unless:** to prepay only as much as they're comfortable with, to stop any claim they disagree with, and to get unused money back.

### 3.3 Secondary: anyone
Executing a matured claim is permissionless. A friend, a bot, or the freelancer can press the button. This matters for liveness, not for product positioning.

## 4. The core idea, as rules

1. The client funds a retainer for one named freelancer.
2. The freelancer files a claim: an amount and a short note describing the work.
3. A claim's money is **reserved** immediately. The client cannot withdraw reserved money.
4. The client may **approve now** (pays immediately) or **object** (cancels the claim, money returns to the available balance) while the objection window is open.
5. When the window closes with no objection, the claim becomes **payable** and anyone can **pay it out**.
6. The client can take unreserved money back only by **requesting a withdrawal**, which completes after a **notice period**. During notice, the freelancer can still claim for work already done; the withdrawal pays whatever remains unreserved at completion.
7. At the **end date**, the freelancer can no longer file claims. Already-filed claims still resolve normally. The client can then take back everything that is not reserved, immediately.

## 5. Flows

Each flow lists actor, preconditions, steps, and the onchain outcome. Every flow must work end-to-end on testnet before mainnet (CLAUDE.md Gate 3).

### F1 — Create and fund a retainer (client)
- **Pre:** client has USDC on Arc; knows freelancer's address.
- **Steps:** enter freelancer address, initial amount, objection window, notice period, end date → approve exact USDC amount → create.
- **Outcome:** retainer exists with an id; contract holds the deposit; public retainer page is live.

### F2 — Top up (client)
- **Pre:** retainer not ended.
- **Steps:** enter amount → approve exact → deposit.
- **Outcome:** balance increases.

### F3 — File a claim (freelancer)
- **Pre:** retainer not ended; amount ≤ available; fewer than 20 pending claims.
- **Steps:** enter amount and note → file.
- **Outcome:** claim is pending, money reserved, countdown visible to both parties.

### F4 — Silent payout (anyone) — **the product's signature moment**
- **Pre:** claim pending; objection window elapsed.
- **Steps:** press "Pay out" (anyone).
- **Outcome:** USDC moves from contract to freelancer. The client never said yes.

### F5 — Approve now (client)
- **Pre:** claim pending.
- **Outcome:** immediate payout to freelancer.

### F6 — Object (client)
- **Pre:** claim pending; window still open.
- **Steps:** optional reason → object.
- **Outcome:** claim objected; money unreserved; reason is public and permanent.

### F7 — Cancel own claim (freelancer)
- **Pre:** claim pending.
- **Outcome:** claim cancelled; money unreserved. (For typos and mistakes.)

### F8 — Request withdrawal with notice (client)
- **Pre:** retainer not ended; no other withdrawal pending; amount ≤ available.
- **Outcome:** withdrawal pending with a ready time; freelancer sees a notice banner.

### F9 — Complete withdrawal (anyone, pays client)
- **Pre:** notice elapsed.
- **Outcome:** client receives `min(requested, available now)`.

### F10 — Cancel withdrawal (client)

### F11 — Withdraw remainder after end (client)
- **Pre:** end date passed.
- **Outcome:** client receives all available (unreserved) money immediately.

### F12 — Extend end date (client)
- **Outcome:** end date moves later; nothing else changes.

### F13 — Recover deferred payout (any recipient)
- **Pre:** a payout to this address failed and was credited instead (e.g., the address was temporarily blocklisted).
- **Outcome:** recipient pulls the owed amount.

## 6. Vocabulary (binding)

| Term | Meaning | Never call it |
|---|---|---|
| Retainer | The funded agreement between one client and one freelancer | Escrow, vault, contract (in UI copy) |
| Client | The party who funds | Payer, employer, buyer |
| Freelancer | The party who claims | Worker, provider, payee, contractor |
| Claim | A freelancer's request to be paid a specific amount for finished work | Invoice, draw, payment request, milestone |
| Objection window | How long the client has to object to a claim | Review period, dispute window |
| Object | Client cancels a pending claim | Dispute, reject, decline |
| Approve now | Client pays a pending claim immediately | Accept, release |
| Pay out | Execute a matured claim | Release, settle, claim |
| Available | Balance minus reserved | Free balance |
| Reserved | Sum of pending claims | Locked, held |
| Withdrawal notice | Delay before the client's withdrawal completes | Cooldown, timelock |
| End date | After this, no new claims | Expiry, deadline |

UI copy is sentence case, active voice, and names the action that will happen ("Pay out 3.00 USDC", not "Submit").

## 7. Success criteria

**For the grant (by Oct 30):** the five-step mainnet script (09-DEMO-SCRIPT) executed between two real wallets, with the silent payout (F4) as the featured transaction.

**For the product (after the grant):** at least one real client-freelancer pair runs a retainer for two or more claims without the builder's involvement.

## 8. Out of scope for this deadline

Do not build these. Mention them only in "what's next".

- Arbitration or third-party dispute resolution
- Multiple freelancers per retainer, team retainers, splits
- Recurring automatic top-ups or scheduled claims
- Currencies other than USDC (no EURC)
- Fiat on/off-ramps
- Notifications (email, push, Telegram)
- Reputation scores, ratings, profiles
- Account abstraction, gas sponsorship, smart-wallet-specific flows
- Transaction memos via Arc's Memo contract (requires EOA direct calls; notes live in events instead)
- Indexer, subgraph, or any backend service
- Mobile app

## 9. Known limitations to state honestly

- **A client can object to every claim.** v1 has no arbiter. Objections are public and permanent, which is a reputational cost, and the freelancer can stop working. This is the first "go further" item.
- **The freelancer's note is self-reported.** The contract proves timing and money, not work quality.
- **Both parties need USDC on Arc.** Onboarding is outside the product.
