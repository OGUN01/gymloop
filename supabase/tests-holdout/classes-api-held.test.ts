// Independent CLS app boundary suite. Real api.ts sessions, mocked identity I/O.
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { GymloopIdentity, StaffRole } from '../../packages/shared/src/api/identity';

const h = vi.hoisted(() => ({ caller: null as unknown, rpc: vi.fn(), from: vi.fn(), events: [] as string[] }));
vi.mock('../../apps/web/lib/identity-session', () => ({
  readIdentity: async () => { h.events.push('identity'); return h.caller; },
  readRequestIdentity: async () => { h.events.push('identity'); return h.caller; },
}));
vi.mock('../../apps/web/lib/supabase/server', () => ({ createServerSupabase: vi.fn(() => { throw new Error('Unexpected client'); }) }));
vi.mock('../../apps/web/lib/supabase/request', () => ({ createRequestSupabase: vi.fn(() => { throw new Error('Unexpected client'); }) }));
vi.mock('../../apps/web/lib/observability', () => ({ createOperationalLogger: () => ({ error: vi.fn() }) }));

const id = '74900000-0000-4000-8000-000000000001';
const owner = ['gym_owner', 'gym_manager'];
const desk = [...owner, 'front_desk'];
const allStaff = [...desk, 'trainer'];
const service = { name: 'Yoga', defaultDurationMinutes: 45, defaultCapacity: 10 };
const session = { serviceId: id, branchId: id, sessionDate: '2026-10-10', startTime: '18:00', durationMinutes: 45, capacity: 10 };
const routes = [
  { path: 'class-bookings', method: 'POST', roles: ['member'], body: { sessionId: id }, rpc: 'book_class_session' },
  { path: 'class-bookings/cancel', method: 'POST', roles: ['member'], body: { bookingId: id }, rpc: 'cancel_class_booking' },
  { path: 'class-bookings/desk', method: 'POST', roles: desk, body: { sessionId: id, memberId: id }, rpc: 'desk_book_class_session' },
  { path: 'class-bookings/desk-cancel', method: 'POST', roles: desk, body: { bookingId: id, reason: 'Requested' }, rpc: 'desk_cancel_class_booking' },
  { path: 'class-bookings/attendance', method: 'POST', roles: allStaff, body: { bookingId: id, status: 'attended' }, rpc: 'mark_class_attendance' },
  { path: 'services', method: 'POST', roles: owner, body: service, rpc: 'create_service' },
  { path: 'services/[serviceId]', method: 'PUT', roles: owner, body: service, rpc: 'update_service' },
  { path: 'services/[serviceId]/active', method: 'POST', roles: owner, body: { isActive: false }, rpc: 'set_service_active' },
  { path: 'class-rules', method: 'POST', roles: owner, body: { serviceId: id, branchId: id, weekdays: [1], startTime: '18:00', durationMinutes: 45, capacity: 10 }, rpc: 'create_class_rules' },
  { path: 'class-rules/[ruleId]', method: 'PUT', roles: owner, body: { durationMinutes: 45, capacity: 10, trainerStaffId: null, validUntil: null, isActive: true }, rpc: 'update_class_rule' },
  { path: 'class-sessions', method: 'POST', roles: owner, body: session, rpc: 'create_class_session' },
  { path: 'class-sessions/[sessionId]', method: 'PUT', roles: owner, body: { sessionDate: '2026-10-10', startTime: '18:00', durationMinutes: 45, capacity: 10, trainerStaffId: null }, rpc: 'update_class_session' },
  { path: 'class-sessions/[sessionId]/cancel', method: 'POST', roles: owner, body: { reason: 'Instructor unwell' }, rpc: 'cancel_class_session' },
  { path: 'class-settings', method: 'PUT', roles: owner, body: { cancelWindowHours: 2, allowCrossBranch: false }, rpc: null },
];
function caller(role: string) {
  const identity: GymloopIdentity = role === 'member'
    ? { kind: 'member', userId: id, tenantId: id, memberId: id }
    : role === 'preview'
      ? { kind: 'impersonation', userId: id, tenantId: id, impersonationSessionId: id }
      : role === 'unlinked'
        ? { kind: 'unlinked' }
        : role === 'super_admin' || role === 'platform_support'
          ? { kind: 'platform', userId: id, role }
          : { kind: 'staff', userId: id, tenantId: id, staffId: id, role: role as StaffRole };
  h.caller = { supabase: { rpc: h.rpc, from: h.from }, signedIn: true, authenticatedUser: true, identity };
}

