import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

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
  { path: '../api/purchase-requests/[id]/record/route', method: 'POST', audience: owner, body: { expectedRevision: id, commandKey: id, actualAmount: '199900', currency: 'INR', method: 'upi', viewedAssetId: id, viewedProofRevision: id } },
  { path: '../api/purchase-requests/[id]/proof-url/route', method: 'POST', audience: owner, body: {} },
] as const;
const routes = [...memberRoutes, ...deskRoutes];
function request(payload: unknown, method: string, malformed = false) {
  const value = new Request('https://gym.example/api', { method, headers: { authorization: 'Bearer verified-caller-token', 'content-type': 'application/json' }, body: malformed ? '{' : JSON.stringify(payload) });
  const parse = value.json.bind(value); vi.spyOn(value, 'json').mockImplementation(async () => { state.events.push('body'); return parse(); }); return value;
}
const context = { params: Promise.resolve({ id, requestId: id }) };
async function invoke(route: { path: string; method: string }, req: Request) { const module = await import(route.path); return module[route.method](req, context) as Promise<Response>; }

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(new Date('2026-10-02T05:44:30Z'));
  // The proof-url capability minting reads the registered env contract; the
  // capability must stay in the existing trusted runtime (frozen decision 7).
  vi.stubEnv('SUPABASE_PROJECT_REF', 'test-project-ref');
  vi.stubEnv('R2_ACCESS_KEY_ID', 'test-r2-access-key');
  vi.stubEnv('R2_SECRET_ACCESS_KEY', 'test-r2-secret');
  vi.stubEnv('R2_BUCKET', 'test-bucket');
  vi.stubEnv('R2_ENDPOINT', 'https://account.r2.cloudflarestorage.com');
  vi.stubEnv('SUPABASE_SERVICE_ROLE_KEY', 'test-service-role-key');
  vi.stubEnv('SUPABASE_DB_PASSWORD', 'test-db-password');
  vi.stubEnv('SUPABASE_ACCESS_TOKEN', 'test-access-token');
  vi.stubEnv('CLOUDFLARE_ACCOUNT_ID', 'test-account-id');
  state.claims = member; state.calls = []; state.results = []; state.events = [];
});
afterEach(() => { vi.useRealTimers(); vi.unstubAllEnvs(); });

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
    expect(state.calls).toEqual([{ name: 'record_purchase_request', args: { p_request_id: id, p_expected_revision: id, p_command_key: id, p_actual_amount: '199900', p_currency: 'INR', p_payment_method: 'upi', p_viewed_asset: id, p_viewed_proof_revision: id } }]);
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
  it('proof-url returns only the bounded proof-asset URL and its expiry, never storage metadata', async () => {
    state.claims = member;
    const proofUrl = { path: '../api/purchase-requests/[id]/proof-url/route', method: 'POST' };
    state.results = [{ data: { requestId: id, proofId: id, assetId: id, url: `/api/purchase-requests/${id}/proof-asset`, expiresAt: '2026-10-02T05:45:00Z' }, error: null }];
    const response = await invoke(proofUrl, request({}, 'POST'));
    expect(response.status).toBe(200);
    expect(response.headers.get('cache-control')).toBe('no-store');
    const payload = await response.json();
    expect(payload.data.expiresAt).toBe('2026-10-02T05:45:00Z');
    expect(payload.data.url.startsWith(`/api/purchase-requests/${id}/proof-asset?capability=`)).toBe(true);
  });
});

const readRoutes = [
  { path: '../api/member/purchase-requests/[id]/route', method: 'GET', audience: member },
  { path: '../api/purchase-requests/route', method: 'GET', audience: owner },
] as const;

