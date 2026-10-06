import { beforeEach, describe, expect, it, vi } from 'vitest';

// SHP-PAGE-001..005/009. Only verified-session/RPC/media boundaries are doubled.
const h = vi.hoisted(() => ({ claims: null as Record<string, unknown> | null, events: [] as string[], calls: [] as Array<{ name: string; args: unknown }>, page: null as unknown, catalogue: [] as unknown[], error: null as unknown, sign: vi.fn() }));
const id = '85000000-0000-4000-8000-000000000001';
const asset = '85000000-0000-4000-8000-000000000002';
const member = { role: 'authenticated', sub: id, app_role: 'member', tenant_id: id, member_id: id };
const cursor = { createdAt: '2026-10-07T03:40:11.123456+00:00', id };
const raw = { reservation_id: id, item_id: id, item_name: 'Saved snapshot name', section: 'products', quantity: 2, unit_price_paise: '9007199254740993', total_paise: '18014398509481986', currency: 'INR', state: 'expired', created_at: cursor.createdAt, expires_at: '2026-10-08T03:40:11Z', cancel_reason: null, terms_changed: false, order_id: null, image_asset_id: asset };
const page = (active = [] as unknown[], history = [raw] as unknown[]) => ({ active_reservations: active, history, next_after_created_at: cursor.createdAt, next_after_id: cursor.id, as_of: '2026-10-07T03:40:12.987654+00:00' });
const client = {
  auth: {
    getClaims: async () => { h.events.push('verified-session'); return { data: { claims: h.claims }, error: null }; },
    getUser: async () => ({ data: { user: h.claims ? { id: h.claims.sub } : null }, error: null }),
    getSession: async () => ({ data: { session: { access_token: 'caller-forwarded-token' } }, error: null }),
  },
  rpc: async (name: string, args: unknown) => { h.calls.push({ name, args }); return name === 'read_member_shop_reservation_page' ? { data: h.page, error: h.error } : { data: h.catalogue, error: null }; },
  from: () => { throw new Error('Paged Shop cannot inspect private media storage'); },
};
vi.mock('../../lib/supabase/server', () => ({ createServerSupabase: async () => client }));
vi.mock('../../lib/supabase/request', () => ({ createRequestSupabase: async () => ({ supabase: client, bearer: 'caller-forwarded-token' }) }));
vi.mock('../../lib/media', () => ({ memberMediaUrl: h.sign }));
function request(body: unknown, broken = false) {
  const req = new Request('https://gym.example/api/shop/catalogue/page', { method: 'POST', headers: { authorization: 'Bearer caller-forwarded-token', 'content-type': 'application/json' }, body: broken ? '{' : JSON.stringify(body) });
  const original = req.json.bind(req);
  vi.spyOn(req, 'json').mockImplementation(async () => { h.events.push('body'); return original(); });
  return req;
}
async function invoke(body: unknown, broken = false) { const { POST } = await import('../api/shop/catalogue/page/route'); return POST(request(body, broken)); }
beforeEach(() => { h.claims = member; h.events = []; h.calls = []; h.page = [page()]; h.catalogue = []; h.error = null; h.sign.mockReset().mockResolvedValue('https://images.example/caller-photo'); });

