// Independent PAY app-layer holdout; frozen contract only (openspec/changes/member-purchases/
// proposal.md BUY-001…025 + contract-resolution-amendment.md); no visible PAY app suite and
// no implementation read. Route discovery follows frozen public URL paths; Next's
// internal dynamic-segment variable spelling is not part of the HTTP contract.
// Named pay-app-boundary-held.test.ts because another holdout already occupied
// pay-app-held.test.ts; the parent orchestrator should dedupe the two.
import { beforeEach, describe, expect, it, vi } from 'vitest';
import * as publicShared from '../../packages/shared/src/config/constants';
import { buildMediaObjectKey, parseMediaObjectKey } from '../../packages/shared/src/api/media';
import { purchaseCreateRequestSchema, purchaseRequestCopy, purchaseRequestRefusalMessage, purchaseRequestStatusWord } from '../../packages/shared/src/api/purchase';
const s = publicShared as unknown as Record<string, { safeParse?: (value: unknown) => { success: boolean }; parse?: (value: unknown) => unknown } | ((...args: unknown[]) => unknown) | Record<string, unknown> | number | string>;

const id = '79400000-0000-4000-8000-000000000001';
const other = '79400000-0000-4000-8000-000000000002';
const uuid = (n: number) => `79400000-0000-4000-8000-00000000000${n}`;
const h = vi.hoisted(() => ({ identity: null as unknown, rpc: vi.fn(), reply: { data: null as unknown, error: null as unknown }, cookie: vi.fn(), bearer: vi.fn(), fetch: vi.fn() }));
vi.mock('../../apps/web/lib/identity-session', () => ({ readIdentity: h.cookie, readRequestIdentity: h.bearer }));

const memberBase = '../../apps/web/app/api/member/purchase-requests';
const staffBase = '../../apps/web/app/api/purchase-requests';
const routeModules = import.meta.glob('../../apps/web/app/api/{member/purchase-requests,purchase-requests}/**/route.ts');
const moduleSlots = new WeakMap<object, string>();
async function loadRoute(publicPath: string) {
  const key = Object.keys(routeModules).find(path => path.replace(/\[[^\]]+\]/g, '[id]') === `${publicPath}.ts`);
  if (!key) throw new Error(`Missing frozen PAY route: ${publicPath}`);
  const module = await routeModules[key]() as object;
  moduleSlots.set(module, key.match(/\[([^\]]+)\]/)?.[1] ?? 'id');
  return module;
}
type Route = { name: string; load: () => Promise<unknown>; method: string; rpc: string | null; member: boolean; staff: boolean; role: string; body: Record<string, unknown> | null };
const routes: Route[] = [
  { name: 'member-create', load: () => loadRoute(`${memberBase}/route`), method: 'POST', rpc: 'create_purchase_request', member: true, staff: false, role: 'front_desk', body: { requestKey: id, kind: 'shop', targetId: other, quantity: 1, expectedRevision: uuid(2) } },
  { name: 'member-list', load: () => loadRoute(`${memberBase}/route`), method: 'GET', rpc: 'read_member_purchase_requests', member: true, staff: false, role: 'front_desk', body: null },
  { name: 'member-detail', load: () => loadRoute(`${memberBase}/[id]/route`), method: 'GET', rpc: 'read_purchase_request', member: true, staff: false, role: 'front_desk', body: null },
  { name: 'member-cancel', load: () => loadRoute(`${memberBase}/[id]/cancel/route`), method: 'POST', rpc: 'cancel_purchase_request', member: true, staff: false, role: 'front_desk', body: { commandKey: uuid(3) } },
  { name: 'member-reconfirm', load: () => loadRoute(`${memberBase}/[id]/reconfirm/route`), method: 'POST', rpc: 'reconfirm_purchase_quote', member: true, staff: false, role: 'front_desk', body: { expectedRevision: uuid(2), commandKey: uuid(3) } },
  { name: 'member-proof-confirm', load: () => loadRoute(`${memberBase}/[id]/proof-confirm/route`), method: 'POST', rpc: 'attach_payment_proof', member: true, staff: false, role: 'front_desk', body: { assetId: other, expectedRevision: uuid(2), commandKey: uuid(3) } },
  { name: 'staff-list', load: () => loadRoute(`${staffBase}/route`), method: 'GET', rpc: 'read_purchase_requests', member: false, staff: true, role: 'front_desk', body: null },
  { name: 'staff-accept', load: () => loadRoute(`${staffBase}/[id]/accept/route`), method: 'POST', rpc: 'accept_purchase_request', member: false, staff: true, role: 'front_desk', body: { expectedRevision: uuid(2), commandKey: uuid(3) } },
  { name: 'staff-reject', load: () => loadRoute(`${staffBase}/[id]/reject/route`), method: 'POST', rpc: 'reject_purchase_request', member: false, staff: true, role: 'front_desk', body: { expectedRevision: uuid(2), reason: 'No stock left', commandKey: uuid(3) } },
  { name: 'staff-reject-proof', load: () => loadRoute(`${staffBase}/[id]/reject-proof/route`), method: 'POST', rpc: 'reject_payment_proof', member: false, staff: true, role: 'front_desk', body: { assetId: other, expectedRevision: uuid(2), reason: 'Unclear screenshot', commandKey: uuid(3) } },
  { name: 'staff-record', load: () => loadRoute(`${staffBase}/[id]/record/route`), method: 'POST', rpc: 'record_purchase_request', member: false, staff: true, role: 'gym_manager', body: { expectedRevision: uuid(2), commandKey: uuid(3), actualAmount: '250000', currency: 'INR', method: 'upi' } },
];