describe('PAY complete actor and safe-read boundaries (BUY-001/009/019)', () => {
  it.each([...routes, ...readRoutes])('$path returns 401 for an absent session before body or RPC', async route => {
    state.claims = null;
    const req = route.method === 'GET' ? new Request('https://gym.example/api') : request({}, route.method, true);
    const response = await invoke(route, req);
    expect(response.status).toBe(401);
    expect(state.calls).toEqual([]);
    expect(state.events).not.toContain('body');
    expect(response.headers.get('cache-control')).toBe('no-store');
  });
  it.each([...memberRoutes, readRoutes[0]])('$path refuses a real staff actor before member RPC/body', async route => {
    state.claims = owner;
    const req = route.method === 'GET' ? new Request('https://gym.example/api') : request({}, route.method, true);
    const response = await invoke(route, req);
    expect(response.status).toBe(403);
    expect((await response.json()).error.code).toBe('not_permitted');
    expect(state.calls).toEqual([]);
    expect(state.events).not.toContain('body');
  });
  it.each([...deskRoutes.filter(route => !route.path.includes('/proof-url')), readRoutes[1]])('$path refuses a member actor before desk RPC/body', async route => {
    state.claims = member;
    const req = route.method === 'GET' ? new Request('https://gym.example/api') : request({}, route.method, true);
    const response = await invoke(route, req);
    expect(response.status).toBe(403);
    expect((await response.json()).error.code).toBe('not_permitted');
    expect(state.calls).toEqual([]);
    expect(state.events).not.toContain('body');
  });
  // Full raw read JSON follows the frozen public detail/snapshot declaration.
  // Unrecorded optional facts are omitted by the SQL projection.
  it.each(readRoutes)('$path invokes only its declared scoped read', async route => {
    state.claims = route.audience;
    state.results = [{ data: route === readRoutes[0] ? {
      requestId: id,
      requestKey: id,
      kind: 'shop',
      status: 'requested',
      targetId: id,
      quantity: 1,
      snapshot: {
        productId: id,
        productName: 'Gym training towel',
        kind: 'product',
        description: null,
        cancellationTerms: null,
        validityDays: null,
        gstRateBp: 0,
        unitPricePaise: '199900',
        pricePaise: '199900',
        totalPaise: '199900',
        currency: 'INR',
        quoteVersion: id,
      },
      quoteRevision: id,
      createdAt: '2026-10-02T05:00:00Z',
      expiresAt: '2026-10-03T05:00:00Z',
    } : { requests: [], nextAfter: null, nextAfterId: null }, error: null }];
    const response = await invoke(route, new Request('https://gym.example/api'));
    expect(response.status).toBe(200);
    expect(response.headers.get('cache-control')).toBe('no-store');
    expect(state.calls).toHaveLength(1);
    expect(state.calls[0]?.name).toBe(route === readRoutes[0] ? 'read_purchase_request' : 'read_purchase_requests');
    if (route === readRoutes[0]) expect(state.calls[0]?.args).toEqual({ p_request_id: id });
  });
  it('member detail refuses an invisible target without leaking its existence', async () => {
    state.results = [{ data: null, error: { code: 'P0002', message: 'PRIVATE_TARGET_EXISTS' } }];
    const response = await invoke(readRoutes[0], new Request('https://gym.example/api'));
    expect(response.status).toBe(404);
    const payload = await response.json();
    expect(payload.error.code).toBe('request_unavailable');
    expect(JSON.stringify(payload)).not.toContain('PRIVATE_TARGET_EXISTS');
  });
  it('proof-url accepts the frozen JSON object envelope and strips private metadata', async () => {
    state.results = [{ data: { requestId: id, proofId: id, assetId: id, url: `/api/purchase-requests/${id}/proof-asset`, expiresAt: '2026-10-02T05:45:00Z', object_key: 'PRIVATE_KEY', etag: 'PRIVATE_ETAG' }, error: null }];
    const response = await invoke(deskRoutes[4], request({}, 'POST'));
    expect(response.status).toBe(200);
    expect(response.headers.get('cache-control')).toBe('no-store');
    const envelope = await response.json();
    expect(envelope.ok).toBe(true);
    expect(envelope.data.expiresAt).toBe('2026-10-02T05:45:00Z');
    expect(envelope.data.url.startsWith(`/api/purchase-requests/${id}/proof-asset?capability=`)).toBe(true);
    const text = JSON.stringify(envelope);
    expect(text).not.toContain('PRIVATE_KEY');
    expect(text).not.toContain('PRIVATE_ETAG');
  });
  // Frozen PAY transport requires a live no-store GET with a TTL at most 60s.
  it.each([
    ['already expired', '2026-10-02T05:44:29Z'],
    ['expires exactly now', '2026-10-02T05:44:30Z'],
    ['exceeds sixty seconds', '2026-10-02T05:45:31Z'],
  ])('proof-url refuses an RPC URL that %s', async (_case, expiresAt) => {
    state.results = [{ data: { requestId: id, proofId: id, assetId: id, url: `/api/purchase-requests/${id}/proof-asset`, expiresAt }, error: null }];
    const response = await invoke(deskRoutes[4], request({}, 'POST'));
    expect(response.status).toBeGreaterThanOrEqual(400);
    expect(response.status).toBeLessThan(600);
    expect(response.headers.get('cache-control')).toBe('no-store');
    const payload = await response.json();
    expect(payload.ok).toBe(false);
    expect(payload.data).toBeUndefined();
    expect(typeof payload.error.message).toBe('string');
    expect(JSON.stringify(payload)).not.toContain('/proof-asset');
  });
});

