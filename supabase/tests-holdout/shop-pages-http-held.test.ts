// Runtime-only independent SHP-PAGE HTTP and safe loader proof.
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { GymloopIdentity } from '../../packages/shared/src/api/identity';
import * as publicLoader from '../../apps/web/lib/shop';
const h = vi.hoisted(() => ({ identity: null as GymloopIdentity | null, rpc: vi.fn(), bearer: vi.fn(), cookie: vi.fn(), signer: vi.fn() }));
vi.mock('../../apps/web/lib/identity-session', () => ({ readIdentity: h.cookie, readRequestIdentity: h.bearer }));
vi.mock('../../apps/web/lib/media', () => ({ memberMediaUrl: h.signer, mediaDisplayUrl: vi.fn() }));
const id = (n: number) => `92040000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const timestamp = '2026-10-06T23:59:59.999999+05:30';
const after = { createdAt: timestamp, id: id(5) };
const row = (patch = {}) => ({ reservation_id: id(5), item_id: id(8), item_name: 'Frozen name', section: 'products', quantity: 10, unit_price_paise: '9007199254740993', total_paise: '90071992547409930', currency: 'INR', state: 'cancelled_by_gym', created_at: timestamp, expires_at: '2026-10-07T01:00:00Z', cancel_reason: 'Desk reason', terms_changed: false, order_id: null, image_asset_id: null, ...patch });
const page = (patch = {}) => ({ active_reservations: [], history: [row()], next_after_created_at: timestamp, next_after_id: id(5), as_of: '2026-10-07T01:00:00.000001Z', ...patch });
const request = (body: unknown) => new Request('https://held.example/api/shop/catalogue/page', { method: 'POST', headers: { authorization: 'Bearer held-caller' }, body: JSON.stringify(body) });
const load = async (input: unknown) => {
  const fn = (publicLoader as unknown as Record<string, unknown>).loadMemberShopPage;
  expect(fn).toBeTypeOf('function');
  return (fn as (client: unknown, input: unknown) => Promise<Record<string, unknown>>)({ rpc: h.rpc }, input);
};
const dispatch = async (req: Request) => {
  const entry = await import('../../apps/web/app/api/shop/catalogue/page/route');
  return entry.POST(req);
};
beforeEach(() => {
  vi.clearAllMocks();
  h.identity = { kind: 'member', userId: id(1), tenantId: id(2), memberId: id(3) };
  const identity = async () => ({ identity: h.identity ?? { kind: 'unlinked' }, signedIn: h.identity !== null, authenticatedUser: h.identity !== null, supabase: { rpc: h.rpc } });
  h.bearer.mockImplementation(identity); h.cookie.mockImplementation(identity);
  h.rpc.mockImplementation((name: string) => Object.assign(Promise.resolve({ data: name === 'read_member_shop' ? [] : [page()], error: null }), { single: async () => ({ data: page(), error: null }), maybeSingle: async () => ({ data: page(), error: null }) }));
  h.signer.mockResolvedValue('https://held.example/temporary-image');
});

describe('independent SHP-PAGE-001/004 auth before body', () => {
  it.each(['anonymous', 'staff', 'platform', 'preview', 'unlinked'] as const)('denies %s before parsing even malformed JSON', async audience => {
    h.identity = audience === 'anonymous' ? null : audience === 'staff' ? { kind: 'staff', userId: id(1), tenantId: id(2), staffId: id(4), role: 'front_desk' } : audience === 'platform' ? { kind: 'platform', userId: id(1), role: 'super_admin' } as GymloopIdentity : audience === 'preview' ? { kind: 'impersonation', userId: id(1), tenantId: id(2), impersonationSessionId: id(4) } : { kind: 'unlinked' };
    const req = new Request('https://held.example/api/shop/catalogue/page', { method: 'POST', body: '{bad' });
    const parse = vi.spyOn(req, 'json');
    const response = await dispatch(req);
    expect(response.status).toBe(audience === 'anonymous' ? 401 : 403);
    expect(parse).not.toHaveBeenCalled(); expect(h.rpc).not.toHaveBeenCalled();
    expect(response.headers.get('cache-control')).toBe('no-store');
  });
  it.each([
    { mode: 'initial', tenantId: id(2) }, { mode: 'initial', memberId: id(3) },
    { mode: 'more', after: null }, { mode: 'more', after: { createdAt: timestamp } },
    { mode: 'more', after: { createdAt: '2026-02-30T01:00:00Z', id: id(5) } },
    { mode: 'more', after: { createdAt: '2026-10-07T01:00:00', id: id(5) } },
    { mode: 'more', after, limit: 5 }, { mode: 'initial', after },
  ])('refuses invalid request without feature RPC %#', async body => {
    const response = await dispatch(request(body));
    expect(response.status).toBe(400); expect(h.rpc).not.toHaveBeenCalled();
    expect(response.headers.get('cache-control')).toBe('no-store');
    const data = await response.json(); expect(data.ok).toBe(false); expect(data.error.code).toBe('invalid_request');
  });
  it.each(['42501', '22023', 'XX000'])('sanitizes backend %s', async code => {
    h.rpc.mockResolvedValue({ data: null, error: { code, details: 'PRIVATE_TENANT_MEMBER_STORAGE', message: 'RAW_SQL_SECRET' } });
    const response = await dispatch(request({ mode: 'more', after }));
    expect(response.status).toBe(code === '42501' ? 403 : code === '22023' ? 400 : 500);
    expect(response.headers.get('cache-control')).toBe('no-store');
    expect(JSON.stringify(await response.json())).not.toMatch(/PRIVATE_|RAW_SQL|XX000|42501/);
  });
  it('uses the verified original bearer and a no-store safe success envelope', async () => {
    const req = request({ mode: 'more', after }); const response = await dispatch(req);
    expect(response.status).toBe(200); expect(h.bearer).toHaveBeenCalledWith(req); expect(h.cookie).not.toHaveBeenCalled();
    expect(response.headers.get('cache-control')).toBe('no-store');
    const data = await response.json(); expect(data.ok).toBe(true); expect(data.data.mode).toBe('more'); expect(data.data.nextAfter).toEqual(after);
  });
});

describe('independent SHP-PAGE-002/003/005 loader', () => {
  it('continues once with exact string cursor and no catalogue or legacy reservation RPC', async () => {
    const response = await load({ mode: 'more', after });
    expect(h.rpc).toHaveBeenCalledExactlyOnceWith('read_member_shop_reservation_page', { p_after_created_at: timestamp, p_after_id: id(5) });
    expect(response.nextAfter).toEqual(after); expect(response).not.toHaveProperty('items'); expect(response).not.toHaveProperty('truncated');
    expect((response.reservations as Array<Record<string, unknown>>)[0]).toMatchObject({ itemName: 'Frozen name', unitPricePaise: '9007199254740993', totalPaise: '90071992547409930', cancelReason: 'Desk reason' });
  });
  it('initial combines active before history and reads current catalogue exactly once', async () => {
    h.rpc.mockImplementation(async (name: string) => ({ error: null, data: name === 'read_member_shop' ? [] : [page({ active_reservations: [row({ reservation_id: id(6), state: 'reserved', cancel_reason: null })] })] }));
    const response = await load({ mode: 'initial' });
    expect(response.mode).toBe('initial'); expect(response.items).toEqual([]); expect(response.truncated).toBe(false);
    expect((response.reservations as Array<Record<string, unknown>>).map(entry => entry.reservationId)).toEqual([id(6), id(5)]);
    expect(h.rpc.mock.calls.map(call => call[0]).sort()).toEqual(['read_member_shop', 'read_member_shop_reservation_page']);
  });
  it('signs exposed opaque asset IDs with the same caller capability', async () => {
    h.rpc.mockResolvedValue({ error: null, data: [page({ history: [row({ image_asset_id: id(9) })] })] });
    const client = { rpc: h.rpc };
    const fn = (publicLoader as unknown as { loadMemberShopPage: (client: unknown, input: unknown) => Promise<Record<string, unknown>> }).loadMemberShopPage;
    expect(fn).toBeTypeOf('function'); const response = await fn(client, { mode: 'more', after });
    expect(h.signer).toHaveBeenCalledWith(client, id(9)); expect(JSON.stringify(response)).not.toContain('image_asset_id');
    expect((response.reservations as Array<Record<string, unknown>>)[0]?.imageUrl).toBe('https://held.example/temporary-image');
  });
  it.each([
    [], [page(), page()], [page({ history: Array.from({ length: 6 }, () => row()) })],
    [page({ next_after_id: null })], [page({ as_of: 'bad' })],
    [page({ history: [row({ total_paise: 9007199254740992 })] })],
    [page({ history: [row({ state: 'wrong' })] })],
    [page({ history: [row({ created_at: '2026-02-30T00:00:00Z' })] })],
  ])('invalid backend page fails instead of entering a view %#', async data => {
    h.rpc.mockResolvedValue({ error: null, data });
    await expect(load({ mode: 'more', after })).rejects.toBeDefined();
  });
});
