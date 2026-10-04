import { describe, expect, it } from 'vitest';

// NTF app-layer holdout (API/route boundary layer). Author is implementation-blind:
// no push implementation exists yet. Section A anchors the PRESERVED boundary
// (notificationResult's exact ten keys) that the frozen contract forbids widening.
// Section B pins the six route files the frozen proposal names, with their
// POST-only shape and their unauthenticated fail-closed behavior. Section C is an
// explicit deferral: rendered/state/a11y holdouts are a separate layer per the
// held-suite convention (rendered phases author their own held files); no `todo`
// markers are used to hide coverage, only this header records the split.
//
// Route URLs derive from the frozen proposal's "Proposed routes" list; concrete
// App Router module names derive from the public NTF POST routes registry row.
// Dynamic segment labels do not change the public URL/identity boundary.
//
// This suite does not touch the database, never reads other Wave C suites, and
// never claims delivery evidence of any kind.

// ---------------------------------------------------------------------------
// Section A — the preserved member result boundary (dec3278 §"Shared lifecycle")
// ---------------------------------------------------------------------------

import { notificationResult, whatsappOpenResult } from '../../apps/web/lib/comms';

const valid = {
  notificationId: '01f8c5c1-7601-4c01-8111-000000000001',
  memberId: '01f8c5c1-7601-4c01-8111-000000000002',
  channel: 'in_app',
  status: 'delivered',
  sentAt: '2026-10-03T10:00:00Z',
  deliveredAt: '2026-10-03T10:01:00Z',
  failedAt: null,
  failedReason: null,
  optedOutAt: null,
  optedOutReason: null,
};

const CHANNELS = ['in_app', 'push', 'whatsapp_link', 'sms', 'email'];
const STATUSES = ['scheduled', 'sent', 'delivered', 'failed', 'clicked', 'converted', 'opted_out'];

