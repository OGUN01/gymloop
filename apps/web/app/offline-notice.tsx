'use client';

import { forwardRef, useEffect, useState } from 'react';
import Link from 'next/link';

/**
 * The one web offline banner (frozen SLF-017/TRV-008/LDC-011 offline copy
 * surface): the browser's own connectivity events are the truth, the probe
 * renders nothing on the server (a production server render has no meaningful
 * `navigator.onLine`), and a reconnect is discovered the same way. Each
 * feature wraps it with its own frozen copy and refresh affordance instead of
 * duplicating the listener plumbing. The render-time `navigator.onLine` check
 * is kept exactly as the original banners had it, so a static render of an
 * offline browser still shows the banner.
 */
/** The render-time browser fact the banners and the submit guards share. */
export function isBrowserOffline(): boolean {
  return typeof navigator !== 'undefined' && navigator.onLine === false;
}

export const OfflineNotice = forwardRef<HTMLParagraphElement, { copy: string; refreshHref?: string }>(function OfflineNotice({ copy, refreshHref }, ref) {
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
  const browserOffline = isBrowserOffline();
  if (!browserOffline && synced !== true) return null;
  return (
    <p ref={ref} role="status" className="cl-alert" data-tone="warn">
      {copy}
      {refreshHref ? <Link className="cl-btn" href={refreshHref}>Refresh</Link> : null}
    </p>
  );
});