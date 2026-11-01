import type { Hex } from 'viem'
import { CLAIM_STATUS, PAID_VIA } from '@/hooks/useRetainer'

/** A claim as read from getClaims. The note itself is not stored, only its hash (ADR-006). */
export interface ClaimView {
  amount: bigint
  filedAt: bigint
  payableAt: bigint
  status: number
  paidVia: number
  noteHash: Hex
}

/** What a claim row shows, derived from chain data and chain time only. */
export type ClaimPhase = 'open' | 'payable' | 'paid' | 'objected' | 'cancelled' | 'unknown'

/**
 * Pending claims split on payableAt: before it the client can object; at it and after it the claim is
 * payable and can no longer be objected to (03-CONTRACT-SPEC section 5). `payable` is null until chain
 * time is known.
 */
export function claimPhase(claim: ClaimView, payable: boolean | null): ClaimPhase | null {
  switch (claim.status) {
    case CLAIM_STATUS.Pending:
      return payable === null ? null : payable ? 'payable' : 'open'
    case CLAIM_STATUS.Paid:
      return 'paid'
    case CLAIM_STATUS.Objected:
      return 'objected'
    case CLAIM_STATUS.Cancelled:
      return 'cancelled'
    default:
      return 'unknown'
  }
}

export function isApprovedNow(claim: ClaimView): boolean {
  return claim.paidVia === PAID_VIA.ApprovedNow
}

/** Limits of the deployed retainer (MAX_TEXT_BYTES, MAX_PENDING_CLAIMS in the frozen contract). */
export const MAX_TEXT_BYTES = 280
export const MAX_PENDING_CLAIMS = 20

const encoder = new TextEncoder()

/** The contract limits notes and reasons in bytes, not characters: an emoji is four. */
export function utf8Bytes(text: string): number {
  return encoder.encode(text).length
}