beforeEach(() => {
  h.identity = null; h.reply = { data: null, error: null };
  h.rpc.mockReset(); h.cookie.mockReset(); h.bearer.mockReset(); h.fetch.mockReset();
  const read = async () => h.identity === null ? null : ({ identity: h.identity, supabase: { rpc: h.rpc }, signedIn: true, authenticatedUser: true });
  h.cookie.mockImplementation(read); h.bearer.mockImplementation(read);
  h.rpc.mockImplementation(() => Object.assign(Promise.resolve(h.reply), { single: async () => h.reply, maybeSingle: async () => h.reply }));
  h.fetch.mockImplementation(async () => new Response(JSON.stringify({ ok: true, data: { assetId: other } }), { status: 200, headers: { 'content-type': 'application/json' } }));
  vi.stubGlobal('fetch', h.fetch);
});

function act(kind: 'member' | 'staff' | 'impersonation' | 'none', role = 'front_desk') {
  if (kind === 'none') { h.identity = null; return; }
  if (kind === 'member') { h.identity = { kind: 'member', userId: id, tenantId: id, memberId: id }; return; }
  if (kind === 'impersonation') { h.identity = { kind: 'impersonation', userId: id, tenantId: id, impersonationSessionId: id }; return; }
  h.identity = { kind: 'staff', userId: id, tenantId: id, staffId: id, role };
}
async function dispatch(route: Route, requestInit: Request) {
  const mod = await route.load() as Record<string, (request: Request, context: { params: Promise<Record<string, string>> }) => Promise<Response>>;
  return mod[route.method](requestInit, { params: Promise.resolve({ [moduleSlots.get(mod) ?? 'id']: id }) });
}
function request(route: Route, body: unknown, search = '') {
  return new Request(`https://holdout.example/api/purchase${search}`, { method: route.method, headers: { authorization: 'Bearer held' }, body: body === null ? undefined : JSON.stringify(body) });
}

describe('PAY routes: session-before-body, role and identity armor', () => {
  it.each(routes)('$name rejects unauthenticated requests before parsing the body', async route => {
    act('none'); const req = new Request('https://holdout.example/x', { method: route.method, body: route.body === null ? undefined : 'bad-json' }); const parse = vi.spyOn(req, 'json');
    const response = await dispatch(route, req);
    expect(response.status).toBe(401); expect(parse).not.toHaveBeenCalled(); expect(h.rpc).not.toHaveBeenCalled(); expect(h.fetch).not.toHaveBeenCalled();
    expect(response.headers.get('cache-control')).toBe('no-store');
  });
  it.each(routes)('$name preview/impersonation cannot mutate or even parse', async route => {
    act('impersonation'); const req = request(route, route.body); const parse = vi.spyOn(req, 'json');
    const response = await dispatch(route, req);
    expect(response.status).toBeGreaterThanOrEqual(400); expect(parse).not.toHaveBeenCalled(); expect(h.rpc).not.toHaveBeenCalled(); expect(h.fetch).not.toHaveBeenCalled();
  });
  it.each(routes.filter(r => r.staff))('$name refuses a member session with 403 and no target facts', async route => {
    act('member'); const response = await dispatch(route, request(route, route.body));
    expect(response.status).toBe(403); expect(h.rpc).not.toHaveBeenCalled();
    const body = JSON.stringify(await response.json());
    expect(body).not.toContain(id); expect(body).not.toContain(other);
    expect(body).not.toMatch(/stock|proof snapshot|member name/i);
  });
  it.each(routes.filter(r => r.staff))('$name refuses the trainer role everywhere', async route => {
    act('staff', 'trainer'); const response = await dispatch(route, request(route, route.body));
    expect(response.status).toBe(403); expect(h.rpc).not.toHaveBeenCalled();
  });
  it.each(routes.filter(r => r.member))('$name refuses a staff session on member-only commands', async route => {
    act('staff', 'gym_owner'); const response = await dispatch(route, request(route, route.body));
    expect(response.status).toBe(403); expect(h.rpc).not.toHaveBeenCalled(); expect(h.fetch).not.toHaveBeenCalled();
  });
  it.each(routes.filter(r => r.body !== null))('$name strict schemas refuse client identity injection before any call', async route => {
    act(route.member ? 'member' : 'staff'); const response = await dispatch(route, request(route, { ...route.body, tenantId: other, memberId: other, staffId: other }));
    expect(response.status).toBe(400); expect(h.rpc).not.toHaveBeenCalled(); expect(h.fetch).not.toHaveBeenCalled();
  });
});

