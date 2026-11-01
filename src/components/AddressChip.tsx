import { useState } from 'react'
import { Check, Copy, ExternalLink } from 'lucide-react'
import { explorerAddressUrl, shortAddress } from '@/lib/format'

/** 0x7C3a…9F22 with a copy button and an explorer link (05-FRONTEND-SPEC section 9). */
export function AddressChip({ address, label }: { address: string; label?: string }) {
  const [copied, setCopied] = useState(false)

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(address)
      setCopied(true)
      setTimeout(() => setCopied(false), 1500)
    } catch {
      setCopied(false)
    }
  }

  return (
    <span className="inline-flex items-center gap-1.5">
      <span className="num" title={address}>
        {shortAddress(address)}
      </span>
      <button
        type="button"
        onClick={() => void copy()}
        className="icon-btn"
        aria-label={`Copy ${label ?? 'address'}`}
      >
        {copied ? <Check size={16} aria-hidden="true" /> : <Copy size={16} aria-hidden="true" />}
      </button>
      <a
        href={explorerAddressUrl(address)}
        target="_blank"
        rel="noopener noreferrer"
        className="icon-btn"
        aria-label={`View ${label ?? 'address'} on the explorer`}
      >
        <ExternalLink size={16} aria-hidden="true" />
      </a>
    </span>
  )
}
