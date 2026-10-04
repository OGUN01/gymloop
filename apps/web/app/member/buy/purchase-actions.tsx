'use client';

import { useRouter } from 'next/navigation';
import { useRef, useState } from 'react';
import { MEDIA_LIMITS, MEDIA_MIME_TYPES, purchaseRequestRefusalMessage, type MediaMime } from '@gymloop/shared';
import { runPurchaseAction } from '../../../lib/purchase-commands';
import { uploadPaymentProof, type MediaUploadStage } from '../../../lib/media-upload';

/**
 * Member commands for an open request: attach the payment screenshot or
 * cancel. Every command answers its refusal honestly; nothing is queued
 * offline (BUY-021), and a screenshot is the member's claim — never payment
 * truth (BUY-022).
 */

type UploadStage = 'staging' | 'putting' | 'confirming';

const STAGE_WORDS: Record<UploadStage, string> = {
  staging: 'Uploading screenshot…',
  putting: 'Uploading screenshot…',
  confirming: 'The gym is checking the upload…',
};

/** The shared transport's two stages land on this component's honest words. */
const STAGE_WORDS_FROM_TRANSPORT: Record<MediaUploadStage, UploadStage> = {
  uploading: 'putting',
  verifying: 'confirming',
};

export function MemberPurchaseActions({ requestId, proofStatus, status, acceptedRevision }: { requestId: string; proofStatus: string; status: string; acceptedRevision: string | null }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [stage, setStage] = useState<UploadStage | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const fileInput = useRef<HTMLInputElement>(null);
  const run = (path: string, body: Record<string, unknown>) => runPurchaseAction(path, body, { busy, setBusy, setMessage, onOk: () => router.refresh() });

  const upload = async (file: File) => {
    if (busy) return;
    setMessage(null);
    const mime = (MEDIA_MIME_TYPES as readonly string[]).includes(file.type) ? file.type as MediaMime : null;
    if (!mime || file.size < 1 || file.size > MEDIA_LIMITS.maxBytes || !acceptedRevision) {
      setMessage(purchaseRequestRefusalMessage(!acceptedRevision ? 'operation_failed' : 'upload_rejected'));
      return;
    }
    setBusy(true);
    try {
      await uploadPaymentProof(file, requestId, acceptedRevision, crypto.randomUUID(), transportStage => setStage(STAGE_WORDS_FROM_TRANSPORT[transportStage]));
      setMessage('Screenshot uploaded. Pending verification — the gym checks the received money.');
      router.refresh();
    } catch (error) {
      setMessage(error instanceof Error && error.message ? error.message : purchaseRequestRefusalMessage('operation_failed'));
    } finally {
      setStage(null);
      setBusy(false);
    }
  };

  return <div className="space-y-2">
    {status === 'owner_accepted' ? <>
      <input ref={fileInput} type="file" accept="image/jpeg,image/png,image/webp" className="sr-only" aria-label="Payment screenshot" onChange={event => { const file = event.target.files?.[0]; event.target.value = ''; if (file) void upload(file); }} />
      <button className="cl-btn" disabled={busy} onClick={() => fileInput.current?.click()}>{proofStatus === 'rejected' ? 'Re-upload payment screenshot' : 'Upload payment screenshot'}</button>
      <p>JPG, PNG or WebP up to 2 MB. The gym checks the received money before your purchase counts.</p>
      {stage ? <p role="status">{STAGE_WORDS[stage]}</p> : null}
    </> : null}
    <button className="cl-btn cl-btn--quiet" disabled={busy} onClick={() => void run(`/api/member/purchase-requests/${requestId}/cancel`, { commandKey: crypto.randomUUID() })}>Cancel request</button>
    {message ? <p role="status">{message}</p> : null}
  </div>;
}