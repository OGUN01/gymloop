import { beforeEach, describe, expect, it, vi } from 'vitest';

// PAY HTTP boundary against the frozen route list; SQL tests own ledger order.
// Routes do not exist yet — the failing import is the expected RED.

const state = vi.hoisted(() => ({ claims: null as Record<string, unknown> | null, results: [] as Array<{ data: unknown; error: unknown }>, calls: [] as Array<{ name: string; args: unknown }>, events: [] as string[] }));
const id = '72000000-0000-4000-8000-000000000001';
const client = () => ({
  auth: { getClaims: async () => { state.events.push('verified-session'); return { data: { claims: state.claims }, error: null }; }, getUser: async () => ({ data: { user: state.claims ? { id: state.claims.sub } : null }, error: null }) },
  rpc: async (name: string, args: unknown) => { state.calls.push({ name, args }); return state.results.shift() ?? { data: null, error: null }; },
  from: () => { const query: Record<string, unknown> = {}; for (const method of ['select', 'insert', 'update', 'eq', 'order']) query[method] = () => query; const result = async () => state.results.shift() ?? { data: null, error: null }; query.single = result; query.maybeSingle = result; query.then = (resolve: (value: unknown) => unknown) => result().then(resolve); return query; },
});
vi.mock('../../lib/supabase/server', () => ({ createServerSupabase: async () => client() }));
vi.mock('../../lib/supabase/request', () => ({ createRequestSupabase: async () => ({ supabase: client(), bearer: 'verified-caller-token' }) }));
const member = { role: 'authenticated', sub: id, app_role: 'member', tenant_id: id, member_id: id };
const owner = { role: 'authenticated', sub: id, app_role: 'gym_owner', tenant_id: id, staff_id: id };
const trainer = { role: 'authenticated', sub: id, app_role: 'trainer', tenant_id: id, staff_id: id };

const memberRoutes = [
  { path: '../api/member/purchase-requests/route', method: 'POST', audience: member, body: { requestKey: id, kind: 'shop', targetId: id, quantity: 1, expectedRevision: id } },
  { path: '../api/member/purchase-requests/[id]/cancel/route', method: 'POST', audience: member, body: { commandKey: id } },
  { path: '../api/member/purchase-requests/[id]/reconfirm/route', method: 'POST', audience: member, body: { expectedRevision: id, commandKey: id } },
  { path: '../api/member/purchase-requests/[id]/proof-upload-url/route', method: 'POST', audience: member, body: {} },
  { path: '../api/member/purchase-requests/[id]/proof-confirm/route', method: 'POST', audience: member, body: { assetId: id, expectedRevision: id, commandKey: id } },
] as const;
const deskRoutes = [
  { path: '../api/purchase-requests/[id]/accept/route', method: 'POST', audience: owner, body: { expectedRevision: id, commandKey: id } },
  { path: '../api/purchase-requests/[id]/reject/route', method: 'POST', audience: owner, body: { expectedRevision: id, commandKey: id, reason: 'Stock reserved for another member' } },
  { path: '../api/purchase-requests/[id]/reject-proof/route', method: 'POST', audience: owner, body: { assetId: id, expectedRevision: id, reason: 'Picture unclear, re-upload', commandKey: id } },
  { path: '../api/purchase-requests/[id]/record/route', method: 'POST', audience: owner, body: { expectedRevision: id, commandKey: id, actualAmount: '199900', currency: 'INR', method: 'upi' } },
  { path: '../api/purchase-requests/[id]/proof-url/route', method: 'POST', audience: owner, body: {} },
] as const;
const routes = [...memberRoutes, ...deskRoutes];
function request(payload: unknown, method: string, malformed = false) {
  const value = new Request('https://gym.example/api', { method, headers: { authorization: 'Bearer verified-caller-token', 'content-type': 'application/json' }, body: malformed ? '{' : JSON.stringify(payload) });
  const parse = value.json.bind(value); vi.spyOn(value, 'json').mockImplementation(async () => { state.events.push('body'); return parse(); }); return value;
}
const context = { params: Promise.resolve({ id, requestId: id }) };
async function invoke(route: { path: string; method: string }, req: Request) { const module = await import(route.path); return module[route.method](req, context) as Promise<Response>; }

beforeEach(() => { state.claims = member; state.calls = []; state.results = []; state.events = []; });

