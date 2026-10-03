'use client';

import { forwardRef, useEffect, useState } from 'react';
import Link from 'next/link';

/**
 * TRV-008's web offline banner (frozen trainer-view proposal), following the
 * LeadsOfflineNotice pattern: the browser's own connectivity events are the
 * truth, the probe renders nothing on the server, and a reconnect is discovered
 * the same way. The forwardRef boundary keeps this a client-side concern —
 * server rendering of the day view never invokes its effects.
 */
const OFFLINE_COPY = "You're offline. Connect to load your sessions.";

function isBrowserOffline(): boolean {
  return typeof navigator !== 'undefined' && navigator.onLine === false;
}

export const TrainerOfflineNotice = forwardRef<HTMLParagraphElement, { refreshHref?: string }>(function TrainerOfflineNotice({ refreshHref = '/training' }, ref) {
  const [synced, setSynced] = useState<boolean | null>(null);
  useEffect(() => {
    const update = () => setSynced(navigator.onLine === false);
    update();
    window.addEventListener('online', update);
    window.addEventListener('offline', update);
    return () => {
      window.removeEventListener('online', update);
      window.removeEventListener('offline', update);
    };
  }, []);
  if (!isBrowserOffline() && synced !== true) return null;
  return <p ref={ref} role="status" className="cl-alert" data-tone="warn">{OFFLINE_COPY}<Link className="cl-btn" href={refreshHref}>Refresh</Link></p>;
});