describe('PAY routes: exact RPC pinning and replay pass-through', () => {
  it.each(routes.filter(r => r.rpc && r.body !== null))('$name calls exactly its frozen RPC once with snake_case p_ arguments', async route => {
    act(route.member ? 'member' : 'staff', route.role);
    h.reply.data = { id, status: 'requested', replayed: false };
    const response = await dispatch(route, request(route, route.body));
    expect(h.rpc).toHaveBeenCalledTimes(1); expect(h.rpc.mock.calls[0][0]).toBe(route.rpc);
    const args = h.rpc.mock.calls[0][1] as Record<string, unknown>;
    expect(Object.keys(args).every(key => /^p_[a-z_]+$/.test(key)), `argument names must be p_ snake_case, got ${Object.keys(args).join(',')}`).toBe(true);
    expect(response.headers.get('cache-control')).toBe('no-store');
    const body = JSON.stringify(await response.json());
    expect(body).not.toMatch(/"(?:objectKey|object_key|etag|storageKey|url)"\s*:/i);
  });
  it('create passes the client request key through verbatim so the server owns replay', async () => {
    const route = routes[0]; act('member');
    const body = { requestKey: uuid(4), kind: 'shop', targetId: uuid(5), quantity: 1, expectedRevision: uuid(2) };
    await dispatch(route, request(route, body)); await dispatch(route, request(route, body));
    expect(h.rpc).toHaveBeenCalledTimes(2);
    expect(h.rpc.mock.calls[0][1]).toEqual(h.rpc.mock.calls[1][1]);
    expect((h.rpc.mock.calls[0][1] as Record<string, unknown>).p_request_key).toBe(uuid(4));
    expect((h.rpc.mock.calls[0][1] as Record<string, unknown>).p_kind).toBe('shop');
  });
  it('repeated identical desk commands are passed through unchanged — the route never regenerates command keys', async () => {
    const route = routes[10]; act('staff', 'gym_manager');
    await dispatch(route, request(route, route.body)); await dispatch(route, request(route, route.body));
    expect(h.rpc).toHaveBeenCalledTimes(2);
    expect(h.rpc.mock.calls[0][1]).toEqual(h.rpc.mock.calls[1][1]);
  });
  it('cancel dispatches the owning member identity and exact command key', async () => {
    const route = routes[3]; act('member');
    await dispatch(route, request(route, { commandKey: uuid(3) }));
    expect(h.rpc).toHaveBeenCalledWith('cancel_purchase_request', { p_request_id: id, p_command_key: uuid(3) });
  });
  it('staff list pagination is clamped by the registered member page size and cursor pair', async () => {
    const route = routes[6]; act('staff', 'front_desk'); h.reply.data = [];
    await dispatch(route, request(route, null, '?limit=99999'));
    const args = h.rpc.mock.calls[0][1] as Record<string, unknown>;
    expect(typeof s.MEMBER_PAGE_SIZE_DEFAULT).toBe('number');
    expect(args.p_limit).toBe(s.MEMBER_PAGE_SIZE_DEFAULT);
  });
});

