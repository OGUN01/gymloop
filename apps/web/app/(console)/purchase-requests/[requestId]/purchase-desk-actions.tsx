'use client';

import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { BUY_LIMITS, formatMoney } from '@gymloop/shared';
import { runPurchaseAction } from '../../../../lib/purchase-commands';

const REASON_LABEL = 'Reason (shown to the member)';

/**
 * Verifier and approver commands. The confirmation block always discloses the
 * request quotation, the actually received amount, the method and that the
 * currently viewed screenshot is what is being judged — never a blind commit.
 */
export function DeskPurchaseActions({ requestId, status, proofStatus, amountPaise, currency, expectedRevision }: {
  requestId: string; status: string; proofStatus: string; amountPaise: string; currency: string; expectedRevision: string | null;
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [reason, setReason] = useState('');
  const [actualAmount, setActualAmount] = useState(amountPaise);
  const [method, setMethod] = useState<'upi' | 'cash'>('upi');
  const [confirming, setConfirming] = useState(false);
  const run = (path: string, body: Record<string, unknown>) => runPurchaseAction(path, body, { busy, setBusy, setMessage, onOk: () => { setConfirming(false); router.refresh(); } });
  const trimmed = reason.trim();
  const reasonInvalid = trimmed.length < BUY_LIMITS.reasonMinLength || trimmed.length > BUY_LIMITS.reasonMaxLength;
  const open = status === 'requested' || status === 'owner_accepted' || status === 'payment_proof_uploaded' || status === 'mismatch_recorded';
  const verifiable = (status === 'payment_proof_uploaded' && proofStatus === 'active') || status === 'owner_accepted';
  return <section className="space-y-3" aria-label="Desk decisions">
    {!open ? <p className="cl-muted">This request is closed. Its history cannot change.</p> : null}
    {status === 'requested' || status === 'owner_accepted' ?
      <div className="flex flex-wrap gap-3">
        <button className="cl-btn" disabled={busy} onClick={() => void run(`/api/purchase-requests/${requestId}/accept`, { expectedRevision: expectedRevision ?? '', commandKey: crypto.randomUUID() })}>Accept request</button>
        <button className="cl-btn cl-btn--quiet" disabled={busy} onClick={() => setConfirming(true)}>Decline request</button>
      </div> : null}
    {verifiable ?
      <div className="space-y-2 p-4 rounded-lg border" role="group" aria-label="Verify and record payment">
        <p>Quotation: {formatMoney(amountPaise, currency)}</p>
        <p>The money was collected outside the app. Confirm the amount the gym actually received.</p>
        <label className="block" htmlFor="actual-amount">Actually received, in paise</label>
        <input id="actual-amount" className="cl-input" inputMode="numeric" value={actualAmount} onChange={event => setActualAmount(event.target.value.replace(/[^0-9]/g, ''))} aria-invalid={!/^[1-9][0-9]*$|^\d+$/.test(actualAmount)} />
        <label className="block" htmlFor="payment-method">Method</label>
        <select id="payment-method" className="cl-input" value={method} onChange={event => setMethod(event.target.value === 'cash' ? 'cash' : 'upi')}>
          <option value="upi">UPI</option>
          <option value="cash">Cash</option>
        </select>
        <button className="cl-btn" disabled={busy} onClick={() => setConfirming(true)}>Record payment</button>
        {method === 'cash' ? <p>Cash received without a screenshot: recording confirms you collected the cash yourself.</p> : null}
      </div> : null}
    {confirming ?
      <div className="space-y-2 p-4 rounded-lg border" role="group" aria-label="Confirm decision">
        <h3 className="cl-section-title">Before you commit</h3>
        <p>Quotation {formatMoney(amountPaise, currency)} · actually received {formatMoney(/^\d+$/.test(actualAmount) ? actualAmount : '0', currency)} · method {method}. The currently viewed screenshot is the evidence you are judging; it is the member&apos;s claim, not proof the gym received the money.</p>
        <label className="block" htmlFor="decision-reason">{REASON_LABEL}</label>
        <input id="decision-reason" className="cl-input" value={reason} onChange={event => setReason(event.target.value)} aria-invalid={reasonInvalid} />
        {reasonInvalid ? <p role="status">Use {BUY_LIMITS.reasonMinLength}–{BUY_LIMITS.reasonMaxLength} characters. This is shown to the member.</p> : null}
        <div className="flex flex-wrap gap-3">
          <button className="cl-btn" disabled={busy || reasonInvalid} onClick={() => void run(`/api/purchase-requests/${requestId}/record`, { expectedRevision: expectedRevision ?? '', commandKey: crypto.randomUUID(), actualAmount, currency: 'INR', method })}>Commit: record payment</button>
          <button className="cl-btn cl-btn--quiet" disabled={busy || reasonInvalid} onClick={() => void run(`/api/purchase-requests/${requestId}/reject`, { expectedRevision: expectedRevision ?? '', commandKey: crypto.randomUUID(), reason: trimmed })}>Decline request</button>
          <button className="cl-btn cl-btn--quiet" disabled={busy || reasonInvalid} onClick={() => void run(`/api/purchase-requests/${requestId}/reject-proof`, { assetId: '', expectedRevision: expectedRevision ?? '', commandKey: crypto.randomUUID(), reason: trimmed })}>Reject proof</button>
          <button className="cl-btn cl-btn--quiet" disabled={busy} onClick={() => setConfirming(false)}>Go back</button>
        </div>
      </div> : null}
    {message ? <p role="status">{message}</p> : null}
  </section>;
}
