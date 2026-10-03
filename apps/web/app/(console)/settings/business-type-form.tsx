'use client';

import { BUSINESS_TYPES, BUSINESS_TYPE_LABELS, BUSINESS_TYPE_SUMMARIES, businessNouns, isBusinessType, UI_TOKENS, type BusinessType, type BusinessTypeChange } from '@gymloop/shared';
import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { usePreviewReadOnly } from '../../preview-context';
import { Alert } from '../alert';

export function BusinessTypeForm({ currentType, businessName, readOnly = false }: { currentType: BusinessType; businessName: string; readOnly?: boolean }) {
  const preview = usePreviewReadOnly() || readOnly;
  const router = useRouter();
  const [current, setCurrent] = useState(currentType);
  const [selected, setSelected] = useState(currentType);
  const [saving, setSaving] = useState(false);
  const [offline, setOffline] = useState(() => typeof navigator !== 'undefined' && navigator.onLine === false);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);
  const previousType = useRef(currentType);
  const radios = useRef<Partial<Record<BusinessType, HTMLInputElement | null>>>({});
  useEffect(() => {
    const previous = previousType.current;
    previousType.current = currentType;
    if (previous === currentType) return;
    setCurrent(currentType);
    setSelected((choice) => choice === previous ? currentType : choice);
    if (current !== currentType) { setError(null); setStatus(null); }
  }, [currentType, current]);
  useEffect(() => {
    const online = () => setOffline(false), disconnected = () => setOffline(true);
    window.addEventListener('online', online); window.addEventListener('offline', disconnected);
    return () => { window.removeEventListener('online', online); window.removeEventListener('offline', disconnected); };
  }, []);
  const cancel = () => { setSelected(current); setError(null); radios.current[current]?.focus(); };
  const nouns = businessNouns(selected), before = businessNouns(current);
  const words = (type: BusinessType) => { const row = businessNouns(type); return `${row.place} · ${row.members} · ${row.classes} · ${row.trainer}s`; };
  const confirm = async () => {
    if (preview || offline || saving || selected === current) return;
    setSaving(true); setError(null); setStatus(null);
    try {
      const response = await fetch('/api/business-type', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ businessType: selected }) });
      const result = await response.json().catch(() => null) as { ok: boolean; data?: BusinessTypeChange; error?: { code?: string } } | null;
      if (!response.ok || !result?.ok || !result.data || !isBusinessType(result.data.businessType) || typeof result.data.changed !== 'boolean') {
        setError(result?.error?.code === 'not_permitted' ? 'Only the owner can change this.' : 'The change was not saved. Check the connection and try again.'); return;
      }
      const saved = result.data, next = businessNouns(saved.businessType);
      setCurrent(saved.businessType); setSelected(saved.businessType);
      setStatus(saved.changed ? `Saved. FitCruxx now says ${next.place}, ${next.members}, ${next.trainer}. To tell your ${next.members}, send a message from Messages.` : `Already set to ${BUSINESS_TYPE_LABELS[saved.businessType]}. Nothing changed.`);
      router.refresh();
    } catch { setOffline(true); } finally { setSaving(false); }
  };
  return <div aria-busy={saving} onKeyDown={(event) => { if (event.key === 'Escape' && !saving) { event.preventDefault(); cancel(); } }}>
    {preview ? <p>Read-only support preview.</p> : null}
    <fieldset disabled={saving || preview} className="cl-form"><legend className="cl-section-title">What kind of business is this?</legend>
      {BUSINESS_TYPES.map((type) => <label key={type} className="cl-field" style={{ minHeight: UI_TOKENS.geometry.targets.touch, display: 'flex', alignItems: 'flex-start', gap: UI_TOKENS.geometry.spacing[2], paddingBlock: UI_TOKENS.geometry.spacing[2] }}>
        <input ref={(node) => { radios.current[type] = node; }} type="radio" name="business-type" value={type} checked={selected === type} disabled={saving || preview} onChange={() => { setSelected(type); setStatus(null); setError(null); }} />
        <span><strong>{BUSINESS_TYPE_LABELS[type]}{current === type ? ' · Current' : ''}</strong><span style={{ display: 'block' }}>{BUSINESS_TYPE_SUMMARIES[type]}</span><small>Words used: {words(type)}</small></span>
      </label>)}
    </fieldset>
    {offline ? <p role="status">You’re offline. Reconnect to change this.</p> : null}
    {selected !== current && !preview ? <section className="cl-section" aria-labelledby="business-confirm-title">
      <h3 id="business-confirm-title" className="cl-section-title">Switch to {BUSINESS_TYPE_LABELS[selected]} wording?</h3>
      <p>Current words: {before.place} · {before.members} · {before.classes} · {before.trainer}</p><p>New words: {words(selected)}</p>
      <p>Everyone at {businessName} sees the new words next time they open FitCruxx: {nouns.place}, {nouns.members}, {nouns.classes}, {nouns.trainer}. Plans, payments, check-ins and messages already sent stay exactly as they are.</p>
      <div className="cl-actions"><button className="cl-btn cl-btn--primary" type="button" disabled={offline || saving} onClick={confirm}>{saving ? 'Saving…' : 'Confirm change'}</button><button className="cl-btn" type="button" disabled={saving} onClick={cancel}>Keep current</button></div>
    </section> : null}
    {error ? <Alert>{error}</Alert> : null}{status ? <p role="status">{status}</p> : null}
  </div>;
}