describe('PAY routes: money honesty at the client boundary', () => {
  it('record refuses non-canonical actual amounts before any call', async () => {
    const route = routes[10]; act('staff', 'gym_manager');
    for (const [amount, why] of [[250000, 'number never crosses'], ['1.5', 'fractional rupees'], ['0', 'zero money'], ['-5', 'negative money'], ['250000.005', 'sub-paise'], ['9223372036854775808', 'bigint overflow']] as Array<[unknown, string]>) {
      const response = await dispatch(route, request(route, { ...route.body, actualAmount: amount }));
      expect(response.status, why).toBe(400); expect(h.rpc, why).not.toHaveBeenCalled();
      h.rpc.mockClear();
    }
  });
  it('record requires an explicit currency and payment method — nothing is defaulted client-side', async () => {
    const route = routes[10]; act('staff', 'gym_manager');
    for (const dropped of ['currency', 'method']) {
      const partial = { ...route.body } as Record<string, unknown>; delete partial[dropped];
      const response = await dispatch(route, request(route, partial));
      expect(response.status).toBe(400); expect(h.rpc).not.toHaveBeenCalled();
      h.rpc.mockClear();
    }
  });
  it.each([['GL068', 409], ['GL066', 409], ['GL123', 409], ['GL124', 409], ['GL125', 409], ['42501', 403], ['P0002', 404], ['23514', 422], ['XX000', 500]])('record maps %s to a stable %d response that leaks no SQL identity', async (code, status) => {
    const route = routes[10]; act('staff', 'gym_manager'); h.reply.error = { code, details: 'PRIVATE_SQL_MEMBER_MONEY_SECRET', message: 'PRIVATE_MESSAGE' };
    const response = await dispatch(route, request(route, route.body));
    expect(response.status).toBe(status); expect(response.headers.get('cache-control')).toBe('no-store');
    expect(JSON.stringify(await response.json())).not.toMatch(/PRIVATE_|GL12|GL06|XX000/);
  });
  it('foreign and unknown request ids share one indistinguishable 404 — no existence oracle', async () => {
    const route = routes[2]; act('member');
    for (const probe of [uuid(9), uuid(8)]) {
      const mod = await route.load() as Record<string, (request: Request, context: { params: Promise<Record<string, string>> }) => Promise<Response>>;
      const response = await mod.GET(request(route, null), { params: Promise.resolve({ [moduleSlots.get(mod) ?? 'id']: probe }) });
      expect(response.status).toBe(404);
    }
    expect(h.rpc).toHaveBeenCalledTimes(2);
  });
});

describe('PAY routes: proof privacy and upload truth', () => {
  it('proof-confirm publishes through the Edge boundary before any attach RPC, and storage failure attaches nothing', async () => {
    const route = routes[5]; act('member'); h.reply.data = { id, status: 'payment_proof_uploaded', replayed: false };
    const ok = await dispatch(route, request(route, route.body));
    expect(h.fetch).toHaveBeenCalledTimes(1); expect(h.rpc).toHaveBeenCalledTimes(1);
    expect(h.rpc.mock.calls[0][0]).toBe('attach_payment_proof');
    expect(String(h.fetch.mock.calls[0][0])).toMatch(/proof/);
    expect(ok.headers.get('cache-control')).toBe('no-store');
    h.fetch.mockImplementation(async () => new Response(JSON.stringify({ ok: false, error: { code: 'upload_rejected', message: 'x' } }), { status: 422 }));
    h.rpc.mockClear();
    const refused = await dispatch(route, request(route, route.body));
    expect(refused.status).toBe(422); expect(h.rpc).not.toHaveBeenCalled();
  });
  it('proof-url issues an authorized ephemeral reference with no-store and never an object key or etag', async () => {
    const route: Route = { name: 'proof-url', load: () => loadRoute(`${staffBase}/[id]/proof-url/route`), method: 'POST', rpc: null, member: true, staff: false, role: 'front_desk', body: null };
    act('member'); h.fetch.mockImplementation(async () => new Response(JSON.stringify({ ok: true, data: { url: `https://media.holdout.example/${id}/published/payment_proof/${uuid(5)}.jpg` } }), { status: 200 }));
    const response = await dispatch(route, request(route, null));
    expect(response.headers.get('cache-control')).toBe('no-store');
    const body = JSON.stringify(await response.json());
    expect(body).not.toMatch(/"(?:objectKey|object_key|etag|storageKey)"\s*:/i);
  });
  it.each(routes)('$name never echoes storage internals in a failed response', async route => {
    act(route.member ? 'member' : 'staff', route.role); h.reply.error = { code: 'P0002', details: 'PRIVATE_TOKEN_HINT', message: 'PRIVATE_HINT' };
    const response = await dispatch(route, request(route, route.body));
    expect(JSON.stringify(await response.json() ?? {})).not.toMatch(/PRIVATE_|object_|etag/i);
  });
});

