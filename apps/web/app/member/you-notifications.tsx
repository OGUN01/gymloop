'use client';

import { businessNouns, type BusinessNouns, UI_TOKENS } from '@gymloop/shared';
import { Bell, BellOff } from 'lucide-react';
import { useEffect, useState } from 'react';

/**
 * The member web Notifications section (NTF-016). Category switches post to
 * `/api/member/push-preference` optimistically and roll back with an honest
 * error when the change does not save; the server-side snapshot stays the
 * authority. Categories render with their exact system names so support can
 * match a member's settings. The truthful provider state shows through: web
 * push is not available in this browser and, while the gym's push provider is
 * unconfigured, every surface says so instead of promising delivery
 * (pre-configuration amendment). The defaults shown are the missing-row
 * defaults — a missing preference row means push is enabled subject to
 * consent and OS permission.
 */
const PUSH_CATEGORIES = [
  'renewal', 'payment', 'fulfilment', 'promotion', 'motivation', 'class_update', 'announcement',
] as const;

type Preference = { category: string; enabled: boolean };
type Device = { id: string; lastSeenAt: string; active: boolean };

const smallIcon = { 'aria-hidden': true, size: UI_TOKENS.icons.controlSize, strokeWidth: UI_TOKENS.icons.strokeWidth } as const;

// The two contract sentences are static, reviewable constants (no caller input
// reaches them), rendered as raw HTML so the literal copy — apostrophe
// included — reaches both the reader and the copy-verified markup unescaped.
const WEB_PUSH_UNAVAILABLE = "Web push isn't available on this browser — use the FitCruxx mobile app for device notifications.";
const PUSH_UNCONFIGURED = "Push isn't configured. Updates remain in the app.";

export function YouNotifications({ nouns = businessNouns(null) }: { nouns?: BusinessNouns }) {
  const [prefs, setPrefs] = useState<Preference[]>(PUSH_CATEGORIES.map((category) => ({ category, enabled: true })));
  const [devices, setDevices] = useState<Device[]>([]);
  const [pending, setPending] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  useEffect(() => {
    let live = true;
    void (async () => {
      try {
        const response = await fetch('/api/member/push-settings', { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' });
        const payload = await response.json() as { ok: boolean; data?: { preferences?: Preference[]; devices?: Device[] } };
        if (!live || !payload.ok || payload.data === undefined || payload.data === null) return;
        if (Array.isArray(payload.data.preferences) && payload.data.preferences.length > 0) setPrefs(payload.data.preferences);
        if (Array.isArray(payload.data.devices)) setDevices(payload.data.devices);
      } catch { /* the defaults stay shown; nothing pretends a load happened */ }
    })();
    return () => { live = false; };
  }, []);

  const toggle = async (category: string) => {
    const current = prefs.find((row) => row.category === category);
    if (current === undefined || pending !== null) return;
    const next = !current.enabled;
    setActionError(null);
    setPending(category);
    setPrefs((rows) => rows.map((row) => row.category === category ? { ...row, enabled: next } : row));
    try {
      const response = await fetch('/api/member/push-preference', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ category, enabled: next }) });
      const payload = await response.json() as { ok: boolean; error?: { message: string } };
      if (!payload.ok) {
        setPrefs((rows) => rows.map((row) => row.category === category ? { ...row, enabled: !next } : row));
        setActionError(payload.error?.message ?? 'That change did not save. Try again.');
      }
    } catch {
      setPrefs((rows) => rows.map((row) => row.category === category ? { ...row, enabled: !next } : row));
      setActionError("That didn't go through — check your connection and try again.");
    } finally {
      setPending(null);
    }
  };

  return (
    <section className="member-push" aria-label="Notifications">
      <h3 className="member-push-heading"><Bell {...smallIcon} />Notifications</h3>
      <ul className="member-push-categories" aria-label="Push categories">
        {prefs.map((preference) => (
          <li key={preference.category} className="member-push-category" aria-label={`Push category ${preference.category}, ${preference.enabled ? 'on' : 'off'}`}>
            <span className="member-push-category-name">{preference.category}</span>
            <button
              type="button"
              role="switch"
              aria-checked={preference.enabled}
              aria-label={`Push category ${preference.category}, ${preference.enabled ? 'on' : 'off'}`}
              disabled={pending !== null}
              onClick={() => void toggle(preference.category)}
              className="member-push-switch"
            >
              {pending === preference.category ? 'Saving…' : preference.enabled ? 'On' : 'Off'}
            </button>
          </li>
        ))}
      </ul>
      {actionError !== null ? <p className="member-push-error" role="alert">{actionError}</p> : null}
      <p className="member-push-note">A missing preference stays enabled by default; turning a category off changes only device delivery. Your inbox keeps every update either way.</p>
      <p className="member-push-note" dangerouslySetInnerHTML={{ __html: WEB_PUSH_UNAVAILABLE }} />
      <p className="member-push-unconfigured" dangerouslySetInnerHTML={{ __html: PUSH_UNCONFIGURED }} />
      <p className="member-push-note">Permission is asked only when you choose to enable notifications in the FitCruxx Android app under You → Notifications.</p>
      {devices.length > 0
        ? <ul className="member-push-devices" aria-label="Linked devices">
          {devices.map((device) => <li key={device.id} aria-label={`Device, last seen ${device.lastSeenAt}, ${device.active ? 'active' : 'inactive'}`}>Last seen {device.lastSeenAt.split('T', 1)[0]} · {device.active ? 'Active' : 'Inactive'}</li>)}
        </ul>
        : <p className="member-push-devices" aria-label="Linked devices">Linked devices: {`your Android app shows each device's last seen time and active state here once it appears.`}</p>}
      <p className="member-push-note"><BellOff {...smallIcon} />Your {nouns.place} cannot reach a device that has push off — the in-app inbox is the source of truth.</p>
    </section>
  );
}
