import { beforeEach, describe, expect, it, vi } from 'vitest';

const h = vi.hoisted(() => ({ admitted: true, calls: [] as unknown[], error: null as null | { code: string; details: string; message: string }, data: null as unknown }));
vi.mock('../../lib/api', async (original) => {
  const actual = await original<typeof import('../../lib/api')>();
  const gate = async () => h.admitted ? { session: { supabase: { rpc: async (name: string, args: unknown) => { h.calls.push({ name, args }); return { data: h.data, error: h.error }; } }, userId: '73000000-0000-4000-8000-000000000003', tenantId: '73000000-0000-4000-8000-000000000004', staffId: '73000000-0000-4000-8000-000000000005', memberId: '73000000-0000-4000-8000-000000000006', role: 'gym_owner' } } : { failure: actual.apiFail('unauthorized', 'not_signed_in', 'Sign in first.') };
  return { ...actual, memberSession: vi.fn(gate), staffSession: vi.fn(gate) };
});
const id = '73000000-0000-4000-8000-000000000001';
const sessionId = '73000000-0000-4000-8000-000000000002';
const startsAt = '2026-10-04T10:00:00+05:30';
const routes = {
  'member/pt-bookings': () => import('../api/member/pt-bookings/route'),
  'member/pt-bookings/cancel': () => import('../api/member/pt-bookings/cancel/route'),
  'pt-forfeits/waive': () => import('../api/pt-forfeits/waive/route'),
  'pt-bookings/cancel': () => import('../api/pt-bookings/cancel/route'),
  'trainer-profiles': () => import('../api/trainer-profiles/route'),
  'trainer-profiles/own': () => import('../api/trainer-profiles/own/route'),
  'trainer-availability': () => import('../api/trainer-availability/route'),
  'trainer-time-off': () => import('../api/trainer-time-off/route'),
  'trainer-time-off/remove': () => import('../api/trainer-time-off/remove/route'),
  'pt-reassignments': () => import('../api/pt-reassignments/route'),
  'pt-policy': () => import('../api/pt-policy/route'),
};
const cases = [
  { path: 'member/pt-bookings', body: { orderId: id, sessionId, startsAt }, rpc: 'book_pt_session', args: { p_order_id: id, p_session_id: sessionId, p_starts_at: startsAt }, row: { session_id: sessionId, order_id: id, starts_at: startsAt, ends_at: '2026-10-04T11:00:00+05:30', status: 'booked', in_cancel_window: false, replayed: true }, data: { sessionId, orderId: id, startsAt, endsAt: '2026-10-04T11:00:00+05:30', status: 'booked', inCancelWindow: false, replayed: true } },
  { path: 'member/pt-bookings/cancel', body: { sessionId }, rpc: 'cancel_pt_booking', args: { p_session_id: sessionId }, row: { session_id: sessionId, status: 'cancelled_by_member', late: true, consumed: true, sessions_remaining: 7, replayed: false }, data: { sessionId, status: 'cancelled_by_member', late: true, consumed: true, sessionsRemaining: 7, replayed: false } },
  { path: 'pt-forfeits/waive', body: { sessionId, reason: 'Desk correction' }, rpc: 'waive_pt_forfeit', args: { p_session_id: sessionId, p_reason: 'Desk correction' }, row: { session_id: sessionId, order_id: id, sessions_used: 9, replayed: false }, data: { sessionId, orderId: id, sessionsUsed: 9, replayed: false } },
  { path: 'pt-bookings/cancel', body: { sessionId, reason: 'Trainer away' }, rpc: 'cancel_pt_session_as_gym', args: { p_session_id: sessionId, p_reason: 'Trainer away' }, row: { session_id: sessionId, status: 'cancelled_by_gym', replayed: false }, data: { sessionId, status: 'cancelled_by_gym', replayed: false } },
  { path: 'trainer-profiles', body: { staffId: id, bio: 'Strength', specialities: ['Mobility'], photoAssetId: null, isListed: true }, rpc: 'set_trainer_profile', args: { p_staff_id: id, p_bio: 'Strength', p_specialities: ['Mobility'], p_photo_asset_id: null, p_is_listed: true }, row: id, data: { profileId: id } },
  { path: 'trainer-profiles/own', body: { bio: 'Strength', specialities: ['Mobility'] }, rpc: 'set_own_trainer_profile', args: { p_bio: 'Strength', p_specialities: ['Mobility'] }, row: id, data: { profileId: id } },
  { path: 'trainer-availability', body: { staffId: id, windows: [{ weekday: 1, startMinute: 360, endMinute: 420 }] }, rpc: 'set_trainer_availability', args: { p_staff_id: id, p_windows: [{ weekday: 1, startMinute: 360, endMinute: 420 }] }, row: 1, data: { windows: 1 } },
  { path: 'trainer-time-off', body: { staffId: id, startsOn: '2026-10-06', endsOn: '2026-10-07', reason: 'Leave' }, rpc: 'add_trainer_time_off', args: { p_staff_id: id, p_starts_on: '2026-10-06', p_ends_on: '2026-10-07', p_reason: 'Leave' }, row: sessionId, data: { timeOffId: sessionId } },
  { path: 'trainer-time-off/remove', body: { timeOffId: sessionId }, rpc: 'remove_trainer_time_off', args: { p_time_off_id: sessionId }, row: null, data: { removed: true } },
  { path: 'pt-reassignments', body: { fromStaffId: id, toStaffId: sessionId, orderIds: [id], reason: 'Trainer leaving' }, rpc: 'reassign_pt_packs', args: { p_from_staff_id: id, p_to_staff_id: sessionId, p_order_ids: [id], p_reason: 'Trainer leaving' }, row: [{ order_id: id, changed: true, cancelled_sessions: 2 }], data: { results: [{ orderId: id, changed: true, cancelledSessions: 2 }] } },
  { path: 'pt-policy', body: { cancelWindowHours: 24, lateCancelConsumes: true, sessionMinutes: 60 }, rpc: 'set_pt_policy', args: { p_cancel_window_hours: 24, p_late_cancel_consumes: true, p_session_minutes: 60 }, row: null, data: { saved: true } },
] as const;
beforeEach(() => { h.admitted = true; h.calls = []; h.error = null; h.data = null; });
describe('PTF-027 request boundary, independently authored', () => {
  for (const entry of cases) {
    it(`${entry.path}: authentication precedes unreadable body`, async () => {
      h.admitted = false;
      const { POST } = await routes[entry.path]();
      const request = new Request(`https://gymloop.example/api/${entry.path}`, { method: 'POST', body: '{' });
      const read = vi.spyOn(request, 'json');
      const response = await POST(request);
      expect(response.status).toBe(401); expect(read).not.toHaveBeenCalled(); expect(h.calls).toEqual([]);
      expect(response.headers.get('cache-control')).toBe('no-store');
    });
    it(`${entry.path}: exact RPC and public replay envelope`, async () => {
      h.data = Array.isArray(entry.row) || entry.row === null || typeof entry.row !== 'object' ? entry.row : [{ ...entry.row, tenant_id: id, private_note: 'do not expose' }];
      const { POST } = await routes[entry.path]();
      const response = await POST(new Request(`https://gymloop.example/api/${entry.path}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(entry.body) }));
      expect(h.calls).toEqual([{ name: entry.rpc, args: entry.args }]);
      expect(await response.json()).toEqual({ ok: true, data: entry.data });
      expect(response.headers.get('cache-control')).toBe('no-store');
    });
    it(`${entry.path}: extra tenant authority is rejected without RPC`, async () => {
      const { POST } = await routes[entry.path]();
      const response = await POST(new Request(`https://gymloop.example/api/${entry.path}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ ...entry.body, tenantId: id }) }));
      expect(response.status).toBe(400); expect(h.calls).toEqual([]);
    });
  }
  it.each([['GL096', '', 409, 'slot_taken'], ['GL055', 'order_unavailable', 409, 'pack_unavailable'], ['42501', 'private member', 404, 'not_found'], ['XX000', 'secret key', 500, 'pt_failed']])('PTF-027 %s detail never leaks', async (code, details, status, publicCode) => {
    h.error = { code, details, message: `private ${id}` };
    const { POST } = await import('../api/member/pt-bookings/route');
    const response = await POST(new Request('https://gymloop.example/api/member/pt-bookings', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(cases[0].body) }));
    expect(response.status).toBe(status);
    const body = await response.json(); expect(body).toMatchObject({ ok: false, error: { code: publicCode } });
    expect(JSON.stringify(body)).not.toContain(id); expect(JSON.stringify(body)).not.toContain(details || 'private');
  });
});
