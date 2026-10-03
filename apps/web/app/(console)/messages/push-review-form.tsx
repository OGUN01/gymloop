'use client';

import { useState } from 'react';

/**
 * The owner/manager review commit for one push campaign (NTF-011). The frozen
 * confirm facts — title, kind, current version, eligible count, quiet hours —
 * are acknowledged explicitly before the review POSTs; the response is
 * permission to attempt, never evidence of receipt. The section renders the
 * form only for a real owner/manager, with the facts supplied by the push
 * review deep link (`?pushReview=<announcementId>&pushVersion=<n>`).
 */
export function PushCampaignReviewForm({ announcementId, versionNo, title, kind, quietHoursNote }: {
  announcementId: string;
  versionNo: number;
  title: string;
  kind: string;
  quietHoursNote: string;
}) {
  const [confirmed, setConfirmed] = useState(false);
  const [result, setResult] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const review = async () => {
    if (!confirmed || busy) return;
    setBusy(true);
    try {
      const requestKey = globalThis.crypto?.randomUUID?.() ?? crypto.randomUUID();
      const response = await fetch(`/api/announcements/${encodeURIComponent(announcementId)}/push-review`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ versionNo, requestKey }),
      });
      const payload = await response.json() as { ok: boolean; data?: { eligibleCount: number; versionNo: number }; error?: { message: string } };
      setResult(payload.ok && payload.data
        ? `Reviewed: version ${payload.data.versionNo} · ${payload.data.eligibleCount} eligible ${payload.data.eligibleCount === 1 ? 'member' : 'members'}. Acceptance is permission to attempt, never a receipt.`
        : payload.error?.message ?? 'That review could not be saved. Try again.');
    } catch {
      setResult('That review could not be saved. Check your connection and try again.');
    } finally {
      setBusy(false);
      setConfirmed(false);
    }
  };
  return <form className="comms-push-review" onSubmit={(event) => { event.preventDefault(); void review(); }}>
    <dl className="comms-push-facts">
      <dt>Title</dt><dd>{title}</dd>
      <dt>Kind</dt><dd>{kind}</dd>
      <dt>Current version</dt><dd>v{versionNo}</dd>
      <dt>Quiet hours</dt><dd>{quietHoursNote}</dd>
    </dl>
    <label className="cl-field comms-push-confirm">
      <span>I confirm these facts and the eligible count shown at review time, and I have read the quiet-hours notice.</span>
      <input type="checkbox" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} />
    </label>
    <button type="submit" className="cl-btn" disabled={!confirmed || busy}>Review push campaign</button>
    {result !== null ? <p className="comms-push-result" role="status">{result}</p> : null}
  </form>;
}
