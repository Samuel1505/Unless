# Mainnet evidence

Arc mainnet (chain 5042) · Contract [`0x766bBE6b3819261F7C1161073551A27362c96047`](https://explorer.arc.io/address/0x766bBE6b3819261F7C1161073551A27362c96047) · App https://unless-nu.vercel.app/ · Retainer 0

Amounts are one tenth of the original demo script (see docs/09-DEMO-SCRIPT.md). Every row was checked on chain with `cast` on 2026-11-01.

| Role | Address |
|---|---|
| Client | `0x89a68d0731F9Bc419d606f1F31Ead04c3fBDFdd6` |
| Freelancer | `0xe98540d28F45830E01D237251Bfc4777E69c9A46` |
| Deployer | `0x88aE55a562536862B6ec32784a640AaF0349b859` |

| # | Step | Actor | USDC movement | Tx hash |
|---|---|---|---|---|
| 0 | Deploy `UnlessRetainer` | Deployer | — | [`0x24a7f498…09ce`](https://explorer.arc.io/tx/0x24a7f49850ff628acd68880c611b39921de4366cb7c500fef2da9391225f09ce) |
| 1 | Approve exactly 1.00 USDC | Client | — | [`0x1b61e217…886f`](https://explorer.arc.io/tx/0x1b61e2174bab8e901f93f3bb386030b68c6925bb471d6956cae310518cea886f) |
| 2 | Create retainer 0 and deposit 1.00 USDC | Client | Client → contract 1.00 | [`0x21e2dd8d…2646`](https://explorer.arc.io/tx/0x21e2dd8d2aaec346726ec79b0338f39da7b2ed957652c3be7ec158c930d52646) |
| 3 | File claim #0 for 0.30 USDC | Freelancer | — (0.30 reserved) | [`0xde5f4c35…d795`](https://explorer.arc.io/tx/0xde5f4c359c8000064c3f33fac0a16e2248acdad17f715fbaa1e60fb7d258d795) |
| 4 | **Pay out claim #0 with no client action** | Freelancer | Contract → freelancer 0.30 | [`0x3080138c…49ca5`](https://explorer.arc.io/tx/0x3080138c62f1483ba7ccc702b977343621360fc47bdf0ef47f3b993fd5949ca5) |
| 5 | File claim #1 for 0.20 USDC | Freelancer | — | [`0xba0b76fd…49e0`](https://explorer.arc.io/tx/0xba0b76fdf668a03012f50d326108669ddf3a27ffcf4816ac1097050cfc41efc9) |
| 6 | Object to claim #1 | Client | — (0.20 unreserved) | [`0x09900884…15d2`](https://explorer.arc.io/tx/0x099008842fdb375735dfd4a7756977d712b33fa3bfbc3e67d773c1e5cff915d2) |
| 7 | Request withdrawal of 0.70 USDC | Client | — | [`0x64d57c64…49bfb`](https://explorer.arc.io/tx/0x64d57c641dfcb2c2d0ee8cdb99aeb034b890c0b031ca8180e94d0abd1b049bfb) |
| 8 | File claim #2 for 0.10 USDC during the notice | Freelancer | — | [`0x5c4e0c00…590d`](https://explorer.arc.io/tx/0x5c4e0c00cb3da73e268909841ab9c62f5b4f0cdc436e1c5a33e969f6bab9f90d) |
| 9 | Approve claim #2 now | Client | Contract → freelancer 0.10 | [`0x993c930f…cdc7`](https://explorer.arc.io/tx/0x993c930f521f1f5c51e853923e85792b4e3c8905f34dbb7eff4caa3de0d9cdc7) |
| 10 | Complete withdrawal | Freelancer (anyone may) | Contract → client 0.60 | [`0xffa11f61…49e0`](https://explorer.arc.io/tx/0xffa11f61c04dcb13bbb560e1283b5d5a7e0c0edbbbe3fb5b6b214f67dffe49e0) |

**Reconciliation (retainer 0, read on chain after row 10):** deposited 1.00 = paid 0.40 + returned 0.60 + balance 0.00. `WithdrawalCompleted` records requested 0.70, paid 0.60. The contract holds 0 USDC.

**Timing checks:** claim #0 was paid out at block time 1793544705, 42 s after its `payableAt` 1793544663, with no client transaction in between. The objection (row 6) came 204 s before claim #1's `payableAt`. Claim #2 (row 8) was filed 236 s before the withdrawal's `readyAt` 1793545281.

**Example transaction for the submission form:** row 4, `0x3080138c62f1483ba7ccc702b977343621360fc47bdf0ef47f3b993fd5949ca5`.

Full hashes:
```
0  0x24a7f49850ff628acd68880c611b39921de4366cb7c500fef2da9391225f09ce
1  0x1b61e2174bab8e901f93f3bb386030b68c6925bb471d6956cae310518cea886f
2  0x21e2dd8d2aaec346726ec79b0338f39da7b2ed957652c3be7ec158c930d52646
3  0xde5f4c359c8000064c3f33fac0a16e2248acdad17f715fbaa1e60fb7d258d795
4  0x3080138c62f1483ba7ccc702b977343621360fc47bdf0ef47f3b993fd5949ca5
5  0xba0b76fdf668a03012f50d326108669ddf3a27ffcf4816ac1097050cfc41efc9
6  0x099008842fdb375735dfd4a7756977d712b33fa3bfbc3e67d773c1e5cff915d2
7  0x64d57c641dfcb2c2d0ee8cdb99aeb034b890c0b031ca8180e94d0abd1b049bfb
8  0x5c4e0c00cb3da73e268909841ab9c62f5b4f0cdc436e1c5a33e969f6bab9f90d
9  0x993c930f521f1f5c51e853923e85792b4e3c8905f34dbb7eff4caa3de0d9cdc7
10 0xffa11f61c04dcb13bbb560e1283b5d5a7e0c0edbbbe3fb5b6b214f67dffe49e0
```