async function run(route: typeof routes[number], body: unknown = route.body) {
  const imports: Record<string, () => Promise<unknown>> = {
    'class-bookings': () => import('../../apps/web/app/api/class-bookings/route'),
    'class-bookings/cancel': () => import('../../apps/web/app/api/class-bookings/cancel/route'),
    'class-bookings/desk': () => import('../../apps/web/app/api/class-bookings/desk/route'),
    'class-bookings/desk-cancel': () => import('../../apps/web/app/api/class-bookings/desk-cancel/route'),
    'class-bookings/attendance': () => import('../../apps/web/app/api/class-bookings/attendance/route'),
    services: () => import('../../apps/web/app/api/services/route'),
    'services/[serviceId]': () => import('../../apps/web/app/api/services/[serviceId]/route'),
    'services/[serviceId]/active': () => import('../../apps/web/app/api/services/[serviceId]/active/route'),
    'class-rules': () => import('../../apps/web/app/api/class-rules/route'),
    'class-rules/[ruleId]': () => import('../../apps/web/app/api/class-rules/[ruleId]/route'),
    'class-sessions': () => import('../../apps/web/app/api/class-sessions/route'),
    'class-sessions/[sessionId]': () => import('../../apps/web/app/api/class-sessions/[sessionId]/route'),
    'class-sessions/[sessionId]/cancel': () => import('../../apps/web/app/api/class-sessions/[sessionId]/cancel/route'),
    'class-settings': () => import('../../apps/web/app/api/class-settings/route'),
  };
  const module = await imports[route.path]!() as Record<string, (request: Request, context: unknown) => Promise<Response>>;
  const request = new Request('https://gymloop.test/api/' + route.path.replace(/\[\w+\]/g, id), {
    method: route.method, headers: { 'content-type': 'application/json', authorization: 'Bearer held-caller-jwt' }, body: JSON.stringify(body),
  });
  const json = request.json.bind(request);
  vi.spyOn(request, 'json').mockImplementation(() => { h.events.push('body'); return json(); });
  const response = await module[route.method]!(request, { params: Promise.resolve({ serviceId: id, ruleId: id, sessionId: id }) });
  return { response, json: await response.json() };
}
beforeEach(() => {
  h.caller = null; h.events = []; h.rpc.mockReset(); h.from.mockReset();
  h.rpc.mockResolvedValue({ data: null, error: { code: 'held_unmapped', message: `private ${id} held-caller-jwt` } });
});
describe('CLS all public route authorization and dispatch boundaries', () => {
  for (const route of routes) {
    it(`${route.path} authenticates before body, even malformed input`, async () => {
      const { response } = await run(route, null);
      expect(response.status).toBe(401);
      expect(h.events).toEqual(['identity']);
      expect(h.rpc).not.toHaveBeenCalled(); expect(h.from).not.toHaveBeenCalled();
      expect(response.headers.get('cache-control')).toBe('no-store');
    });
    for (const role of ['member', 'gym_owner', 'gym_manager', 'front_desk', 'trainer', 'super_admin', 'platform_support', 'preview', 'unlinked']) {
      if (route.roles.includes(role)) continue;
      it(`${route.path} rejects ${role} before inspecting body`, async () => {
        caller(role);
        const { response } = await run(route, null);
        expect([401, 403]).toContain(response.status);
        expect(response.headers.get('cache-control')).toBe('no-store');
        expect(h.events).toEqual(['identity']);
        expect(h.rpc).not.toHaveBeenCalled(); expect(h.from).not.toHaveBeenCalled();
      });
    }
    it(`${route.path} rejects identity injection without a dispatch`, async () => {
      caller(route.roles[0]!);
      const { response, json } = await run(route, { ...route.body, tenantId: id });
      expect(response.status).toBe(400); expect(json.error.code).toBe('invalid_request');
      expect(h.rpc).not.toHaveBeenCalled(); expect(h.from).not.toHaveBeenCalled();
      expect(h.events).toEqual(['identity', 'body']);
    });
    if (route.rpc) it(`${route.path} dispatches through caller client and hides unexpected error`, async () => {
      caller(route.roles[0]!);
      const { response, json } = await run(route);
      expect(h.rpc).toHaveBeenCalledWith(route.rpc, expect.any(Object));
      expect(response.status).toBe(500);
      expect(response.headers.get('cache-control')).toBe('no-store');
      expect(json.ok).toBe(false);
      expect(JSON.stringify(json)).not.toContain(id);
      expect(JSON.stringify(json)).not.toContain('held-caller-jwt');
    });
    if (route.rpc && route.path !== 'services/[serviceId]' && route.path !== 'class-sessions/[sessionId]') {
      for (const data of [null, [], [{ unexpected: id }, { unexpected: id }]]) {
        it(`${route.path} fails closed for malformed successful RPC data ${JSON.stringify(data)}`, async () => {
          caller(route.roles[0]!); h.rpc.mockResolvedValue({ data, error: null });
          const { response, json } = await run(route);
          expect(response.status).toBe(500); expect(json.ok).toBe(false);
          expect(response.headers.get('cache-control')).toBe('no-store');
        });
      }
    }
  }
  // CLS-004 returns exactly one rule per requested weekday; CLS-030 rejects partial success.
  const createRules = routes[8]!;
  const ruleRows = {
    monday: { rule_id: id, weekday: 1, sessions_created: 4 },
    wednesday: { rule_id: '74900000-0000-4000-8000-000000000003', weekday: 3, sessions_created: 0 },
    extra: { rule_id: '74900000-0000-4000-8000-000000000005', weekday: 5, sessions_created: 2 },
  };
  for (const [label, rows] of [
    ['missing Wednesday', [ruleRows.monday]],
    ['missing Monday', [ruleRows.wednesday]],
    ['missing both weekdays', []],
    ['duplicate Monday replaces Wednesday', [ruleRows.monday, { ...ruleRows.monday, rule_id: ruleRows.extra.rule_id }]],
    ['duplicate Wednesday replaces Monday', [ruleRows.wednesday, { ...ruleRows.wednesday, rule_id: ruleRows.extra.rule_id }]],
    ['extra duplicate weekday', [ruleRows.monday, ruleRows.wednesday, { ...ruleRows.wednesday, rule_id: ruleRows.extra.rule_id }]],
    ['unrequested weekday replaces Wednesday', [ruleRows.monday, ruleRows.extra]],
    ['extra unrequested weekday', [ruleRows.monday, ruleRows.wednesday, ruleRows.extra]],
  ] as const) it(`rule creation fails closed for ${label}`, async () => {
    caller('gym_manager'); h.rpc.mockResolvedValue({ data: rows, error: null });
    const { response, json } = await run(createRules, { ...createRules.body, weekdays: [1, 3] });
    expect(response.status).toBe(500); expect(json.ok).toBe(false); expect(json.error.code).toBe('class_failed');
    expect(response.headers.get('cache-control')).toBe('no-store');
    expect(h.events).toEqual(['identity', 'body']);
    expect(h.rpc).toHaveBeenCalledTimes(1);
    expect(h.rpc).toHaveBeenCalledWith('create_class_rules', expect.objectContaining({ p_weekdays: [1, 3] }));
    expect(h.from).not.toHaveBeenCalled();
    for (const secret of [id, ruleRows.wednesday.rule_id, ruleRows.extra.rule_id, 'held-caller-jwt']) {
      expect(JSON.stringify(json)).not.toContain(secret);
    }
    expect(json).not.toHaveProperty('data');
  });
  for (const [label, rows] of [
    ['requested order', [ruleRows.monday, ruleRows.wednesday]],
    ['legitimate unsorted result', [ruleRows.wednesday, ruleRows.monday]],
  ] as const) it(`rule creation accepts exact weekday coverage in ${label}`, async () => {
    caller('gym_manager'); h.rpc.mockResolvedValue({ data: rows, error: null });
    const { response, json } = await run(createRules, { ...createRules.body, weekdays: [1, 3] });
    expect(response.status).toBe(200); expect(json.ok).toBe(true);
    expect(json.data.rules).toHaveLength(2);
    expect(json.data.rules).toEqual(expect.arrayContaining([
      { ruleId: id, weekday: 1, sessionsCreated: 4 },
      { ruleId: ruleRows.wednesday.rule_id, weekday: 3, sessionsCreated: 0 },
    ]));
    expect(response.headers.get('cache-control')).toBe('no-store');
    expect(h.events).toEqual(['identity', 'body']);
    expect(h.rpc).toHaveBeenCalledTimes(1);
    expect(h.rpc).toHaveBeenCalledWith('create_class_rules', expect.objectContaining({ p_weekdays: [1, 3] }));
    expect(h.from).not.toHaveBeenCalled();
  });
  const book = routes[0]!;
  for (const [code, status, refusal] of [
    ['42501', 404, 'session_not_found'], ['GL090', 409, 'class_full'], ['GL091', 409, 'already_booked'],
    ['GL092', 409, 'not_bookable'], ['GL093', 403, 'membership_not_live'], ['GL094', 409, 'other_branch'],
    ['constructor', 500, 'booking_failed'], ['__proto__', 500, 'booking_failed'], ['GL096', 500, 'booking_failed'],
  ] as const) it(`booking maps ${code} with own-key safe lookup`, async () => {
    caller('member'); h.rpc.mockResolvedValue({ data: null, error: { code, message: 'private database detail' } });
    const { response, json } = await run(book);
    expect(response.status).toBe(status); expect(json.error.code).toBe(refusal);
    expect(JSON.stringify(json)).not.toContain('private database detail');
  });
  for (const data of [null, [], [{ booking_id: id, status: 'booked', spots_left: 1 }, { booking_id: id, status: 'booked', spots_left: 1 }], [{ booking_id: id, status: 'invented', spots_left: 1 }], [{ booking_id: id, status: 'booked', spots_left: -1 }]]) {
    it(`booking fails closed on bad RPC result ${JSON.stringify(data)}`, async () => {
      caller('member'); h.rpc.mockResolvedValue({ data, error: null });
      const { response, json } = await run(book);
      expect(response.status).toBe(500); expect(json.error.code).toBe('booking_failed');
    });
  }
  for (const [code, status, refusal] of [
    ['42501', 404, 'booking_not_found'], ['GL095', 409, 'cancel_window_closed'],
    ['GL113', 409, 'booking_not_cancellable'], ['constructor', 500, 'booking_failed'],
  ] as const) it(`member cancellation maps ${code} without leaking detail`, async () => {
    caller('member'); h.rpc.mockResolvedValue({ data: null, error: { code, message: 'private held cancellation detail' } });
    const { response, json } = await run(routes[1]!);
    expect(response.status).toBe(status); expect(json.error.code).toBe(refusal);
    expect(response.headers.get('cache-control')).toBe('no-store');
    expect(JSON.stringify(json)).not.toContain('private held cancellation detail');
  });
  it('each mutation uses the current caller client rather than retaining an earlier client', async () => {
    caller('member');
    h.rpc.mockResolvedValue({ data: [{ booking_id: id, status: 'booked', spots_left: 0 }], error: null });
    await run(book);
    const nextRpc = vi.fn().mockResolvedValue({ data: null, error: { code: 'GL090' } });
    const identity: GymloopIdentity = { kind: 'member', userId: id, tenantId: id, memberId: id };
    h.caller = { supabase: { rpc: nextRpc, from: h.from }, signedIn: true, authenticatedUser: true, identity };
    const { response, json } = await run(book);
    expect(nextRpc).toHaveBeenCalledWith('book_class_session', { p_session_id: id });
    expect(h.rpc).toHaveBeenCalledTimes(1);
    expect(response.status).toBe(409); expect(json.error.code).toBe('class_full');
    expect(response.headers.get('cache-control')).toBe('no-store');
  });
  it('booking returns truthful data and no inferred attendance dispatch', async () => {
    caller('member'); h.rpc.mockResolvedValue({ data: [{ booking_id: id, status: 'booked', spots_left: 0 }], error: null });
    const { response, json } = await run(book);
    expect(response.status).toBe(200); expect(json).toEqual({ ok: true, data: { bookingId: id, status: 'booked', spotsLeft: 0 } });
    expect(h.rpc).toHaveBeenCalledTimes(1); expect(h.rpc).toHaveBeenCalledWith('book_class_session', { p_session_id: id });
    expect(h.from).not.toHaveBeenCalled();
  });
  it('cancellation returns separate honest in-app and no-app counts', async () => {
    caller('gym_owner');
    h.rpc.mockResolvedValue({ data: [{ bookings_cancelled: 7, notices_written: 5, notices_withheld: 2, members_without_app: 3 }], error: null });
    const { response, json } = await run(routes[12]!);
    expect(response.status).toBe(200);
    expect(json).toEqual({ ok: true, data: { sessionId: id, bookingsCancelled: 7, noticesWritten: 5, noticesWithheld: 2, membersWithoutApp: 3 } });
  });
  it('rule update reports created updated removed and kept independently', async () => {
    caller('gym_manager');
    h.rpc.mockResolvedValue({ data: [{ sessions_created: 2, sessions_updated: 3, sessions_removed: 4, sessions_kept: 5 }], error: null });
    const { response, json } = await run(routes[9]!);
    expect(response.status).toBe(200);
    expect(json).toEqual({ ok: true, data: { ruleId: id, sessionsCreated: 2, sessionsUpdated: 3, sessionsRemoved: 4, sessionsKept: 5 } });
  });
});
