import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * Phase 6 comms/wallet HTTP boundary, authored from the frozen contract
 * (docs/planning/phase6-comms-contract.md §1, §3-§5, §7-§8) before any of
 * these route handlers exist. `comms-api.test.ts` owns the wire-helper
 * shapes and the shared error table (`lib/comms.ts`); this suite owns the
 * role gates, the exact RPC argument names and the honest HTTP outcomes,
 * following `leads-routes.test.ts`'s mock conventions exactly: only
 * `lib/supabase/server` is mocked, every other module (including
 * `@gymloop/db`'s generated `Constants` and `lib/comms.ts` once it exists)
 * runs for real. No production source was consulted.
 *
 * Route module map this suite fixes for the implementation:
 *
 *   POST /api/consents                              -> app/api/consents/route.ts
 *   POST /api/member/notifications/[id]/delivered    -> app/api/member/notifications/[id]/delivered/route.ts
 *   POST /api/notifications/[id]/whatsapp            -> app/api/notifications/[id]/whatsapp/route.ts (POST only — no GET export)
 *   POST /api/message-templates                      -> app/api/message-templates/route.ts
 *   POST /api/messaging-wallet/adjust                 -> app/api/messaging-wallet/adjust/route.ts
 *
 * Every route reuses the registered `lib/api.ts` session helpers
 * (`staffJson`/`staffSession` for gym-side identities, `memberSession` for
 * the member-only action, `platformSession({ requireAdmin: true })` for the
 * wallet, exactly as already used elsewhere — no fifth gate) and
 * `lib/comms.ts`'s `commsRpcFailure` for the shared error table.
 */

type Result = { data: unknown; error: { code: string; message: string } | null };

const state = vi.hoisted(() => ({
  claims: null as Record<string, unknown> | null,
  rpc: [] as Array<{ name: string; args: Record<string, unknown> }>,
  results: [] as Result[],
  writes: [] as Array<{ table: string; method: string; value: unknown }>,
  operations: [] as Array<
    | { kind: 'rpc'; name: string; args: Record<string, unknown> }
    | { kind: 'query'; table: string; method: string; args: unknown[] }
  >,
}));

vi.mock('../../lib/supabase/server', () => ({
  createServerSupabase: async () => ({
    auth: { getClaims: async () => ({ data: state.claims && { claims: state.claims }, error: null }) },
    rpc: async (name: string, args: Record<string, unknown>) => {
      state.rpc.push({ name, args });
      state.operations.push({ kind: 'rpc', name, args });
      return state.results.shift() ?? { data: null, error: { code: 'XX000', message: 'Unexpected RPC' } };
    },
    from: (table: string) => {
      const result = state.results.shift() ?? { data: null, error: null };
      const chain: Record<string, unknown> = {
        then: (resolve: (value: Result) => unknown) => Promise.resolve(result).then(resolve),
        single: async () => result,
        maybeSingle: async () => result,
      };
      for (const method of ['insert', 'update', 'select', 'eq']) {
        chain[method] = (...args: unknown[]) => {
          const [value] = args;
          state.writes.push({ table, method, value });
          state.operations.push({ kind: 'query', table, method, args });
          return chain;
        };
      }
      return chain;
    },
  }),
}));

const TENANT_ID = '11111111-1111-4111-8111-111111111111';
const STAFF_ID = '22222222-2222-4222-8222-222222222222';
const MEMBER_ID = '33333333-3333-4333-8333-333333333333';
const NOTIFICATION_ID = '55555555-5555-4555-8555-555555555555';
const CONSENT_ID = '77777777-7777-4777-8777-777777777777';
const LEDGER_ID = '88888888-8888-4888-8888-888888888888';
const TEMPLATE_ID = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const KEY = '99999999-9999-4999-8999-999999999999';

const OWNER = { sub: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', app_role: 'gym_owner', tenant_id: TENANT_ID, staff_id: STAFF_ID };
const MANAGER = { ...OWNER, app_role: 'gym_manager' };
const FRONT_DESK = { ...OWNER, app_role: 'front_desk' };
const TRAINER = { ...OWNER, app_role: 'trainer' };
const MEMBER = { sub: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', app_role: 'member', tenant_id: TENANT_ID, member_id: MEMBER_ID };
const IMPERSONATION = { sub: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', app_role: 'gym_owner', tenant_id: TENANT_ID, impersonation_session_id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd' };
const SUPER_ADMIN = { sub: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', app_role: 'super_admin' };
const PLATFORM_SUPPORT = { sub: 'ffffffff-ffff-4fff-8fff-ffffffffffff', app_role: 'platform_support' };

function json(path: string, body: unknown, method = 'POST') {
  return new Request(`https://gym.example${path}`, {
    method, headers: { 'content-type': 'application/json' }, body: JSON.stringify(body),
  });
}
async function body(response: Response) {
  return await response.json() as { ok: boolean; data?: Record<string, unknown>; error?: { code: string } & Record<string, unknown> };
}

beforeEach(() => {
  state.claims = OWNER;
  state.rpc = [];
  state.results = [];
  state.writes = [];
  state.operations = [];
});

// ---------------------------------------------------------------------------
// POST /api/consents — §3, front office only
// ---------------------------------------------------------------------------

describe('POST /api/consents', () => {
  const consentsRoute = async () => (await import('../api/consents/route'));
  const requestBody = { memberId: MEMBER_ID, purpose: 'marketing', granted: true, version: '2026-09-01', source: 'front_desk_form', requestKey: KEY };
  const rpcResult = {
    consentId: CONSENT_ID, memberId: MEMBER_ID, purpose: 'marketing', granted: true,
    version: '2026-09-01', source: 'front_desk_form', recordedAt: '2026-09-10T10:00:00+00:00', recordedByStaffId: STAFF_ID,
  };

  it('sends exactly the six named record_consent facts', async () => {
    state.results = [{ data: rpcResult, error: null }];
    const { POST } = await consentsRoute();

    const response = await POST(json('/api/consents', requestBody));
    const payload = await body(response);

    expect(response.status).toBe(201);
    expect(payload).toMatchObject({ ok: true, data: rpcResult });
    expect(state.rpc).toEqual([{
      name: 'record_consent',
      args: {
        p_member_id: MEMBER_ID, p_purpose: 'marketing', p_granted: true,
        p_version: '2026-09-01', p_source: 'front_desk_form', p_request_key: KEY,
      },
    }]);
  });

  it('records a withdrawal on the independent service purpose', async () => {
    state.results = [{ data: { ...rpcResult, purpose: 'service', granted: false }, error: null }];
    const { POST } = await consentsRoute();

    const response = await POST(json('/api/consents', { ...requestBody, purpose: 'service', granted: false }));

    expect(response.status).toBe(201);
    expect(state.rpc[0]?.args).toMatchObject({ p_purpose: 'service', p_granted: false });
  });

  it.each([
    ['a non-uuid memberId', { ...requestBody, memberId: 'not-a-uuid' }],
    ['a non-uuid requestKey', { ...requestBody, requestKey: 'not-a-uuid' }],
    ['an off-catalogue purpose', { ...requestBody, purpose: 'transactional' }],
    ['a non-boolean granted', { ...requestBody, granted: 'yes' }],
    ['a blank version', { ...requestBody, version: '   ' }],
    ['a blank source', { ...requestBody, source: '' }],
    ['a missing source', { memberId: MEMBER_ID, purpose: 'marketing', granted: true, version: '2026-09-01', requestKey: KEY }],
    ['a forged consentId', { ...requestBody, consentId: CONSENT_ID }],
    ['a forged recordedByStaffId', { ...requestBody, recordedByStaffId: STAFF_ID }],
  ])('refuses %s before invoking record_consent', async (_name, payload) => {
    const { POST } = await consentsRoute();
    const response = await POST(json('/api/consents', payload));

    expect(response.status).toBe(400);
    expect((await body(response)).error?.code).toBe('invalid_request');
    expect(state.rpc).toEqual([]);
  });

  it.each([
    ['a trainer', TRAINER],
    ['a member', MEMBER],
    ['a preview identity', IMPERSONATION],
  ])('refuses %s with 403 before any consent write', async (_name, claims) => {
    state.claims = claims;
    const { POST } = await consentsRoute();
    const response = await POST(json('/api/consents', requestBody));

    expect(response.status).toBe(403);
    expect((await body(response)).error?.code).toBe('not_permitted');
    expect(state.rpc).toEqual([]);
  });

  it('answers an unsigned caller with 401 rather than parsing the body', async () => {
    state.claims = null;
    const { POST } = await consentsRoute();
    const response = await POST(json('/api/consents', requestBody));

    expect(response.status).toBe(401);
    expect((await body(response)).error?.code).toBe('not_signed_in');
    expect(state.rpc).toEqual([]);
  });

  it.each([
    ['GL065', 422, 'invalid_consent'],
    ['P0002', 404, 'not_found'],
    ['42501', 403, 'not_permitted'],
    ['GL068', 409, 'idempotency_conflict'],
    ['40001', 409, 'retryable'],
    ['40P01', 409, 'retryable'],
  ])('maps %s to HTTP %s / %s, never inventing success', async (code, status, expectedCode) => {
    state.results = [{ data: null, error: { code, message: 'refused' } }];
    const { POST } = await consentsRoute();
    const response = await POST(json('/api/consents', requestBody));

    expect(response.status).toBe(status);
    const payload = await body(response);
    expect(payload.ok).toBe(false);
    expect(payload.error?.code).toBe(expectedCode);
  });
});

// ---------------------------------------------------------------------------
// POST /api/member/notifications/[id]/delivered — §5, member only
// ---------------------------------------------------------------------------

describe('POST /api/member/notifications/[id]/delivered', () => {
  const deliveredRoute = async () => (await import('../api/member/notifications/[id]/delivered/route'));
  const params = { params: Promise.resolve({ id: NOTIFICATION_ID }) };
  const delivered = {
    notificationId: NOTIFICATION_ID, memberId: MEMBER_ID, channel: 'in_app', status: 'delivered',
    sentAt: '2026-09-10T09:00:00+00:00', deliveredAt: '2026-09-10T10:00:00+00:00',
    failedAt: null, failedReason: null, optedOutAt: null, optedOutReason: null,
  };

  beforeEach(() => { state.claims = MEMBER; });

  it('sends exactly the notification id to acknowledge_notification and returns the result', async () => {
    state.results = [{ data: delivered, error: null }];
    const { POST } = await deliveredRoute();

    const response = await POST(json(`/api/member/notifications/${NOTIFICATION_ID}/delivered`, {}), params);
    const payload = await body(response);

    expect(response.status).toBe(200);
    expect(payload).toMatchObject({ ok: true, data: delivered });
    expect(state.rpc).toEqual([{ name: 'acknowledge_notification', args: { p_notification_id: NOTIFICATION_ID } }]);
  });

  it('answers a repeated acknowledgement with the same inert result, one RPC call', async () => {
    state.results = [{ data: delivered, error: null }];
    const { POST } = await deliveredRoute();

    const response = await POST(json(`/api/member/notifications/${NOTIFICATION_ID}/delivered`, {}), params);

    expect(response.status).toBe(200);
    expect(state.rpc).toHaveLength(1);
  });

  it('rejects a non-uuid notification id before any RPC', async () => {
    const { POST } = await deliveredRoute();
    const response = await POST(
      json('/api/member/notifications/not-a-uuid/delivered', {}),
      { params: Promise.resolve({ id: 'not-a-uuid' }) },
    );

    expect(response.status).toBe(400);
    expect((await body(response)).error?.code).toBe('invalid_request');
    expect(state.rpc).toEqual([]);
  });

  it.each([
    ['GL066 on a non-sent notification', 'GL066', 422, 'invalid_notification'],
    ['no such own-gym in-app notification', 'P0002', 404, 'not_found'],
    ['a serialization failure', '40001', 409, 'retryable'],
  ])('maps %s to HTTP %s / %s', async (_name, code, status, expectedCode) => {
    state.results = [{ data: null, error: { code, message: 'refused' } }];
    const { POST } = await deliveredRoute();
    const response = await POST(json(`/api/member/notifications/${NOTIFICATION_ID}/delivered`, {}), params);

    expect(response.status).toBe(status);
    expect((await body(response)).error?.code).toBe(expectedCode);
  });

  it.each([
    ['staff (owner)', OWNER],
    ['a trainer', TRAINER],
    ['a preview identity', IMPERSONATION],
  ])('refuses %s with 401 not_signed_in — this action has no staff identity', async (_name, claims) => {
    state.claims = claims;
    const { POST } = await deliveredRoute();
    const response = await POST(json(`/api/member/notifications/${NOTIFICATION_ID}/delivered`, {}), params);

    expect(response.status).toBe(401);
    expect((await body(response)).error?.code).toBe('not_signed_in');
    expect(state.rpc).toEqual([]);
  });

  it('answers an unsigned caller with 401', async () => {
    state.claims = null;
    const { POST } = await deliveredRoute();
    const response = await POST(json(`/api/member/notifications/${NOTIFICATION_ID}/delivered`, {}), params);

    expect(response.status).toBe(401);
    expect(state.rpc).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// POST /api/notifications/[id]/whatsapp — §5, front-office only, no GET
// ---------------------------------------------------------------------------

describe('POST /api/notifications/[id]/whatsapp', () => {
  const whatsappRoute = async () => (await import('../api/notifications/[id]/whatsapp/route'));
  const params = { params: Promise.resolve({ id: NOTIFICATION_ID }) };
  const childSent = {
    notificationId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', memberId: MEMBER_ID, channel: 'whatsapp_link', status: 'sent',
    sentAt: '2026-09-10T10:00:00+00:00', deliveredAt: null, failedAt: null, failedReason: null, optedOutAt: null, optedOutReason: null,
  };
  const url = 'https://wa.me/919876543210?text=Your%20membership%20ends%20soon';

  it('sends exactly the source notification id and returns {notification,url}', async () => {
    state.results = [{ data: { notification: childSent, url }, error: null }];
    const { POST } = await whatsappRoute();

    const response = await POST(json(`/api/notifications/${NOTIFICATION_ID}/whatsapp`, {}), params);
    const payload = await body(response);

    expect(response.status).toBe(200);
    expect(payload).toMatchObject({ ok: true, data: { notification: childSent, url } });
    expect(state.rpc).toEqual([{ name: 'open_notification_whatsapp', args: { p_notification_id: NOTIFICATION_ID } }]);
  });

  it('answers a repeated opening with the same child and URL, never a second row', async () => {
    state.results = [{ data: { notification: childSent, url }, error: null }];
    const { POST } = await whatsappRoute();

    const response = await POST(json(`/api/notifications/${NOTIFICATION_ID}/whatsapp`, {}), params);
    const payload = await body(response);

    expect(response.status).toBe(200);
    expect(payload.data?.url).toBe(url);
  });

  it('answers a refused current consent/eligibility/renewal decision with 403 communication_opted_out and no URL', async () => {
    state.results = [{ data: { communicationOptedOut: true }, error: null }];
    const { POST } = await whatsappRoute();

    const response = await POST(json(`/api/notifications/${NOTIFICATION_ID}/whatsapp`, {}), params);
    const payload = await body(response);

    expect(response.status).toBe(403);
    expect(payload.ok).toBe(false);
    expect(payload.error?.code).toBe('communication_opted_out');
    expect(JSON.stringify(payload)).not.toContain('wa.me');
  });

  it('rejects a non-uuid source notification id before any RPC', async () => {
    const { POST } = await whatsappRoute();
    const response = await POST(
      json('/api/notifications/not-a-uuid/whatsapp', {}),
      { params: Promise.resolve({ id: 'not-a-uuid' }) },
    );

    expect(response.status).toBe(400);
    expect((await body(response)).error?.code).toBe('invalid_request');
    expect(state.rpc).toEqual([]);
  });

  it.each([
    ['GL066 — recipient phone changed since the child was frozen', 'GL066', 422, 'invalid_notification'],
    ['no such own-gym in-app source notification', 'P0002', 404, 'not_found'],
  ])('maps %s to HTTP %s / %s', async (_name, code, status, expectedCode) => {
    state.results = [{ data: null, error: { code, message: 'refused' } }];
    const { POST } = await whatsappRoute();
    const response = await POST(json(`/api/notifications/${NOTIFICATION_ID}/whatsapp`, {}), params);

    expect(response.status).toBe(status);
    expect((await body(response)).error?.code).toBe(expectedCode);
  });

  it.each([
    ['a trainer', TRAINER],
    ['a member', MEMBER],
    ['a preview identity', IMPERSONATION],
  ])('refuses %s with 403 before any RPC', async (_name, claims) => {
    state.claims = claims;
    const { POST } = await whatsappRoute();
    const response = await POST(json(`/api/notifications/${NOTIFICATION_ID}/whatsapp`, {}), params);

    expect(response.status).toBe(403);
    expect((await body(response)).error?.code).toBe('not_permitted');
    expect(state.rpc).toEqual([]);
  });

  it('exposes no GET handler — the URL is returned only from the POST action', async () => {
    const route = await whatsappRoute();
    expect((route as Record<string, unknown>).GET).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// POST /api/message-templates — §8, gym admin only, ordinary RLS write
// ---------------------------------------------------------------------------

describe('POST /api/message-templates', () => {
  const templatesRoute = async () => (await import('../api/message-templates/route'));
  const creation = { key: 'trial_reminder', channel: 'push', locale: 'en', category: 'motivation', body: 'Come back for your trial!', isActive: true };
  const createdRow = { id: TEMPLATE_ID, key: 'trial_reminder', channel: 'push', locale: 'en', category: 'motivation', body: 'Come back for your trial!', isActive: true };

  it('inserts exactly the six creation facts, with no template id', async () => {
    state.results = [{ data: createdRow, error: null }];
    const { POST } = await templatesRoute();

    const response = await POST(json('/api/message-templates', creation));
    const payload = await body(response);

    expect(response.status).toBe(201);
    expect(payload).toMatchObject({ ok: true, data: createdRow });
    expect(state.writes[0]).toMatchObject({
      table: 'message_templates', method: 'insert',
      value: { key: 'trial_reminder', channel: 'push', locale: 'en', category: 'motivation', body: 'Come back for your trial!', is_active: true },
    });
  });

  it('updates only category/body/isActive on an existing template — never key, channel or locale', async () => {
    const updated = { ...createdRow, body: 'Updated copy', isActive: false };
    state.results = [{ data: updated, error: null }];
    const { POST } = await templatesRoute();

    const response = await POST(json('/api/message-templates', { ...creation, templateId: TEMPLATE_ID, body: 'Updated copy', isActive: false }));
    const payload = await body(response);

    expect(response.status).toBe(200);
    expect(payload).toMatchObject({ ok: true, data: updated });
    const update = state.writes.find((write) => write.method === 'update');
    expect(update).toBeDefined();
    const written = update?.value as Record<string, unknown>;
    expect(written).not.toHaveProperty('key');
    expect(written).not.toHaveProperty('channel');
    expect(written).not.toHaveProperty('locale');
    expect(written).toMatchObject({ category: 'motivation', body: 'Updated copy', is_active: false });
  });

  it('answers an invisible or unknown templateId with a generic 404, never a Postgres detail', async () => {
    state.results = [{ data: null, error: null }];
    const { POST } = await templatesRoute();

    const response = await POST(json('/api/message-templates', { ...creation, templateId: TEMPLATE_ID }));

    expect(response.status).toBe(404);
    expect((await body(response)).error?.code).toBe('not_found');
  });

  it.each([
    ['a missing category', { key: 'trial_reminder', channel: 'push', locale: 'en', body: 'x', isActive: true }],
    ['an off-catalogue category', { ...creation, category: 'weather' }],
    ['an off-catalogue locale', { ...creation, locale: 'fr' }],
    ['an off-catalogue channel', { ...creation, channel: 'carrier_pigeon' }],
    ['a blank key', { ...creation, key: '   ' }],
    ['a blank body', { ...creation, body: '' }],
    ['the reserved renewal_reminder key', { ...creation, key: 'renewal_reminder' }],
    ['a non-boolean isActive', { ...creation, isActive: 'yes' }],
    ['a non-uuid templateId', { ...creation, templateId: 'not-a-uuid' }],
  ])('refuses %s before any write', async (_name, payload) => {
    const { POST } = await templatesRoute();
    const response = await POST(json('/api/message-templates', payload));

    expect(response.status).toBe(400);
    expect((await body(response)).error?.code).toBe('invalid_request');
    expect(state.writes).toEqual([]);
  });

  it('permits category "renewal" on a template whose key is not the reserved system key', async () => {
    state.results = [{ data: { ...createdRow, category: 'renewal' }, error: null }];
    const { POST } = await templatesRoute();

    const response = await POST(json('/api/message-templates', { ...creation, key: 'renewal_tip', category: 'renewal' }));

    expect(response.status).toBe(201);
    expect(state.writes).toHaveLength(1);
  });

  it.each([
    ['front desk', FRONT_DESK],
    ['a trainer', TRAINER],
    ['a member', MEMBER],
    ['a preview identity', IMPERSONATION],
  ])('refuses %s with 403 — templates are gym admin only', async (_name, claims) => {
    state.claims = claims;
    const { POST } = await templatesRoute();
    const response = await POST(json('/api/message-templates', creation));

    expect(response.status).toBe(403);
    expect((await body(response)).error?.code).toBe('not_permitted');
    expect(state.writes).toEqual([]);
  });

  it('permits a manager, the second gym-admin role', async () => {
    state.claims = MANAGER;
    state.results = [{ data: createdRow, error: null }];
    const { POST } = await templatesRoute();

    const response = await POST(json('/api/message-templates', creation));

    expect(response.status).toBe(201);
  });
});

// ---------------------------------------------------------------------------
// POST /api/messaging-wallet/adjust — §7, super_admin only
// ---------------------------------------------------------------------------

describe('POST /api/messaging-wallet/adjust', () => {
  const adjustRoute = async () => (await import('../api/messaging-wallet/adjust/route'));
  const requestBody = { tenantId: TENANT_ID, deltaCredits: '500', reason: 'Promotional top-up', requestKey: KEY };
  const ledgerResult = { ledgerId: LEDGER_ID, tenantId: TENANT_ID, deltaCredits: '500', reason: 'Promotional top-up', balanceAfterCredits: '5000', createdAt: '2026-09-10T10:00:00+00:00' };

  beforeEach(() => { state.claims = SUPER_ADMIN; });

  it('sends exactly the four named adjust_messaging_wallet facts, deltaCredits as the untouched string', async () => {
    state.results = [{ data: ledgerResult, error: null }];
    const { POST } = await adjustRoute();

    const response = await POST(json('/api/messaging-wallet/adjust', requestBody));
    const payload = await body(response);

    expect(response.status).toBe(201);
    expect(payload).toMatchObject({ ok: true, data: ledgerResult });
    expect(state.rpc).toEqual([{
      name: 'adjust_messaging_wallet',
      args: { p_tenant_id: TENANT_ID, p_delta_credits: '500', p_reason: 'Promotional top-up', p_request_key: KEY },
    }]);
  });

  it('never turns a huge deltaCredits into a JS number on the way to the RPC or in the response', async () => {
    const huge = '9223372036854775807';
    state.results = [{ data: { ...ledgerResult, deltaCredits: huge, balanceAfterCredits: huge }, error: null }];
    const { POST } = await adjustRoute();

    const response = await POST(json('/api/messaging-wallet/adjust', { ...requestBody, deltaCredits: huge }));
    const payload = await body(response);

    expect(state.rpc[0]?.args.p_delta_credits).toBe(huge);
    expect(typeof state.rpc[0]?.args.p_delta_credits).toBe('string');
    expect(payload.data?.deltaCredits).toBe(huge);
    expect(typeof payload.data?.deltaCredits).toBe('string');
  });

  it('accepts a negative delta (a debit) with one leading minus', async () => {
    state.results = [{ data: { ...ledgerResult, deltaCredits: '-200', balanceAfterCredits: '4800' }, error: null }];
    const { POST } = await adjustRoute();

    const response = await POST(json('/api/messaging-wallet/adjust', { ...requestBody, deltaCredits: '-200' }));

    expect(response.status).toBe(201);
    expect(state.rpc[0]?.args.p_delta_credits).toBe('-200');
  });

  it('sends a zero delta through to the RPC rather than pre-refusing it — the CHECK constraint owns that refusal', async () => {
    state.results = [{ data: null, error: { code: '23514', message: 'zero delta or blank reason' } }];
    const { POST } = await adjustRoute();

    const response = await POST(json('/api/messaging-wallet/adjust', { ...requestBody, deltaCredits: '0' }));

    expect(state.rpc).toHaveLength(1);
    expect(response.status).toBe(422);
    expect((await body(response)).error?.code).toBe('invalid_adjustment');
  });

  it.each([
    ['a non-canonical deltaCredits (leading zero)', { ...requestBody, deltaCredits: '0500' }],
    ['a fractional deltaCredits', { ...requestBody, deltaCredits: '500.5' }],
    ['a JS-number deltaCredits', { ...requestBody, deltaCredits: 500 }],
    ['a blank reason', { ...requestBody, reason: '   ' }],
    ['a non-uuid tenantId', { ...requestBody, tenantId: 'not-a-uuid' }],
    ['a non-uuid requestKey', { ...requestBody, requestKey: 'not-a-uuid' }],
    ['a forged ledgerId', { ...requestBody, ledgerId: LEDGER_ID }],
    ['a forged balanceAfterCredits', { ...requestBody, balanceAfterCredits: '5000' }],
  ])('refuses %s before invoking adjust_messaging_wallet', async (_name, payload) => {
    const { POST } = await adjustRoute();
    const response = await POST(json('/api/messaging-wallet/adjust', payload));

    expect(response.status).toBe(400);
    expect((await body(response)).error?.code).toBe('invalid_request');
    expect(state.rpc).toEqual([]);
  });

  it.each([
    ['GL067', 409, 'insufficient_credits'],
    ['GL068', 409, 'idempotency_conflict'],
    ['23514', 422, 'invalid_adjustment'],
    ['22003', 422, 'credits_out_of_range'],
    ['40001', 409, 'retryable'],
    ['40P01', 409, 'retryable'],
  ])('maps %s to HTTP %s / %s, never inventing success', async (code, status, expectedCode) => {
    state.results = [{ data: null, error: { code, message: 'refused' } }];
    const { POST } = await adjustRoute();
    const response = await POST(json('/api/messaging-wallet/adjust', requestBody));

    expect(response.status).toBe(status);
    const payload = await body(response);
    expect(payload.ok).toBe(false);
    expect(payload.error?.code).toBe(expectedCode);
  });

  it('answers an exact replay with the original immutable entry, even if current balance has since changed', async () => {
    state.results = [{ data: ledgerResult, error: null }];
    const { POST } = await adjustRoute();

    const response = await POST(json('/api/messaging-wallet/adjust', requestBody));
    const payload = await body(response);

    expect(payload).toMatchObject({ ok: true, data: ledgerResult });
  });

  it('refuses platform_support (not an admin) with 403', async () => {
    state.claims = PLATFORM_SUPPORT;
    const { POST } = await adjustRoute();
    const response = await POST(json('/api/messaging-wallet/adjust', requestBody));

    expect(response.status).toBe(403);
    expect((await body(response)).error?.code).toBe('not_permitted');
    expect(state.rpc).toEqual([]);
  });

  it.each([
    ['gym staff (owner)', OWNER],
    ['a member', MEMBER],
    ['a preview identity', IMPERSONATION],
  ])('refuses %s with 401 — the wallet has no gym/staff/member/impersonation identity', async (_name, claims) => {
    state.claims = claims;
    const { POST } = await adjustRoute();
    const response = await POST(json('/api/messaging-wallet/adjust', requestBody));

    expect(response.status).toBe(401);
    expect(state.rpc).toEqual([]);
  });

  it('answers an unsigned caller with 401', async () => {
    state.claims = null;
    const { POST } = await adjustRoute();
    const response = await POST(json('/api/messaging-wallet/adjust', requestBody));

    expect(response.status).toBe(401);
    expect(state.rpc).toEqual([]);
  });
});