describe('NTF preserved result boundary held', () => {
  it('exact ten keys accept a well-formed result', () => {
    expect(notificationResult({ ...valid })).toEqual(valid);
    expect(notificationResult({ ...valid, status: 'sent', deliveredAt: null })).toEqual({ ...valid, status: 'sent', deliveredAt: null });
  });

  it('provider, token, lease or cost evidence never widens the member envelope', () => {
    // dec3278: no token, phone, secret, provider id or lease in member/staff
    // envelopes — the exact-key contract must reject NTF's transport evidence.
    for (const leak of ['providerMessageId', 'pushToken', 'reservationId', 'attemptId', 'ttlSeconds', 'costPaise']) {
      expect(notificationResult({ ...valid, [leak]: 'x' }), `extra ${leak} must not widen the envelope`).toBeNull();
    }
  });

  it('missing, mis-typed or unknown-vocabulary fields refuse', () => {
    for (const key of Object.keys(valid)) {
      const broken = { ...valid } as Record<string, unknown>;
      delete broken[key];
      expect(notificationResult(broken), `missing ${key}`).toBeNull();
    }
    expect(notificationResult({ ...valid, channel: 'whatsapp_paid' })).toBeNull();
    expect(notificationResult({ ...valid, status: 'queued' })).toBeNull();
    // every canonical vocabulary label must stay accepted — the enum is frozen
    for (const channel of CHANNELS) expect(notificationResult({ ...valid, channel })).not.toBeNull();
    for (const status of STATUSES) expect(notificationResult({ ...valid, status })).not.toBeNull();
    expect(notificationResult({ ...valid, sentAt: 123 as never })).toBeNull();
    expect(notificationResult({ ...valid, notificationId: 'not-a-uuid' })).toBeNull();
    expect(notificationResult({ ...valid, memberId: undefined })).toBeNull();
  });

  it('paired failure and opt-out evidence never splits', () => {
    expect(notificationResult({ ...valid, failedAt: '2026-10-03T10:02:00Z', failedReason: null })).toBeNull();
    expect(notificationResult({ ...valid, failedAt: null, failedReason: 'unregistered' })).toBeNull();
    expect(notificationResult({ ...valid, status: 'failed', deliveredAt: null, failedAt: '2026-10-03T10:02:00Z', failedReason: 'provider_unconfigured' })).not.toBeNull();
    expect(notificationResult({ ...valid, optedOutAt: '2026-10-03T10:02:00Z', optedOutReason: null })).toBeNull();
    expect(notificationResult({ ...valid, status: 'opted_out', deliveredAt: null, optedOutAt: '2026-10-03T10:02:00Z', optedOutReason: 'consent_withdrawn' })).not.toBeNull();
  });

  it('whatsapp open result keeps its exact {notification,url} pair', () => {
    expect(whatsappOpenResult({ notification: valid, url: 'https://wa.me/910000000000' })).not.toBeNull();
    expect(whatsappOpenResult({ notification: valid })).toBeNull();
    expect(whatsappOpenResult({ notification: valid, url: '' })).toBeNull();
    expect(whatsappOpenResult({ ...valid, url: 'https://wa.me/1' })).toBeNull();
    expect(whatsappOpenResult({ notification: valid, url: 'https://wa.me/1', providerMessageId: 'x' })).toBeNull();
    expect(whatsappOpenResult({ notification: { ...valid, failedAt: 'x', failedReason: null }, url: 'u' })).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// Section B — the six frozen member/admin routes: POST-only, fail closed
// ---------------------------------------------------------------------------

const ROUTES: { name: string; path: string }[] = [
  { name: 'member push-device register', path: '../../apps/web/app/api/member/push-device/route' },
  { name: 'member push-device remove', path: '../../apps/web/app/api/member/push-device/remove/route' },
  { name: 'member push-preference', path: '../../apps/web/app/api/member/push-preference/route' },
  { name: 'member push-event evidence', path: '../../apps/web/app/api/member/notifications/[id]/push-event/route' },
  { name: 'campaign push review', path: '../../apps/web/app/api/announcements/[announcementId]/push-review/route' },
  { name: 'campaign cancel', path: '../../apps/web/app/api/push-campaigns/[campaignId]/cancel/route' },
];

const enumValuesPrefix = 'http://localhost/api/member/push-device';

async function routeModule(path: string) {
  // Relative dynamic specifiers resolve against the project root under
  // vite-node; anchor them to this file with URL so the pinned paths mean
  // the pinned files.
  return await import(/* @vite-ignore */ new URL(path, import.meta.url).href);
}

describe('NTF frozen route boundary held', () => {
  it.each(ROUTES)('$name exports POST only and exists at the pinned path', async ({ path, name }) => {
    const mod = await routeModule(path);
    expect(mod, `${name} module`).toBeTruthy();
    expect(typeof mod.POST, `${name} must expose POST`).toBe('function');
    expect(mod.GET ?? mod.PUT ?? mod.DELETE ?? mod.PATCH, `${name} is POST-only (reads go through RPC, not this route)`).toBeUndefined();
  });

  it.each(ROUTES)('$name fail-closes an unauthenticated malformed POST', async ({ path, name }) => {
    const mod = await routeModule(path);
    const response = await mod.POST(
      new Request(`${enumValuesPrefix}/probe-${encodeURIComponent(name)}`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: '{"bogus":[}',
      }),
    );
    expect(response instanceof Response, `${name} returns a Response, never throws open`).toBe(true);
    expect([400, 401, 403], `${name} unauthenticated status`).toContain(response.status);
    const body = (await response.json()) as { ok?: boolean; error?: { code?: string; message?: string } };
    expect(body.ok, `${name} failure envelope`).toBe(false);
    expect(typeof body.error?.code, `${name} refusal code`).toBe('string');
    expect(typeof body.error?.message, `${name} refusal message`).toBe('string');
    // No success path may leak transport evidence or member identity on refusal.
    const raw = JSON.stringify(body);
    for (const leak of ['pushToken', 'provider', 'tokenRevision', 'reservation']) expect(raw, `${name} refusal leak`).not.toContain(leak);
  });
});
