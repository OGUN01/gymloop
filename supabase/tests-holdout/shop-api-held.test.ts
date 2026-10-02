// Independent SHP auth/body and refusal boundary; existing identity transport double only.
import { beforeEach, expect, it, vi } from 'vitest';
import type { GymloopIdentity } from '../../packages/shared/src/api/identity';
const h = vi.hoisted(() => ({ identity: null as GymloopIdentity | null, rpc: vi.fn(), reply: { data: null as unknown, error: null as unknown }, bearer: vi.fn(), cookie: vi.fn() }));
vi.mock('../../apps/web/lib/identity-session', () => ({ readIdentity: h.cookie, readRequestIdentity: h.bearer }));
const id = '72930000-0000-4000-8000-000000000001';
const routes = [
  { name: 'reserve', load: () => import('../../apps/web/app/api/shop/reservations/route'), method: 'POST', rpc: 'create_shop_reservation', member: true, body: { itemId: id, quantity: 2, quoteVersion: id } },
  { name: 'member-cancel', load: () => import('../../apps/web/app/api/shop/reservations/[reservationId]/cancel/route'), method: 'POST', rpc: 'cancel_shop_reservation', member: true, body: {} },
  { name: 'desk-cancel', load: () => import('../../apps/web/app/api/shop-reservations/[reservationId]/cancel/route'), method: 'POST', rpc: 'cancel_shop_reservation', member: false, body: { reason: 'Not enough stock' } },
  { name: 'fulfil', load: () => import('../../apps/web/app/api/shop-reservations/[reservationId]/fulfil/route'), method: 'POST', rpc: 'fulfil_shop_reservation', member: false, body: { quoteVersion: id, method: 'cash', reason: null, idempotencyKey: id } },
  { name: 'display', load: () => import('../../apps/web/app/api/shop/products/[productId]/route'), method: 'PATCH', rpc: 'set_shop_product_display', member: false, body: { categoryId: null, sortOrder: 0, imageAssetId: null } },
  { name: 'category-create', load: () => import('../../apps/web/app/api/shop/categories/route'), method: 'POST', rpc: null, member: false, body: { name: 'Food' } },
  { name: 'category-patch', load: () => import('../../apps/web/app/api/shop/categories/[categoryId]/route'), method: 'PATCH', rpc: null, member: false, body: { name: 'Food' } },
  { name: 'category-order', load: () => import('../../apps/web/app/api/shop/categories/order/route'), method: 'PUT', rpc: 'reorder_shop_categories', member: false, body: { orderedIds: [id] } },
];
beforeEach(() => {
  h.identity = null; h.reply = { data: null, error: null }; h.rpc.mockReset(); h.cookie.mockReset(); h.bearer.mockReset();
  const read = async () => ({ identity: h.identity ?? { kind: 'unlinked' }, supabase: { rpc: h.rpc }, signedIn: h.identity !== null, authenticatedUser: h.identity !== null });
  h.cookie.mockImplementation(read); h.bearer.mockImplementation(read);
  h.rpc.mockImplementation(() => Object.assign(Promise.resolve(h.reply), { single: async () => h.reply, maybeSingle: async () => h.reply }));
});
function actor(member: boolean) { h.identity = member ? { kind: 'member', userId: id, tenantId: id, memberId: id } : { kind: 'staff', userId: id, tenantId: id, staffId: id, role: 'gym_owner' }; }
async function dispatch(route: typeof routes[number], request: Request) { const mod = await route.load() as Record<string, (request: Request, context: { params: Promise<Record<string, string>> }) => Promise<Response>>; return mod[route.method](request, { params: Promise.resolve({ reservationId: id, productId: id, categoryId: id }) }); }
function request(route: typeof routes[number], body: unknown) { return new Request('https://holdout.example/api/shop', { method: route.method, headers: { authorization: 'Bearer held-member' }, body: JSON.stringify(body) }); }
it.each(routes)('$name rejects unauthenticated malformed body before parsing', async route => {
  const req = new Request('https://holdout.example/api/shop', { method: route.method, body: 'bad-json' }); const parse = vi.spyOn(req, 'json');
  const response = await dispatch(route, req); expect(response.status).toBe(401); expect(parse).not.toHaveBeenCalled(); expect(h.rpc).not.toHaveBeenCalled(); expect(response.headers.get('cache-control')).toBe('no-store');
});
it.each(routes)('$name preview cannot mutate or parse body', async route => {
  h.identity = { kind: 'impersonation', userId: id, tenantId: id, impersonationSessionId: id };
  const req = request(route, route.body); const parse = vi.spyOn(req, 'json'); const response = await dispatch(route, req);
  expect(response.status).toBeGreaterThanOrEqual(400); expect(parse).not.toHaveBeenCalled(); expect(h.rpc).not.toHaveBeenCalled();
});
it.each(routes)('$name strict client identity injection has no write', async route => {
  actor(route.member); const response = await dispatch(route, request(route, { ...route.body, tenantId: id })); expect(response.status).toBe(400); expect(h.rpc).not.toHaveBeenCalled();
});
it.each([['GL087','sold_out',409], ['GL086','quote_changed',409], ['GL086','invalid_quantity',422], ['GL086','reservation_limit',429], ['42501','PRIVATE_DETAIL',403], ['XX000','PRIVATE_DETAIL',500]])('reserve safely maps %s/%s', async (code, details, status) => {
  const route = routes[0]; actor(true); h.reply.error = { code, details, message: 'PRIVATE_SQL_MEMBER_STOCK_SECRET' };
  const response = await dispatch(route, request(route, route.body)); expect(response.status).toBe(status); expect(response.headers.get('cache-control')).toBe('no-store');
  expect(JSON.stringify(await response.json())).not.toMatch(/PRIVATE_|GL08|XX000/); expect(h.rpc).toHaveBeenCalledOnce(); expect(h.rpc.mock.calls[0][0]).toBe(route.rpc);
});
it('member cancellation supplies null desk reason and dispatches caller bearer', async () => {
  const route = routes[1]; actor(true); const req = request(route, {}); await dispatch(route, req);
  expect(h.bearer).toHaveBeenCalledWith(req); expect(h.cookie).not.toHaveBeenCalled(); expect(h.rpc).toHaveBeenCalledWith('cancel_shop_reservation', { p_reservation_id: id, p_reason: null });
});
it('fulfil replay returns ordinary sale ids without another route-side mutation', async () => {
  const route = routes[3]; actor(false); h.reply.data = [{ reservation_id: id, order_id: id, payment_id: id, replayed: true }];
  const response = await dispatch(route, request(route, route.body)); expect(response.status).toBe(200); expect(await response.json()).toEqual({ ok: true, data: { reservationId: id, orderId: id, paymentId: id, replayed: true } }); expect(h.rpc).toHaveBeenCalledOnce();
});
