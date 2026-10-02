import { beforeEach, describe, expect, it, vi } from 'vitest';

// Implementation-blind SHP HTTP boundary; database tests own SQL ordering.
const state = vi.hoisted(() => ({ claims: null as Record<string, unknown> | null, results: [] as Array<{ data: unknown; error: unknown }>, calls: [] as Array<{ name: string; args: unknown }>, events: [] as string[] }));
const client = () => ({
  auth: { getClaims: async () => { state.events.push('verified-session'); return { data: { claims: state.claims }, error: null }; }, getUser: async () => ({ data: { user: state.claims ? { id: state.claims.sub } : null }, error: null }) },
  rpc: async (name: string, args: unknown) => { state.calls.push({ name, args }); return state.results.shift() ?? { data: null, error: null }; },
  from: () => {
    const query: Record<string, unknown> = {};
    for (const method of ['select', 'insert', 'update', 'eq', 'order']) query[method] = () => query;
    const result = async () => state.results.shift() ?? { data: null, error: null };
    query.single = result; query.maybeSingle = result;
    query.then = (resolve: (value: unknown) => unknown) => result().then(resolve);
    return query;
  },
});
vi.mock('../../lib/supabase/server', () => ({ createServerSupabase: async () => client() }));
vi.mock('../../lib/supabase/request', () => ({ createRequestSupabase: async () => ({ supabase: client(), bearer: 'verified-caller-token' }) }));
const id = '72000000-0000-4000-8000-000000000001';
const owner = { role: 'authenticated', sub: id, app_role: 'gym_owner', tenant_id: id, staff_id: id };
const member = { role: 'authenticated', sub: id, app_role: 'member', tenant_id: id, member_id: id };
const reserve = { itemId: id, quantity: 1, quoteVersion: id };
const routes = [
  { path: '../api/shop/reservations/route', method: 'POST', audience: member, body: reserve },
  { path: '../api/shop/reservations/[reservationId]/cancel/route', method: 'POST', audience: member, body: {} },
  { path: '../api/shop-reservations/[reservationId]/cancel/route', method: 'POST', audience: owner, body: { reason: 'Not available' } },
  { path: '../api/shop-reservations/[reservationId]/fulfil/route', method: 'POST', audience: owner, body: { quoteVersion: id, method: 'cash', reason: null, idempotencyKey: id } },
  { path: '../api/shop/products/[productId]/route', method: 'PATCH', audience: owner, body: { categoryId: null, imageAssetId: null, sortOrder: 0 } },
  { path: '../api/shop/categories/route', method: 'POST', audience: owner, body: { name: 'Nutrition' } },
  { path: '../api/shop/categories/[categoryId]/route', method: 'PATCH', audience: owner, body: { isActive: false } },
  { path: '../api/shop/categories/order/route', method: 'PUT', audience: owner, body: { orderedIds: [id] } },
  { path: '../api/shop/catalogue/route', method: 'POST', audience: member, body: {} },
] as const;
function request(payload: unknown, method: string, malformed = false) {
  const value = new Request('https://gym.example/api/shop', { method, headers: { authorization: 'Bearer verified-caller-token', 'content-type': 'application/json' }, body: malformed ? '{' : JSON.stringify(payload) });
  const parse = value.json.bind(value); vi.spyOn(value, 'json').mockImplementation(async () => { state.events.push('body'); return parse(); }); return value;
}
const context = { params: Promise.resolve({ reservationId: id, productId: id, categoryId: id }) };
async function invoke(route: typeof routes[number], req: Request) { const module = await import(route.path); return module[route.method](req, context) as Promise<Response>; }
beforeEach(() => { state.claims = member; state.calls = []; state.results = []; state.events = []; });
describe('SHP route session/body order and safe failures', () => {
  it.each(routes)('$path identifies caller before reading malformed JSON', async route => {
    state.claims = null;
    const response = await invoke(route, request({}, route.method, true));
    expect([401, 403]).toContain(response.status); expect(state.events).not.toContain('body'); expect(state.calls).toEqual([]); expect(response.headers.get('cache-control')).toBe('no-store');
  });
  it.each(routes)('$path rejects extra fields without command execution', async route => {
    state.claims = route.audience;
    const response = await invoke(route, request({ ...route.body, tenantId: id }, route.method));
    expect(response.status).toBe(400); expect((await response.json()).error.code).toBe('invalid_request'); expect(state.calls).toEqual([]); expect(state.events.indexOf('verified-session')).toBeLessThan(state.events.indexOf('body')); expect(response.headers.get('cache-control')).toBe('no-store');
  });
  it.each([['GL086', 'quote_changed', 409], ['GL086', 'item_unavailable', 409], ['GL086', 'member_unavailable', 409], ['GL086', 'reservation_exists', 409], ['GL086', 'invalid_quantity', 422], ['GL086', 'reservation_limit', 429], ['GL087', 'sold_out', 409], ['42501', '', 403], ['22023', '', 400], ['XX000', 'secret upstream', 500]])('maps reserve %s/%s to %s without raw upstream disclosure', async (code, details, status) => {
    state.results = [{ data: null, error: { code, details, message: 'RAW_TOKEN_PRIVATE_KEY' } }];
    const response = await invoke(routes[0], request(reserve, 'POST'));
    expect(response.status).toBe(status); expect(response.headers.get('cache-control')).toBe('no-store'); expect(await response.text()).not.toContain('RAW_TOKEN_PRIVATE_KEY');
    expect(state.calls).toEqual([{ name: 'create_shop_reservation', args: { p_item_id: id, p_quantity: 1, p_quote_version: id } }]);
  });
  it('reserve returns only reservation intent, no payment or order', async () => {
    state.results = [{ data: [{ reservation_id: id, expires_at: '2026-10-03T10:00:00Z' }], error: null }];
    const response = await invoke(routes[0], request(reserve, 'POST'));
    expect(response.status).toBe(200); expect(await response.json()).toEqual({ ok: true, data: { reservationId: id, expiresAt: '2026-10-03T10:00:00Z' } });
  });
  it('member cancel sends null reason and no claimed member identity', async () => {
    const response = await invoke(routes[1], request({}, 'POST')); expect(response.status).toBe(200);
    expect(state.calls).toEqual([{ name: 'cancel_shop_reservation', args: { p_reservation_id: id, p_reason: null } }]);
  });
  it.each(['constructor', '__proto__', 'toString'])('does not treat prototype detail %s as a refusal mapping', async details => {
    state.results = [{ data: null, error: { code: 'GL086', details, message: 'private' } }]; expect((await invoke(routes[0], request(reserve, 'POST'))).status).toBe(500);
  });
  it.each([['23505', 409, 'category_name_taken'], ['42501', 404, 'category_not_found'], ['22023', 400, 'invalid_request']])('maps category %s safely', async (code, status, expected) => {
    state.claims = owner; state.results = [{ data: null, error: { code, message: 'raw private category' } }]; const response = await invoke(routes[5], request({ name: 'Nutrition' }, 'POST')); expect(response.status).toBe(status); expect((await response.json()).error.code).toBe(expected);
  });
  it.each(['reservation_not_open', 'reservation_expired'])('maps cancel %s without pretending success', async details => {
    state.results = [{ data: null, error: { code: 'GL086', details, message: 'private' } }]; const response = await invoke(routes[1], request({}, 'POST')); expect(response.status).toBe(409); expect((await response.json()).error.code).toBe(details);
  });
  it('fulfil forwards frozen sale inputs only, preserving decimal money machinery in SQL', async () => {
    state.claims = owner; state.results = [{ data: [{ reservation_id: id, order_id: id, payment_id: id, replayed: true }], error: null }]; const response = await invoke(routes[3], request(routes[3].body, 'POST')); expect(response.status).toBe(200); expect(await response.json()).toEqual({ ok: true, data: { reservationId: id, orderId: id, paymentId: id, replayed: true } }); expect(state.calls).toEqual([{ name: 'fulfil_shop_reservation', args: { p_reservation_id: id, p_quote_version: id, p_method: 'cash', p_reason: null, p_idempotency_key: id } }]);
  });
  it.each([['GL052', 'idempotency_conflict', 409], ['GL055', 'quote_changed', 409], ['GL055', 'offer_unavailable', 409], ['GL055', 'member_unavailable', 409], ['GL057', 'insufficient_stock', 409], ['GL086', 'reservation_expired', 409], ['GL086', 'reservation_not_open', 409], ['42501', '', 404]])('fulfil passes through sale refusal %s/%s', async (code, details, status) => {
    state.claims = owner; state.results = [{ data: null, error: { code, details, message: 'raw private sale' } }]; const response = await invoke(routes[3], request(routes[3].body, 'POST')); expect(response.status).toBe(status); const payload = await response.json(); expect(payload.ok).toBe(false); expect(payload.error.code).toBe(code === '42501' ? 'reservation_not_found' : details); expect(JSON.stringify(payload)).not.toContain('raw private sale');
  });
});
