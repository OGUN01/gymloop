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
      if (!result || typeof result !== 'object') throw new Error('Unavailable');
      if (!response.ok || result.ok !== true) { const code = typeof result.error?.code === 'string' ? result.error.code : ''; setConflict(code === 'announcement_version_conflict'); setError(code === 'invalid_request' ? 'Check the announcement fields and try again.' : code === 'not_signed_in' ? 'Sign in to continue.' : code === 'not_permitted' ? 'Your staff role cannot perform this action.' : announcementRefusalMessage(code === 'announcement_rate_limited' ? 'publish_rate_limited' : code && result.ok === false && typeof result.error?.message === 'string' && (['announcement_not_found', 'announcement_not_draft', 'announcement_not_live', 'announcement_not_published', 'announcement_expiry_invalid', 'announcement_image_unavailable', 'announcement_live_limit', 'announcement_version_limit', 'announcement_version_conflict', 'announcement_no_change', 'announcement_failed'].includes(code)) ? code.replace(/^announcement_/, '') : 'unknown_outcome')); return null; }
      const data = result.data;
      if (!data || typeof data !== 'object' || Array.isArray(data)) throw new Error('Unavailable');
      const action = path.split('/').at(-1);
      if (action === 'announcements' ? typeof data.announcementId !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(data.announcementId) : action === 'edit' ? !Number.isSafeInteger(data.versionNo) || data.versionNo < 1 || typeof data.newVersion !== 'boolean' : action === 'publish' ? typeof data.publishedAt !== 'string' || !Number.isFinite(Date.parse(data.publishedAt)) || !Number.isSafeInteger(data.audienceCount) || data.audienceCount < 0 || (data.expiresAt !== null && (typeof data.expiresAt !== 'string' || !Number.isFinite(Date.parse(data.expiresAt)))) : action === 'draft' ? data.updated !== true : action === 'discard' ? data.discarded !== true : action === 'unpublish' ? data.unpublished !== true : Object.keys(data).length === 0) throw new Error('Unavailable');
      router.refresh(); return result.data as Record<string, unknown>;
    } catch { if (isCurrent()) setError(announcementRefusalMessage('unknown_outcome')); return null; }
    finally { if (pending.current === lifetime) pending.current = null; if (isCurrent()) setBusy(false); }
  };
  return { send, isCurrent, online, busy, error, conflict, setError, preview, disabled: preview || busy || !online };
}
export function AnnouncementCommandStatus({ command }: { command: ReturnType<typeof useAnnouncementCommand> }) { return <>{!command.online ? <p className="cl-alert" role="status">You're offline. Announcements can't be loaded or saved until you reconnect.</p> : null}{command.error ? <p className="cl-alert" role="alert">{command.error}</p> : null}{command.conflict ? <a className="cl-btn" href={typeof window === 'undefined' ? '/announcements' : window.location.pathname}>Reload</a> : null}{command.busy ? <p role="status">Saving…</p> : null}</>; }
