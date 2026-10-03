'use client';

import { useState } from 'react';

/**
 * The member's own WhatsApp consent controls (WSP-002). Each button is one
 * explicit grant or revoke for one purpose; no bulk grant exists. The notice
 * version shown is the version the settings projection carries — consent is
 * only accepted against a displayed, versioned notice.
 */

export type WhatsappConsentControlsProps = {
  noticeVersion: string;
  current: { service: boolean; marketing: boolean };
};

const WRITE_FAILURE = 'The WhatsApp consent could not be recorded. Nothing was written.';

export function WhatsappConsentControls({ noticeVersion, current }: WhatsappConsentControlsProps) {
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [granted, setGranted] = useState(current);

  const write = async (purpose: 'service' | 'marketing', next: boolean) => {
    if (busy) return;
    setBusy(true);
    setNotice(null);
    try {
      const response = await fetch('/api/member/whatsapp-consent', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ purpose, granted: next, noticeVersion }),
      });
      const envelope = (await response.json()) as { ok: boolean; error?: { message: string } };
      if (response.ok && envelope.ok) {
        setGranted((previous) => ({ ...previous, [purpose]: next }));
        setNotice(next
          ? purpose === 'service'
            ? 'WhatsApp service updates are on.'
            : 'WhatsApp offers and news are on.'
          : purpose === 'service'
            ? 'WhatsApp service updates are off.'
            : 'WhatsApp offers and news are off.');
      } else {
        setNotice(envelope.error?.message ?? WRITE_FAILURE);
      }
    } catch {
      setNotice('That consent could not be recorded. Check the connection and try again.');
    } finally {
      setBusy(false);
    }
  };

  const rows: { purpose: 'service' | 'marketing'; title: string; detail: string }[] = [
    { purpose: 'service', title: 'Service updates', detail: 'Renewals, class changes, receipts on the gym’s WhatsApp number.' },
    { purpose: 'marketing', title: 'Offers and news', detail: 'Promotions from your gym, only with your separate yes.' },
  ];

  return (
    <section aria-label="WhatsApp consent">
      {rows.map((row) => (
        <div key={row.purpose}>
          <h3>{row.title}</h3>
          <p>{row.detail}</p>
          <p>{granted[row.purpose] ? 'On' : 'Off'}</p>
          <button type="button" disabled={busy} onClick={() => write(row.purpose, !granted[row.purpose])}>
            {granted[row.purpose] ? 'Turn off' : 'Turn on'}
          </button>
        </div>
      ))}
      <p>Notice version accepted: {noticeVersion}</p>
      {notice !== null ? <p aria-live="polite">{notice}</p> : null}
    </section>
  );
}
