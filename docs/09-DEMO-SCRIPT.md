# 09 — Demo Script

Two scripts in one file:

- **Part A — Mainnet transaction script.** The exact sequence of real transactions that produces the evidence table. Executed once, carefully, on Arc mainnet.
- **Part B — Video script.** A 2:30–3:00 walkthrough showing the Studio build and the mainnet result.

Part A mirrors 03-CONTRACT-SPEC §14 exactly, and `test_workedExample_matchesSpecTable` already proves it works. If a mainnet step behaves differently from that table, stop and investigate before continuing.

---

## Part A — Mainnet transaction script

### A.1 Cast and wallets

| Role | Wallet | Browser profile | Funding |
|---|---|---|---|
| Client | Wallet C | Profile 1 (label the window "Client") | 15 USDC |
| Freelancer | Wallet F (ideally a real second person) | Profile 2 ("Freelancer") | 0.5 USDC (gas) |
| Anyone | Wallet X (optional) | Profile 3 ("Anyone") | 0.5 USDC (gas) |

Using a real second person as freelancer makes row 4 stronger evidence: USDC lands in a wallet the builder does not control. If not possible, use a separate wallet and say so honestly.

### A.2 Preflight (T−30 minutes)

- [ ] App is on the public URL, network badge says **Arc mainnet**
- [ ] `RETAINER_MAINNET` address in the app matches `deployments/arc-mainnet.json`
- [ ] Each profile connected to the right wallet, on chain 5042
- [ ] Wallet C USDC ≥ 11.5; F and X have gas
- [ ] `evidence/mainnet-transactions.md` open for pasting hashes
- [ ] Screen recorder running on all three profiles (capture raw footage now; edit later)
- [ ] A clock visible on screen (system clock is fine; the app shows chain time)
- [ ] Phone on do-not-disturb

### A.3 Parameters

```
Freelancer:        <Wallet F address>
Starting amount:   10.00 USDC
Objection window:  5 minutes   (300 s)
Withdrawal notice: 5 minutes   (300 s)
End date:          7 days from now
```

### A.4 Steps

Times are relative to the create transaction (t = 0). Each step: action, expected result, what to record.

| t | Profile | Action in app | Expect | Record |
|---|---|---|---|---|
| −0:30 | Client | Create retainer form → **Approve 10.00 USDC** | Wallet asks for exactly 10.00 USDC | Row 1 hash |
| 0:00 | Client | **Create retainer** | Redirect to `/#/r/<id>`; Available 10.00 | Row 2 hash; retainer id |
| 0:30 | Freelancer | Open `/#/r/<id>` → **File a claim** 3.00, note "Week 1: landing page" | Claim #0 pending, fuse burning, "Pays out in 4m 59s"; Available 7.00, Reserved 3.00 | Row 3 hash |
| 0:30–5:30 | Client | **Do nothing.** Show the client view with Approve now / Object buttons visible and untouched | Fuse burns down | — |
| 5:30 | Anyone (or Freelancer) | **Pay out 3.00 USDC** | Claim #0 "Paid out — no objection"; Wallet F USDC +3.00 | **Row 4 hash (featured)** |
| 6:00 | Freelancer | **File a claim** 2.00, note "Extra revisions" | Claim #1 pending | Row 5 hash |
| 6:40 | Client | **Object**, reason "Not agreed in scope" | Claim #1 "Client objected"; Available 7.00 | Row 6 hash |
| 7:00 | Client | **Request withdrawal** 7.00 | Notice banner on both views: completes in 5:00 | Row 7 hash |
| 7:30 | Freelancer | **File a claim** 1.00, note "Final handoff call" | Claim #2 pending; Available 6.00; banner still shows | Row 8 hash |
| 7:40 | Client | **Approve now** on claim #2 | Claim #2 "Approved by client"; Wallet F +1.00 | Row 9 hash |
| 12:00 | Anyone | **Complete withdrawal** | Client receives **6.00** (not 7.00); Available 0.00 | Row 10 hash |

### A.5 Post-run checks