describe('SHP-PAGE paged Shop actual HTTP and loader contract', () => {
  it.each([
    null,
    { role: 'authenticated', sub: id, app_role: 'gym_owner', tenant_id: id, staff_id: id },
    { role: 'authenticated', sub: id, app_role: 'super_admin' },
    { ...member, staff_id: id },
    { ...member, impersonation_session_id: id },
    { ...member, tenant_id: 'not-a-uuid' },
  ])('authorizes audience before even malformed JSON %j', async claims => {
    h.claims = claims;
    const response = await invoke({}, true);
    expect([401, 403]).toContain(response.status);
    expect(h.events).not.toContain('body'); expect(h.calls).toEqual([]); expect(h.sign).not.toHaveBeenCalled();
    expect(response.headers.get('cache-control')).toBe('no-store');
  });
  it.each([{ mode: 'more', after: null }, { mode: 'more', after: { createdAt: cursor.createdAt } }, { mode: 'more', after: { ...cursor, createdAt: '2026-02-30T03:40:11Z' } }, { mode: 'more', after: { ...cursor, createdAt: '2026-10-07T03:40:11' } }, { mode: 'initial', tenantId: id }, { mode: 'initial', memberId: id }, { mode: 'more', after: cursor, pageSize: 200 }, { mode: 'initial', after: cursor }, {}])('refuses invalid page %j before feature RPC', async body => {
    const response = await invoke(body); expect(response.status).toBe(400);
    expect((await response.json()).error.code).toBe('invalid_request'); expect(h.calls).toEqual([]); expect(h.sign).not.toHaveBeenCalled();
    expect(h.events.indexOf('verified-session')).toBeLessThan(h.events.indexOf('body')); expect(response.headers.get('cache-control')).toBe('no-store');
  });
  it('initial reads catalogue and new reservations, preserving exact money and cursor', async () => {
    const response = await invoke({ mode: 'initial' }); expect(response.status).toBe(200);
    const result = await response.json(); expect(result.ok).toBe(true);
    expect(result.data).toMatchObject({ mode: 'initial', items: [], reservations: [{ reservationId: id, itemName: 'Saved snapshot name', totalPaise: '18014398509481986', unitPricePaise: '9007199254740993', imageUrl: 'https://images.example/caller-photo' }], nextAfter: cursor, truncated: false, serverTime: '2026-10-07T03:40:12.987654+00:00' });
    expect(h.calls.map(call => call.name).sort()).toEqual(['read_member_shop', 'read_member_shop_reservation_page']);
    expect(h.calls.find(call => call.name === 'read_member_shop_reservation_page')?.args).toEqual({ p_after_created_at: null, p_after_id: null });
    expect(h.sign.mock.calls[0]?.slice(0, 2)).toEqual([client, asset]); expect(response.headers.get('cache-control')).toBe('no-store');
    expect(JSON.stringify(result)).not.toMatch(/image_asset_id|object_key|staging|caller-forwarded-token/);
  });
  it('more never reads catalogue or legacy reservations and forwards cursor text untouched', async () => {
    const response = await invoke({ mode: 'more', after: cursor }); expect(response.status).toBe(200);
    const result = await response.json(); expect(result.data.mode).toBe('more'); expect(result.data.nextAfter).toEqual(cursor);
    expect(result.data).not.toHaveProperty('items'); expect(result.data).not.toHaveProperty('truncated');
    expect(h.calls).toEqual([{ name: 'read_member_shop_reservation_page', args: { p_after_created_at: cursor.createdAt, p_after_id: cursor.id } }]);
    expect(response.headers.get('cache-control')).toBe('no-store');
  });
  it('direct loader uses the same frozen page projection', async () => {
    const { loadMemberShopPage } = await import('../../lib/shop');
    const result = await loadMemberShopPage(client as unknown as Parameters<typeof loadMemberShopPage>[0], { mode: 'more', after: cursor });
    expect(result).toMatchObject({ mode: 'more', reservations: [{ totalPaise: '18014398509481986' }], nextAfter: cursor });
    expect(h.calls).toHaveLength(1);
  });
  it.each([
    [], [page([], [{ ...raw, total_paise: 1 }])], [page([], [{ ...raw, state: 'paid' }])],
    [{ ...page(), next_after_id: null }], [{ ...page(), next_after_created_at: 'bad' }],
    [page([], Array.from({ length: 6 }, () => raw))], [page([raw], [])],
  ])('malformed continuation backend cannot enter a successful envelope %j', async bad => {
    h.page = bad; const response = await invoke({ mode: 'more', after: cursor });
    expect(response.status).toBe(500); const result = await response.json(); expect(result.ok).toBe(false); expect(result).not.toHaveProperty('data');
    expect(response.headers.get('cache-control')).toBe('no-store');
  });
  it.each(['42501', '22023', 'XX000'])('sanitizes %s feature failure and remains no-store', async code => {
    h.error = { code, message: 'RAW_PRIVATE_UPSTREAM_TOKEN', details: 'RAW_PRIVATE_DETAIL' };
    const response = await invoke({ mode: 'more', after: cursor });
    expect(response.status).toBe(code === '42501' ? 403 : code === '22023' ? 400 : 500);
    expect(await response.text()).not.toMatch(/RAW_PRIVATE/); expect(response.headers.get('cache-control')).toBe('no-store');
  });
  it('released empty-body route still invokes only released reads and rejects paging bodies', async () => {
    const { POST } = await import('../api/shop/catalogue/route');
    const response = await POST(request({})); expect(response.status).toBe(200);
    const result = await response.json(); expect(result.data).toMatchObject({ items: [], reservations: [], truncated: false });
    expect(result.data).not.toHaveProperty('mode'); expect(result.data).not.toHaveProperty('nextAfter');
    expect(h.calls.map(call => call.name).sort()).toEqual(['read_member_shop', 'read_member_shop_reservations']);
    h.calls = []; expect((await POST(request({ mode: 'initial' }))).status).toBe(400); expect(h.calls).toEqual([]);
  });
});
