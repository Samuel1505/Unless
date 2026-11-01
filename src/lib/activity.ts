import { decodeEventLog, type Hash, type Hex } from 'viem'
import { retainerAbi } from '@/app-config/retainer-abi.generated'
import { PAID_VIA } from '@/hooks/useRetainer'
import { describeSpan } from '@/lib/createRetainer'
import { formatDate, formatDateTime, formatUsdcPlain } from '@/lib/format'

/** A raw log as returned by eth_getLogs. */
export interface RpcLogLike {
  blockNumber: Hex
  logIndex: Hex
  transactionHash: Hash
  data: Hex
  topics: readonly Hex[]
}

function decode(log: RpcLogLike) {
  return decodeEventLog({ abi: retainerAbi, data: log.data, topics: log.topics as [Hex, ...Hex[]] })
}

export type DecodedEvent = ReturnType<typeof decode>

export interface ActivityItem {
  key: string
  blockNumber: bigint
  logIndex: number
  transactionHash: Hash
  event: DecodedEvent
}

/** Decodes a log, or returns undefined when it is not one of this contract's events. */
export function toActivityItem(log: RpcLogLike): ActivityItem | undefined {
  try {
    return {
      key: `${log.transactionHash}:${BigInt(log.logIndex)}`,
      blockNumber: BigInt(log.blockNumber),
      logIndex: Number(BigInt(log.logIndex)),
      transactionHash: log.transactionHash,
      event: decode(log),
    }
  } catch {
    return undefined
  }
}

export function byNewest(a: ActivityItem, b: ActivityItem): number {
  if (a.blockNumber !== b.blockNumber) return a.blockNumber > b.blockNumber ? -1 : 1
  return b.logIndex - a.logIndex
}

/** What the claim rows need from the events: the note and reason text, and the payout transaction. */
export interface ClaimDetail {
  note?: string
  reason?: string
  paidTx?: Hash
}

export function claimDetails(items: readonly ActivityItem[]): Map<number, ClaimDetail> {
  const details = new Map<number, ClaimDetail>()
  const entry = (claimId: bigint) => {
    const key = Number(claimId)
    const existing = details.get(key) ?? {}
    details.set(key, existing)
    return existing
  }
  for (const item of items) {
    const { event } = item
    if (event.eventName === 'ClaimFiled') entry(event.args.claimId).note = event.args.note
    if (event.eventName === 'ClaimObjected') entry(event.args.claimId).reason = event.args.reason
    if (event.eventName === 'ClaimPaid') entry(event.args.claimId).paidTx = item.transactionHash
  }
  return details
}

export interface ActivityLine {
  text: string
  /** The full note or reason, shown under the line. */
  detail?: string
}

const usdc = (raw: bigint) => `${formatUsdcPlain(raw)} USDC`

/** One plain sentence per event, in the vocabulary of 01-PRODUCT section 6. */
export function describeActivity(event: DecodedEvent): ActivityLine {
  switch (event.eventName) {
    case 'RetainerCreated':
      return {
        text: `Retainer created. Objection window ${describeSpan(event.args.objectionWindow)}, withdrawal notice ${describeSpan(event.args.noticePeriod)}, ends ${formatDate(event.args.endTime)}.`,
      }
    case 'Deposited':
      return { text: `The client added ${usdc(event.args.amount)}. The balance is now ${usdc(event.args.newBalance)}.` }
    case 'ClaimFiled':
      return {
        text: `The freelancer filed claim ${event.args.claimId} for ${usdc(event.args.amount)}. It pays out ${formatDateTime(event.args.payableAt)} unless the client objects.`,
        detail: event.args.note === '' ? undefined : event.args.note,
      }
    case 'ClaimPaid':
      return {
        text:
          event.args.via === PAID_VIA.ApprovedNow
            ? `The client approved claim ${event.args.claimId} now. ${usdc(event.args.amount)} went to the freelancer.`
            : `Claim ${event.args.claimId} paid out with no objection. ${usdc(event.args.amount)} went to the freelancer.`,
      }
    case 'ClaimObjected':
      return {
        text: `The client objected to claim ${event.args.claimId}.`,
        detail: event.args.reason === '' ? undefined : event.args.reason,
      }
    case 'ClaimCancelled':
      return { text: `The freelancer cancelled claim ${event.args.claimId}.` }
    case 'WithdrawalRequested':
      return {
        text: `The client asked to take back ${usdc(event.args.amount)}. It can be completed from ${formatDateTime(event.args.readyAt)}.`,
      }
    case 'WithdrawalCancelled':
      return { text: 'The client cancelled the withdrawal.' }
    case 'WithdrawalCompleted':
      return {
        text:
          event.args.paid === event.args.requested
            ? `Withdrawal completed. ${usdc(event.args.paid)} went back to the client.`
            : `Withdrawal completed. ${usdc(event.args.paid)} went back to the client; ${usdc(event.args.requested)} was requested, and claims filed during the notice were paid first.`,
      }
    case 'RemainderWithdrawn':
      return { text: `The client withdrew the remaining ${usdc(event.args.amount)}.` }
    case 'EndTimeExtended':
      return { text: `The client moved the end date to ${formatDate(event.args.newEndTime)}.` }
    default:
      return { text: event.eventName }
  }
}