- [ ] Retainer page shows: Paid to date 4.00, Available 0.00, Reserved 0.00
- [ ] Wallet F received exactly 4.00 USDC
- [ ] Wallet C received exactly 6.00 USDC back
- [ ] Reconciliation line written under the evidence table
- [ ] Every hash opens on explorer.arc.io
- [ ] Optionally run `arc-cast call $RETAINER "getRetainer(uint256)" <id>` and save the output to evidence

### A.6 Contingencies

| Problem | Response |
|---|---|
| Tx doesn't appear | Fee too low; check wallet's max fee ≥ 20 gwei; check nonce before resending |
| Pay out button shows early or late | Chain-time sync issue in the app; the contract is authoritative — try anyway; record the bug |
| Wrong amount typed | Freelancer cancels the claim (F7), refile; record the extra rows honestly |
| Object pressed after window closed | Expected revert `ObjectionWindowClosed`; capture it — it's a good demo of the boundary |
| Something unexpected moves money | Stop. Compare to spec §14. Do not continue the script until explained |

If the run is spoiled, create a fresh retainer and redo it. Keep the spoiled one in the evidence with a note; honest evidence beats a clean story.

---

## Part B — Video script

**Target length:** 2:30–3:00. **Format:** screen recording + voiceover, 1080p. Cut all waiting. Show real UI only; no slides except an optional 3-second title card.

### B.1 Shot list

| Time | Segment | On screen | Voiceover (read naturally) |
|---|---|---|---|
| 0:00–0:15 | Problem | Home page headline | "Freelancers wait to be paid because every payment needs the client to say yes. Unless flips that: claims pay out unless the client objects." |
| 0:15–0:45 | The moment | Client and freelancer windows side by side; fuse burning on claim #0; client's Approve/Object buttons untouched; cut to fuse complete; Anyone presses **Pay out**; Paid stamp | "The client funded ten dollars. The freelancer claimed three for finished work. The client did nothing. Five minutes later, anyone can pay it out — and the freelancer has the money." |
| 0:45–1:00 | Proof | Explorer page for row 4: from contract to freelancer, 3 USDC | "That's a real transaction on Arc mainnet: USDC moving from the contract to the freelancer, with no approval from the client." |
| 1:00–1:25 | Client control | Claim #1 → Object with reason; then withdrawal request → notice banner; claim #2 during notice → Approve now | "The client stays in control. They can object, and the money goes back. To take money out, they give notice — and anything the freelancer claims before then still gets paid." |
| 1:25–1:40 | Withdrawal completes | Complete withdrawal → client receives 6.00, not 7.00 | "The client asked for seven back. One dollar was owed for work, so they get six." |
| 1:40–2:20 | Built in Arc Studio | Studio workspace: the contract prompt and generated contract; the test prompt; test run output scrolling with passes and invariant results; app preview in Studio on testnet; Studio's testnet deployment output | "I built all of it in Arc Studio: the contract from a written spec, a full unit and invariant test suite that Studio wrote and ran, and the app. Studio deployed it to testnet, where I ran every flow." |
| 2:20–2:40 | Lineage | Terminal: arc-forge deploy to mainnet; `bytecode-match.txt` with two identical hashes | "Then I pushed from Studio to GitHub and deployed the same commit to mainnet with Arc Foundry. The bytecode on testnet and mainnet is identical." |
| 2:40–2:55 | What's next | README "What's next" | "Next: an optional arbiter, recurring retainers, and team retainers." |
| 2:55–3:00 | Close | Live app URL + Studio project URL | "Unless. Live on Arc mainnet." |

### B.2 Recording rules

- Record Studio footage **during** the build (Phases 1–4), not reconstructed afterwards. Keep timestamps visible where possible.
- Show the Studio project URL in the address bar at least once.
- Zoom browser to 125% so amounts are readable; hide bookmarks bar; use a clean browser profile.
- Never show private keys, seed phrases, or `.env` files.
- Use the real voice of the builder; a calm pace beats energy.

### B.3 Edit checklist

- [ ] The silent payout appears in the first 45 seconds
- [ ] Explorer proof of row 4 is on screen for at least 4 seconds
- [ ] Studio test output is visible, not just mentioned
- [ ] Studio project URL visible
- [ ] Bytecode-match hashes visible
- [ ] Total length ≤ 3:00
- [ ] Captions burned in or provided (reviewers often watch muted)