describe('PAY shared contract: limits, copy truth and money vocabulary', () => {
  it('BUY_LIMITS pins the frozen numbers exactly', () => {
    const limits = s.BUY_LIMITS as unknown as Record<string, number>;
    expect(limits.requestTtlSecondsAfterAcceptance).toBe(86400);
    expect(limits.requestTtlSecondsUnaccepted).toBe(86400);
    expect(limits.openRequestsPerMember).toBe(5);
    expect(limits.creationsPerMemberPerDay).toBe(10);
    expect(limits.proofRegistrationsPerMemberPerHour).toBe(10);
    expect(limits.maxQuantity).toBe(10);
    expect(limits.reasonMinLength).toBe(3); expect(limits.reasonMaxLength).toBe(200);
    expect(limits.privateProofGetTtlSeconds).toBe(60);
  });
  it('status vocabulary upholds BUY-022: pending verification is not payment recorded, and mismatch is not a purchase', () => {
    const copy = purchaseRequestCopy as unknown as Record<string, string>;
    for (const status of ['requested', 'owner_accepted', 'payment_proof_uploaded', 'recorded', 'mismatch_recorded', 'rejected', 'cancelled', 'expired']) expect(typeof purchaseRequestStatusWord(status)).toBe('string');
    for (const key of ['requested', 'accepted', 'pendingVerification', 'recorded', 'mismatchTitle', 'mismatchNote', 'rejectedTitle', 'cancelledTitle', 'expiredTitle']) expect(typeof copy[key]).toBe('string');
    expect(copy.pendingVerification).toMatch(/pending verification/i);
    expect(copy.recorded).toMatch(/payment recorded/i);
    expect(copy.mismatchNote).toMatch(/desk/i);
    expect(copy.mismatchNote).not.toMatch(/bought|purchase complete|fulfilled/i);
    const everything = Object.values(copy).join(' ');
    expect(everything).not.toMatch(/bank[- ]verified|payment successful|automatically (?:verified|settled)|instantly verified/i);
  });
  it.each(['invalid_request', 'request_unavailable', 'upload_rejected', 'rate_limited', 'not_permitted'])('refusal %s has a specific honest message', code => {
    const message = purchaseRequestRefusalMessage(code);
    expect(typeof message).toBe('string'); expect(message.length).toBeGreaterThan(10);
    expect(message).not.toMatch(/bank[- ]verified|payment successful/i);
  });
  it('unknown or hostile refusal codes fall back to fixed copy that never echoes the caller input', () => {
    const refusal = purchaseRequestRefusalMessage as unknown as (value: string) => string;
    for (const probe of ['constructor', '__proto__', `${id} SHOP_STOCK_SECRET`, 'request_unavailable; DROP TABLE']) {
      const message = refusal(probe);
      expect(message).not.toContain(id); expect(message).not.toContain(probe);
    }
    expect(refusal('constructor')).toBe(refusal('__proto__'));
  });
  it('create schema is strict: identity, storage and proof internals can never be client-authored', () => {
    const schema = purchaseCreateRequestSchema as unknown as { safeParse(value: unknown): { success: boolean } };
    expect(schema.safeParse({ requestKey: id, kind: 'shop', targetId: other, quantity: 1, expectedRevision: uuid(2) }).success).toBe(true);
    for (const bad of ['tenantId', 'memberId', 'staffId', 'objectKey', 'proofUrl', 'screenshotBase64', 'amountPaise', 'gstRateBp', '__proto_payload']) {
      expect(schema.safeParse({ requestKey: id, kind: 'shop', targetId: other, quantity: 1, expectedRevision: uuid(2), [bad]: other }).success).toBe(false);
    }
    for (const kind of ['complimentary', 'gateway', 'membership', '']) expect(schema.safeParse({ requestKey: id, kind, targetId: other, quantity: 1, expectedRevision: uuid(2) }).success).toBe(false);
    for (const quantity of [0, -1, 11, 1.5, '1', null]) expect(schema.safeParse({ requestKey: id, kind: 'shop', targetId: other, quantity, expectedRevision: uuid(2) }).success).toBe(false);
  });
  it('payment_proof becomes a parseable private MEDIA namespace, staged then published', () => {
    for (const storageArea of ['staging', 'published'] as const) {
      const key = (buildMediaObjectKey as unknown as (...a: unknown[]) => string)({ tenantId: id, objectUuid: id, kind: 'payment_proof', mime: 'image/jpeg', storageArea });
      expect(key).toBe(`${id}/${storageArea}/payment_proof/${id}.jpg`);
      expect((parseMediaObjectKey as unknown as (value: string) => unknown)(key)).toEqual({ tenantId: id, objectUuid: id, kind: 'payment_proof', extension: 'jpg', storageArea });
    }
  });
  it('member page size default exists and the limits object is registered rather than inlined', () => {
    expect(typeof s.MEMBER_PAGE_SIZE_DEFAULT).toBe('number');
    expect(typeof s.BUY_LIMITS).toBe('object');
  });
});