describe('PAY route session/body order, shape and safe failures', () => {
  it.each(routes)('$path identifies caller before reading malformed JSON', async route => {
    state.claims = null;
    const response = await invoke(route, request({}, route.method, true));
    expect([401, 403]).toContain(response.status); expect(state.events).not.toContain('body'); expect(state.calls).toEqual([]); expect(response.headers.get('cache-control')).toBe('no-store');
  });
  it.each(routes)('$path rejects extra fields without command execution', async route => {
    state.claims = route.audience;
    const response = await invoke(route, request({ ...route.body, tenantId: id }, route.method));
    expect(response.status).toBe(400); expect((await response.json()).error.code).toBe('invalid_request'); expect(state.events.indexOf('verified-session')).toBeLessThan(state.events.indexOf('body')); expect(response.headers.get('cache-control')).toBe('no-store');
  });
  it('trainer is not permitted anywhere on the desk boundary', async () => {
    for (const route of deskRoutes) {
      state.claims = trainer; state.results = [];
      const response = await invoke(route, request(route.body, route.method));
      expect(response.status).toBe(403); expect((await response.json()).error.code).toBe('not_permitted'); expect(state.calls).toEqual([]);
    }
  });
  it('record forwards actual amount, currency and method as decimal text without inventing a receipt', async () => {
    state.claims = owner;
    state.results = [{ data: [{ request_id: id, status: 'recorded', replayed: false, receipt_id: 'RC-0011' }], error: null }];
    const record = deskRoutes.find(route => route.path.includes('/record'))!;
    const response = await invoke(record, request(record.body, record.method));
    expect(response.status).toBe(200); expect(await response.json()).toEqual({ ok: true, data: { requestId: id, status: 'recorded', replayed: false, receiptId: 'RC-0011' } });
    expect(state.calls).toEqual([{ name: 'record_purchase_request', args: { p_request_id: id, p_expected_revision: id, p_command_key: id, p_actual_amount: '199900', p_currency: 'INR', p_payment_method: 'upi' } }]);
  });
  it('exact replay is answered read-only with the replayed flag', async () => {
    state.claims = owner;
    state.results = [{ data: [{ request_id: id, status: 'recorded', replayed: true, receipt_id: 'RC-0011' }], error: null }];
    const record = deskRoutes.find(route => route.path.includes('/record'))!;
    const response = await invoke(record, request(record.body, record.method));
    expect(response.status).toBe(200); expect((await response.json()).data.replayed).toBe(true);
  });
  it.each([
    ['GL068', '', 409, 'idempotency_conflict'],
    ['GL123', '', 409, ''],
    ['GL124', '', 409, ''],
    ['GL125', '', 409, ''],
    ['42501', '', 403, 'not_permitted'],
    ['P0002', '', 404, 'request_unavailable'],
    ['23514', '', 422, ''],
    ['XX000', '', 500, ''],
  ])('maps ledger refusal %s safely', async (code, _details, status, pinnedCode) => {
    state.claims = owner;
    const record = deskRoutes.find(route => route.path.includes('/record'))!;
    state.results = [{ data: null, error: { code, message: 'RAW_PRIVATE_LEDGER' } }];
    const response = await invoke(record, request(record.body, record.method));
    expect(response.status).toBe(status); expect(response.headers.get('cache-control')).toBe('no-store');
    const payload = await response.json();
    if (pinnedCode) expect(payload.error.code).toBe(pinnedCode);
    expect(JSON.stringify(payload)).not.toContain('RAW_PRIVATE_LEDGER');
  });
  it('member create targets only the frozen RPC name and never a second inventory', async () => {
    state.claims = member;
    state.results = [{ data: [{ request_id: id, status: 'requested' }], error: null }];
    const [create] = memberRoutes;
    const response = await invoke(create, request(create.body, create.method));
    expect(response.status).toBe(200);
    expect(state.calls).toEqual([{ name: 'create_purchase_request', args: { p_request_key: id, p_kind: 'shop', p_target_id: id, p_quantity: 1, p_expected_revision: id } }]);
  });
  it('proof-url returns only the signed URL and its expiry, never storage metadata', async () => {
    state.claims = member;
    const proofUrl = { path: '../api/purchase-requests/[id]/proof-url/route', method: 'POST' };
    state.results = [{ data: [{ request_id: id, url: 'https://r2.test/signed', expires_at: '2026-10-02T05:45:00Z' }], error: null }];
    const response = await invoke(proofUrl, request({}, 'POST'));
    expect(response.status).toBe(200);
    expect(response.headers.get('cache-control')).toBe('no-store');
    const payload = await response.json();
    expect(payload.data).toEqual({ url: 'https://r2.test/signed', expiresAt: '2026-10-02T05:45:00Z' });
  });
});
