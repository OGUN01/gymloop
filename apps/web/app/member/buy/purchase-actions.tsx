'use client';

import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { runPurchaseAction } from '../../../lib/purchase-commands';

/**
 * Member commands for an open request: replace the payment screenshot or
 * cancel. Every command answers its refusal honestly; nothing is queued
 * offline (BUY-021).
 */
export function MemberPurchaseActions({ requestId, proofStatus }: { requestId: string; proofStatus: string }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const run = (path: string, body: Record<string, unknown>) => runPurchaseAction(path, body, { busy, setBusy, setMessage, onOk: () => router.refresh() });
  return <div className="space-y-2">
    {proofStatus !== 'active' ? <button className="cl-btn" disabled={busy} onClick={() => void run(`/api/member/purchase-requests/${requestId}/proof-upload-url`, {})}>Upload payment screenshot</button> : null}
    <button className="cl-btn cl-btn--quiet" disabled={busy} onClick={() => void run(`/api/member/purchase-requests/${requestId}/cancel`, { commandKey: crypto.randomUUID() })}>Cancel request</button>
    {message ? <p role="status">{message}</p> : null}
  </div>;
}
