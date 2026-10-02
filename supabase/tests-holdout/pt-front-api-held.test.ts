import { beforeEach, expect, it, vi } from 'vitest';
import type { Database } from '../../packages/db/types/database';
const h = vi.hoisted(() => ({ identity: null as unknown, rpc: vi.fn(), cookie: vi.fn(), bearer: vi.fn(), reply: { data: null as unknown, error: null as unknown } }));
vi.mock('../../apps/web/lib/identity-session', () => ({ readIdentity: h.cookie, readRequestIdentity: h.bearer }));
vi.mock('../../apps/web/lib/supabase/server', () => ({ createServerSupabase: vi.fn() }));
vi.mock('../../apps/web/lib/supabase/request', () => ({ createRequestSupabase: vi.fn() }));
const ids = { tenant: '73920000-0000-4000-8000-000000000001', user: '73920000-0000-4000-8000-000000000002', member: '73920000-0000-4000-8000-000000000003', staff: '73920000-0000-4000-8000-000000000004', order: '73920000-0000-4000-8000-000000000005', session: '73920000-0000-4000-8000-000000000006' };
const routes: { key: string; load: () => Promise<{ POST: (request: Request) => Promise<Response> }>; rpc: string; member: boolean; roles: Database['public']['Enums']['app_role'][]; body: Record<string, unknown> }[] = [
  { key: 'member-book', load: () => import('../../apps/web/app/api/member/pt-bookings/route'), rpc: 'book_pt_session', member: true, roles: [], body: { orderId: ids.order, sessionId: ids.session, startsAt: '2026-11-06T06:00:00Z' } },
  { key: 'member-cancel', load: () => import('../../apps/web/app/api/member/pt-bookings/cancel/route'), rpc: 'cancel_pt_booking', member: true, roles: [], body: { sessionId: ids.session } },
  { key: 'gym-cancel', load: () => import('../../apps/web/app/api/pt-bookings/cancel/route'), rpc: 'cancel_pt_session_as_gym', member: false, roles: ['gym_owner', 'gym_manager', 'front_desk'], body: { sessionId: ids.session, reason: 'Trainer unavailable' } },
  { key: 'waive', load: () => import('../../apps/web/app/api/pt-forfeits/waive/route'), rpc: 'waive_pt_forfeit', member: false, roles: ['gym_owner', 'gym_manager'], body: { sessionId: ids.session, reason: 'Restore final session' } },
  { key: 'reassign', load: () => import('../../apps/web/app/api/pt-reassignments/route'), rpc: 'reassign_pt_packs', member: false, roles: ['gym_owner', 'gym_manager'], body: { fromStaffId: ids.staff, toStaffId: ids.member, orderIds: [ids.order], reason: 'Trainer leaving' } },
  { key: 'policy', load: () => import('../../apps/web/app/api/pt-policy/route'), rpc: 'set_pt_policy', member: false, roles: ['gym_owner', 'gym_manager'], body: { cancelWindowHours: 12, lateCancelConsumes: true, sessionMinutes: 45 } },
  { key: 'profile', load: () => import('../../apps/web/app/api/trainer-profiles/route'), rpc: 'set_trainer_profile', member: false, roles: ['gym_owner', 'gym_manager'], body: { staffId: ids.staff, bio: 'Strength coach', specialities: ['Strength'], photoAssetId: null, isListed: true } },
  { key: 'own-profile', load: () => import('../../apps/web/app/api/trainer-profiles/own/route'), rpc: 'set_own_trainer_profile', member: false, roles: ['trainer'], body: { bio: 'Strength coach', specialities: ['Strength'] } },
  { key: 'availability', load: () => import('../../apps/web/app/api/trainer-availability/route'), rpc: 'set_trainer_availability', member: false, roles: ['gym_owner', 'gym_manager', 'trainer'], body: { staffId: ids.staff, windows: [{ weekday: 3, startMinute: 360, endMinute: 540 }] } },
  { key: 'time-off', load: () => import('../../apps/web/app/api/trainer-time-off/route'), rpc: 'add_trainer_time_off', member: false, roles: ['gym_owner', 'gym_manager', 'trainer'], body: { staffId: ids.staff, startsOn: '2026-11-04', endsOn: '2026-11-05', reason: 'Unavailable' } },
  { key: 'time-off-remove', load: () => import('../../apps/web/app/api/trainer-time-off/remove/route'), rpc: 'remove_trainer_time_off', member: false, roles: ['gym_owner', 'gym_manager', 'trainer'], body: { timeOffId: ids.order } },
];
beforeEach(() => {
  h.identity = null; h.reply = { data: null, error: null }; h.rpc.mockReset(); h.cookie.mockReset(); h.bearer.mockReset();
  const read = async () => h.identity === null ? null : { identity: h.identity, supabase: { rpc: h.rpc } };
  h.cookie.mockImplementation(read); h.bearer.mockImplementation(read);
  h.rpc.mockImplementation(() => { const result = Promise.resolve(h.reply); return Object.assign(result, { single: async () => h.reply, maybeSingle: async () => h.reply }); });
});
function identity(role: Database['public']['Enums']['app_role'] | 'preview' | undefined) {
  if (role === undefined) throw Error('Missing permitted role in route fixture');
  h.identity = role === 'member' ? { kind: 'member', userId: ids.user, tenantId: ids.tenant, memberId: ids.member } : role === 'preview' ? { kind: 'impersonation', userId: ids.user, tenantId: ids.tenant, role: 'gym_owner' } : { kind: 'staff', userId: ids.user, tenantId: ids.tenant, staffId: ids.staff, role };
}
it.each(routes)('$key authenticates before body and never dispatches unauthenticated', async route => {
  const request = new Request('https://holdout.example/api', { method: 'POST', body: 'malformed' });
  const parse = vi.spyOn(request, 'json'); const response = await (await route.load()).POST(request);
  expect(response.status).toBe(401); expect(response.headers.get('cache-control')).toBe('no-store');
  expect(parse).not.toHaveBeenCalled(); expect(h.rpc).not.toHaveBeenCalled(); expect((await response.json()).ok).toBe(false);
});
it.each(routes)('$key refuses support preview before reading body', async route => {
  identity('preview'); const request = new Request('https://holdout.example/api', { method: 'POST', body: JSON.stringify(route.body) });
  const parse = vi.spyOn(request, 'json'); const response = await (await route.load()).POST(request);
  expect(response.status).toBeGreaterThanOrEqual(400); expect(parse).not.toHaveBeenCalled(); expect(h.rpc).not.toHaveBeenCalled();
  expect(response.headers.get('cache-control')).toBe('no-store');
});
it.each(routes)('$key wrong audience/role refuses with no write', async route => {
  identity(route.member ? 'gym_owner' : route.roles.includes('trainer') ? 'front_desk' : 'trainer'); const response = await (await route.load()).POST(new Request('https://holdout.example/api', { method: 'POST', body: JSON.stringify(route.body) }));
  expect(response.status).toBeGreaterThanOrEqual(400); expect(h.rpc).not.toHaveBeenCalled();
});
it.each(routes)('$key strict extra identity fails before RPC', async route => {
  identity(route.member ? 'member' : route.roles[0]); const response = await (await route.load()).POST(new Request('https://holdout.example/api', { method: 'POST', body: JSON.stringify({ ...route.body, tenantId: ids.tenant }) }));
  expect(response.status).toBe(400); expect(h.rpc).not.toHaveBeenCalled(); expect(response.headers.get('cache-control')).toBe('no-store');
});
it.each(routes)('$key safe pack refusal hides SQL details and writes only via its command', async route => {
  identity(route.member ? 'member' : route.roles[0]); h.reply.error = { code: 'GL055', details: 'order_unavailable', message: `private:${ids.order}:sensitive reason` };
  const response = await (await route.load()).POST(new Request('https://holdout.example/api', { method: 'POST', body: JSON.stringify(route.body) }));
  expect(response.status).toBe(409); expect(response.headers.get('cache-control')).toBe('no-store');
  const body = await response.json(); expect(body).toMatchObject({ ok: false, error: { code: 'pack_unavailable' } });
  expect(JSON.stringify(body)).not.toMatch(/private:|sensitive reason|GL055|order_unavailable/);
  expect(h.rpc).toHaveBeenCalledOnce(); const call = h.rpc.mock.calls[0]; if (call === undefined) throw Error('Missing expected RPC call'); expect(call[0]).toBe(route.rpc);
});
it.each(routes.filter(route => route.member))('$key bearer request passes Request and cannot reuse cookie identity', async route => {
  identity('member'); const request = new Request('https://holdout.example/api', { method: 'POST', headers: { authorization: 'Bearer independent-member-token' }, body: JSON.stringify(route.body) });
  h.reply.error = { code: '42501', message: 'private foreign record' };
  const response = await (await route.load()).POST(request); expect(response.status).toBe(404);
  expect(h.bearer).toHaveBeenCalledWith(request); expect(h.cookie).not.toHaveBeenCalled();
});
it('completed waiver returns exact restored counter and replay without another API-side mutation', async () => {
  identity('gym_manager'); const route = routes.find(item => item.key === 'waive')!;
  h.reply.data = [{ session_id: ids.session, order_id: ids.order, sessions_used: 9, replayed: true }];
  const response = await (await route.load()).POST(new Request('https://holdout.example/api', { method: 'POST', body: JSON.stringify(route.body) }));
  expect(response.status).toBe(200); expect(await response.json()).toEqual({ ok: true, data: { sessionId: ids.session, orderId: ids.order, sessionsUsed: 9, replayed: true } });
  expect(h.rpc).toHaveBeenCalledOnce();
});
