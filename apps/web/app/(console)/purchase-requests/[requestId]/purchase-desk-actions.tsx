'use client';

import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { BUY_LIMITS, formatMoney } from '@gymloop/shared';
import { runPurchaseAction } from '../../../../lib/purchase-commands';

const REASON_LABEL = 'Reason (shown to the member)';

/**
 * Verifier and approver commands with the exact-proof viewer. The viewer
 * fetches a bounded same-origin capability URL for the request's currently
 * ACTIVE proof and enables recording only after that exact screenshot has
 * rendered; rejection and recording bind the exact viewed asset and revision,
 * and the confirmation block always discloses the request quotation, the
 * actually received amount, the method and that the currently viewed
 * screenshot is the member's claim — never a blind commit and never money
 * truth from an upload alone (BUY-009/010/011/012/022/025).
 */
export function DeskPurchaseActions({ requestId, status, proofStatus, amountPaise, currency, expectedRevision, activeProofAssetId }: {
  requestId: string; status: string; proofStatus: string; amountPaise: string; currency: string; expectedRevision: string | null; activeProofAssetId: string | null;
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [reason, setReason] = useState('');
  const [actualAmount, setActualAmount] = useState(amountPaise);
  const [method, setMethod] = useState<'upi' | 'cash'>('upi');
  const [confirming, setConfirming] = useState(false);
  const [proofUrl, setProofUrl] = useState<string | null>(null);
  const [proofLoaded, setProofLoaded] = useState(false);
  const showProof = status === 'payment_proof_uploaded' && proofStatus === 'active' && activeProofAssetId !== null;
  useEffect(() => {
    if (!showProof) return;
    let live = true;
    void (async () => {
      try {
        const answer = await fetch(`/api/purchase-requests/${requestId}/proof-url`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' });
        const envelope = await answer.json().catch(() => null);
        const url = envelope?.ok === true && typeof envelope.data?.url === 'string' ? envelope.data.url : null;
        if (live) setProofUrl(url);
      } catch { if (live) setProofUrl(null); }
    })();
    return () => { live = false; };
  }, [showProof, requestId]);
  const run = (path: string, body: Record<string, unknown>) => runPurchaseAction(path, body, { busy, setBusy, setMessage, onOk: () => { setConfirming(false); router.refresh(); } });
  const trimmed = reason.trim();
  const reasonInvalid = trimmed.length < BUY_LIMITS.reasonMinLength || trimmed.length > BUY_LIMITS.reasonMaxLength;
  const open = status === 'requested' || status === 'owner_accepted' || status === 'payment_proof_uploaded' || status === 'mismatch_recorded';
  // The verify group is visible from first paint with its full disclosure;
  // the record commit itself stays disabled until the exact active screenshot
  // has rendered for this verifier. A cash request may be recorded without a
  // screenshot through the explicit received-cash path (BUY-012).
  const showsVerification = (status === 'payment_proof_uploaded' && proofStatus === 'active') || status === 'owner_accepted';
  const recordDisabled = busy || (status === 'payment_proof_uploaded' && !proofLoaded);
  const viewedFacts = activeProofAssetId && expectedRevision ? { viewedAssetId: activeProofAssetId, viewedProofRevision: expectedRevision } : {};
  return <section className="space-y-3" aria-label="Desk decisions">
    {!open ? <p className="cl-muted">This request is closed. Its history cannot change.</p> : null}
    {showProof ?
      <section className="space-y-2" aria-label="Payment proof viewer" data-proof-path={`/api/purchase-requests/${requestId}/proof-asset`}>
        {proofUrl ?
          <img src={proofUrl} alt="Payment screenshot" className="max-w-full rounded-lg border" onLoad={() => setProofLoaded(true)} />
          : <p role="status">Loading the payment screenshot…</p>}
        <p className="cl-muted">This screenshot is the member&apos;s claim. The gym still checks the money actually received.</p>
      </section>
      : null}
    {status === 'requested' || status === 'owner_accepted' ?
      <div className="flex flex-wrap gap-3">
        <button className="cl-btn" disabled={busy} onClick={() => void run(`/api/purchase-requests/${requestId}/accept`, { expectedRevision: expectedRevision ?? '', commandKey: crypto.randomUUID() })}>Accept request</button>
        <button className="cl-btn cl-btn--quiet" disabled={busy} onClick={() => setConfirming(true)}>Decline request</button>
      </div> : null}
    {showsVerification ?
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
        <button className="cl-btn" disabled={recordDisabled} onClick={() => setConfirming(true)}>Record payment</button>
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
          <button className="cl-btn" disabled={busy || reasonInvalid} onClick={() => void run(`/api/purchase-requests/${requestId}/record`, { expectedRevision: expectedRevision ?? '', commandKey: crypto.randomUUID(), actualAmount, currency: 'INR', method, ...viewedFacts })}>Commit: record payment</button>
          <button className="cl-btn cl-btn--quiet" disabled={busy || reasonInvalid} onClick={() => void run(`/api/purchase-requests/${requestId}/reject`, { expectedRevision: expectedRevision ?? '', commandKey: crypto.randomUUID(), reason: trimmed })}>Decline request</button>
          <button className="cl-btn cl-btn--quiet" disabled={busy || reasonInvalid || !activeProofAssetId} onClick={() => void run(`/api/purchase-requests/${requestId}/reject-proof`, { assetId: activeProofAssetId ?? '', expectedRevision: expectedRevision ?? '', commandKey: crypto.randomUUID(), reason: trimmed })}>Reject proof</button>
          <button className="cl-btn cl-btn--quiet" disabled={busy} onClick={() => setConfirming(false)}>Go back</button>
        </div>
      </div> : null}
    {message ? <p role="status">{message}</p> : null}
  </section>;
}