describe('PAY record HTTP canonical money boundary (BUY-012)', () => {
  it.each(['9223372036854775808', '01', '+1', '1e3', '1.0', '0', 199900])('refuses amount %s before recording', async actualAmount => {
    state.claims = owner;
    const record = deskRoutes[3];
    const response = await invoke(record, request({ ...record.body, actualAmount }, 'POST'));
    expect(response.status).toBe(400);
    expect((await response.json()).error.code).toBe('invalid_request');
    expect(state.calls).toEqual([]);
  });
  it('forwards maximum signed-bigint paise without precision loss', async () => {
    state.claims = owner;
    state.results = [{ data: { request_id: id, status: 'recorded', replayed: false }, error: null }];
    const record = deskRoutes[3];
    const response = await invoke(record, request({ ...record.body, actualAmount: '9223372036854775807' }, 'POST'));
    expect(response.status).toBe(200);
    expect(state.calls[0]?.args).toMatchObject({ p_actual_amount: '9223372036854775807', p_currency: 'INR', p_payment_method: 'upi' });
  });
  it.each(['__proto__', 'constructor', 'toString'])('maps %s without raw refusal or prototype output', async code => {
    state.claims = owner;
    state.results = [{ data: null, error: { code, message: 'RAW_PRIVATE_LEDGER' } }];
    const record = deskRoutes[3];
    const response = await invoke(record, request(record.body, 'POST'));
    expect(response.status).toBe(500);
    const payload = await response.json();
    expect(typeof payload.error.message).toBe('string');
    expect(JSON.stringify(payload)).not.toContain('RAW_PRIVATE_LEDGER');
  });
});

describe('PAY real verifier authority cannot be substituted by trainer or preview', () => {
  it.each([
    trainer,
    { role: 'authenticated', sub: id, app_role: 'super_admin' },
    { role: 'authenticated', sub: id, app_role: 'gym_owner', tenant_id: id, impersonation_session_id: id },
  ])('denies non-verifier claims on every desk command/read before malformed body', async claims => {
    for (const route of [...deskRoutes, readRoutes[1]]) {
      state.claims = claims;
      state.calls = [];
      state.events = [];
      const req = route.method === 'GET' ? new Request('https://gym.example/api') : request({}, route.method, true);
      const response = await invoke(route, req);
      expect(response.status).toBe(403);
      expect((await response.json()).error.code).toBe('not_permitted');
      expect(state.calls).toEqual([]);
      expect(state.events).not.toContain('body');
    }
  });
  it('classifies mixed staff/preview claims as unlinked before any desk body or RPC', async () => {
    for (const route of [...deskRoutes, readRoutes[1]]) {
      state.claims = { ...owner, impersonation_session_id: id };
      state.calls = [];
      state.events = [];
      const req = route.method === 'GET' ? new Request('https://gym.example/api') : request({}, route.method, true);
      const response = await invoke(route, req);
      expect(response.status).toBe(401);
      expect((await response.json()).error.code).toBe('not_signed_in');
      expect(state.calls).toEqual([]);
      expect(state.events).not.toContain('body');
    }
  });
});
