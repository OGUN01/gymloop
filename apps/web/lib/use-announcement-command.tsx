'use client';
import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { announcementRefusalMessage } from '@gymloop/shared';
import { usePreviewReadOnly } from '../app/preview-context';
export function useAnnouncementCommand(viewKey = '') {
  const preview = usePreviewReadOnly();
  const mounted = useRef(false); const currentView = useRef({ viewKey, preview });
  if (currentView.current.viewKey !== viewKey || currentView.current.preview !== preview) currentView.current = { viewKey, preview };
  const lifetime = currentView.current;
  const isCurrent = () => mounted.current && currentView.current === lifetime;
  const router = useRouter(); const pending = useRef<typeof lifetime | null>(null);
  const [online, setOnline] = useState(true); const [busy, setBusy] = useState(false); const [error, setError] = useState<string | null>(null); const [conflict, setConflict] = useState(false);
  useEffect(() => { mounted.current = true; const update = () => setOnline(navigator.onLine); update(); window.addEventListener('online', update); window.addEventListener('offline', update); return () => { mounted.current = false; window.removeEventListener('online', update); window.removeEventListener('offline', update); }; }, [lifetime]);
  const send = async (path: string, body: unknown): Promise<Record<string, unknown> | null> => {
    if (!isCurrent() || preview || pending.current === lifetime || !navigator.onLine) return null;
    pending.current = lifetime; setBusy(true); setError(null); setConflict(false);
    try { const response = await fetch(path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body), cache: 'no-store' }); if (!isCurrent()) return null; const result = await response.json(); if (!isCurrent()) return null;
      if (!response.ok || result.ok !== true) { const code = typeof result.error?.code === 'string' ? result.error.code : ''; setConflict(code === 'announcement_version_conflict'); setError(code === 'invalid_request' ? 'Check the announcement fields and try again.' : announcementRefusalMessage(code === 'announcement_rate_limited' ? 'publish_rate_limited' : code.replace(/^announcement_/, ''))); return null; }
      router.refresh(); return result.data as Record<string, unknown>;
    } catch { if (isCurrent()) setError('The connection was interrupted. Reload to check whether the change was saved.'); return null; }
    finally { if (pending.current === lifetime) pending.current = null; if (isCurrent()) setBusy(false); }
  };
  return { send, isCurrent, online, busy, error, conflict, setError, preview, disabled: preview || busy || !online };
}
export function AnnouncementCommandStatus({ command }: { command: ReturnType<typeof useAnnouncementCommand> }) { return <>{!command.online ? <p className="cl-alert" role="status">You're offline. Announcements can't be loaded or saved until you reconnect.</p> : null}{command.error ? <p className="cl-alert" role="alert">{command.error}</p> : null}{command.conflict ? <a className="cl-btn" href={typeof window === 'undefined' ? '/announcements' : window.location.pathname}>Reload</a> : null}{command.busy ? <p role="status">Saving…</p> : null}</>; }
