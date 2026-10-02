import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { GymloopIdentity } from '../../lib/identity';

const h = vi.hoisted(() => ({ identity: null as GymloopIdentity | null, rpc: vi.fn(), from: vi.fn(), requestIdentity: vi.fn(), cookieIdentity: vi.fn() }));
vi.mock('../../lib/identity-session', () => ({
  readIdentity: async () => { h.cookieIdentity(); return h.identity ? { identity: h.identity, signedIn: true, authenticatedUser: true, supabase: { rpc: h.rpc, from: h.from } } : null; },
  readRequestIdentity: async (request: Request) => { h.requestIdentity(request); return h.identity ? { identity: h.identity, signedIn: true, authenticatedUser: true, supabase: { rpc: h.rpc, from: h.from } } : null; },
}));
const id = '74000000-0000-4000-8000-000000000001';
const second = '74000000-0000-4000-8000-000000000002';
const owner = { kind: 'staff', role: 'gym_owner', userId: id, tenantId: id, staffId: id } satisfies GymloopIdentity;
const member = { kind: 'member', userId: id, tenantId: id, memberId: second } satisfies GymloopIdentity;
const session = { sessionDate: '2026-10-02', startTime: '18:30', durationMinutes: 60, capacity: 20, trainerStaffId: null };
const service = { name: 'Yoga', description: 'Quiet practice', defaultDurationMinutes: 60, defaultCapacity: 20, sortOrder: 0 };
const modules: Record<string, () => Promise<unknown>> = {
  'class-bookings': () => import('../api/class-bookings/route'),
  'class-bookings/cancel': () => import('../api/class-bookings/cancel/route'),
  'class-bookings/desk': () => import('../api/class-bookings/desk/route'),
  'class-bookings/desk-cancel': () => import('../api/class-bookings/desk-cancel/route'),
  'class-bookings/attendance': () => import('../api/class-bookings/attendance/route'),
  'services': () => import('../api/services/route'),
  'services/[serviceId]': () => import('../api/services/[serviceId]/route'),
  'services/[serviceId]/active': () => import('../api/services/[serviceId]/active/route'),
  'class-rules': () => import('../api/class-rules/route'),
  'class-rules/[ruleId]': () => import('../api/class-rules/[ruleId]/route'),
  'class-sessions': () => import('../api/class-sessions/route'),
  'class-sessions/[sessionId]': () => import('../api/class-sessions/[sessionId]/route'),
  'class-sessions/[sessionId]/cancel': () => import('../api/class-sessions/[sessionId]/cancel/route'),
  'class-settings': () => import('../api/class-settings/route'),
};
const routes = [
  { path: 'class-bookings', method: 'POST', audience: 'member', body: { sessionId: id }, rpc: 'book_class_session', params: {}, failure: 'booking_failed' },
  { path: 'class-bookings/cancel', method: 'POST', audience: 'member', body: { bookingId: id }, rpc: 'cancel_class_booking', params: {}, failure: 'booking_failed' },
  { path: 'class-bookings/desk', method: 'POST', audience: 'front', body: { sessionId: id, memberId: second }, rpc: 'desk_book_class_session', params: {}, failure: 'booking_failed' },
  { path: 'class-bookings/desk-cancel', method: 'POST', audience: 'front', body: { bookingId: id, reason: 'Member asked' }, rpc: 'desk_cancel_class_booking', params: {}, failure: 'booking_failed' },
  { path: 'class-bookings/attendance', method: 'POST', audience: 'staff', body: { bookingId: id, status: 'attended' }, rpc: 'mark_class_attendance', params: {}, failure: 'booking_failed' },
  { path: 'services', method: 'POST', audience: 'owner', body: service, rpc: 'create_service', params: {}, failure: 'class_failed' },
  { path: 'services/[serviceId]', method: 'PUT', audience: 'owner', body: service, rpc: 'update_service', params: { serviceId: id }, failure: 'class_failed' },
  { path: 'services/[serviceId]/active', method: 'POST', audience: 'owner', body: { isActive: false }, rpc: 'set_service_active', params: { serviceId: id }, failure: 'class_failed' },
  { path: 'class-rules', method: 'POST', audience: 'owner', body: { serviceId: id, branchId: second, weekdays: [1, 3], startTime: '18:30', durationMinutes: 60, capacity: 20 }, rpc: 'create_class_rules', params: {}, failure: 'class_failed' },
  { path: 'class-rules/[ruleId]', method: 'PUT', audience: 'owner', body: { durationMinutes: 60, capacity: 20, trainerStaffId: null, validUntil: null, isActive: true }, rpc: 'update_class_rule', params: { ruleId: id }, failure: 'class_failed' },
  { path: 'class-sessions', method: 'POST', audience: 'owner', body: { ...session, trainerStaffId: undefined, serviceId: id, branchId: second }, rpc: 'create_class_session', params: {}, failure: 'class_failed' },
  { path: 'class-sessions/[sessionId]', method: 'PUT', audience: 'owner', body: session, rpc: 'update_class_session', params: { sessionId: id }, failure: 'class_failed' },
  { path: 'class-sessions/[sessionId]/cancel', method: 'POST', audience: 'owner', body: { reason: 'Gym closed' }, rpc: 'cancel_class_session', params: { sessionId: id }, failure: 'class_failed' },
  { path: 'class-settings', method: 'PUT', audience: 'owner', body: { cancelWindowHours: 2, allowCrossBranch: false }, rpc: null, params: {}, failure: 'class_failed' },
] as const;
type Route = (typeof routes)[number];
type Handler = (request: Request, context: { params: Promise<Record<string, string>> }) => Promise<Response>;
async function invoke(route: Route, body: unknown = route.body, bearer = false) {
  const module = await modules[route.path]!() as Record<string, Handler>;
  const request = new Request('https://gym.example/api/classes', { method: route.method, headers: bearer ? { authorization: 'Bearer caller-only' } : {}, body: JSON.stringify(body) });
  return (module[route.method] as Handler)(request, { params: Promise.resolve(route.params) });
}
beforeEach(() => {
  vi.clearAllMocks(); h.identity = owner;
  h.rpc.mockResolvedValue({ data: null, error: { code: 'XX000', message: 'SECRET token tenant-id private error' } });
  h.from.mockImplementation(() => { throw new Error('Unexpected direct write'); });
});

describe.each(routes)('CLS $method $path', (route) => {
  it('identifies caller before reading even a malformed body and is no-store', async () => {
    h.identity = null;
    const module = await modules[route.path]!() as Record<string, Handler>;
    const request = new Request('https://gym.example/api/classes', { method: route.method, body: '{' });
    const json = vi.spyOn(request, 'json');
    const response = await (module[route.method] as Handler)(request, { params: Promise.resolve(route.params) });
    expect(response.status).toBe(401); expect(json).not.toHaveBeenCalled();
    expect(h.rpc).not.toHaveBeenCalled(); expect(h.from).not.toHaveBeenCalled();
    expect(response.headers.get('cache-control')).toBe('no-store');
  });
  it('rejects forged identity fields and malformed JSON without a write', async () => {
    h.identity = route.audience === 'member' ? member : owner;
    const response = await invoke(route, { ...route.body, tenantId: second });
    expect(response.status).toBe(400); expect(await response.json()).toMatchObject({ ok: false, error: { code: 'invalid_request' } });
    expect(h.rpc).not.toHaveBeenCalled(); expect(h.from).not.toHaveBeenCalled();
    const module = await modules[route.path]!() as Record<string, Handler>;
    const malformed = await (module[route.method] as Handler)(new Request('https://gym.example/api/classes', { method: route.method, body: '{' }), { params: Promise.resolve(route.params) });
    expect(malformed.status).toBe(400); expect(h.rpc).not.toHaveBeenCalled(); expect(h.from).not.toHaveBeenCalled();
  });
  it('refuses a complete support preview before body parsing', async () => {
    h.identity = { kind: 'impersonation', userId: id, impersonationSessionId: second, tenantId: id };
    const module = await modules[route.path]!() as Record<string, Handler>;
    const request = new Request('https://gym.example/api/classes', { method: route.method, body: '{' });
    const json = vi.spyOn(request, 'json');
    const response = await (module[route.method] as Handler)(request, { params: Promise.resolve(route.params) });
    expect([401, 403]).toContain(response.status); expect(json).not.toHaveBeenCalled(); expect(h.rpc).not.toHaveBeenCalled(); expect(h.from).not.toHaveBeenCalled();
  });
  it('refuses the wrong member/staff audience before malformed body parsing', async () => {
    h.identity = route.audience === 'member' ? owner : member;
    const module = await modules[route.path]!() as Record<string, Handler>;
    const request = new Request('https://gym.example/api/classes', { method: route.method, body: '{' });
    const json = vi.spyOn(request, 'json');
    const response = await (module[route.method] as Handler)(request, { params: Promise.resolve(route.params) });
    expect([401, 403]).toContain(response.status);
    expect(json).not.toHaveBeenCalled(); expect(h.rpc).not.toHaveBeenCalled(); expect(h.from).not.toHaveBeenCalled();
  });
  if (route.rpc !== null) {
    it.each(['XX000', 'constructor', '__proto__', 'toString'])('fails closed on SQLSTATE %s without leaking details', async (code) => {
      h.identity = route.audience === 'member' ? member : owner;
      h.rpc.mockResolvedValue({ data: null, error: { code, message: 'SECRET caller-only private tenant-id' } });
      const response = await invoke(route);
      expect(response.status).toBe(500);
      const payload = await response.json();
      expect(payload).toMatchObject({ ok: false, error: { code: route.failure } });
      expect(JSON.stringify(payload)).not.toMatch(/SECRET|caller-only|private tenant-id/);
      expect(response.headers.get('cache-control')).toBe('no-store');
      expect(h.rpc).toHaveBeenCalledWith(route.rpc, expect.any(Object));
    });
    it('uses the original bearer request and caller-scoped RPC', async () => {
      h.identity = route.audience === 'member' ? member : owner;
      const response = await invoke(route, route.body, true);
      expect(h.requestIdentity).toHaveBeenCalledOnce(); expect(h.cookieIdentity).not.toHaveBeenCalled();
      expect(h.requestIdentity.mock.calls[0]?.[0].headers.get('authorization')).toBe('Bearer caller-only');
      expect(h.rpc).toHaveBeenCalledWith(route.rpc, expect.any(Object)); expect(response.status).toBe(500);
      expect(h.from).not.toHaveBeenCalled();
    });
  }
  if (route.audience === 'owner' || route.audience === 'front') {
    it('refuses a trainer before parsing or writing', async () => {
      h.identity = { ...owner, role: 'trainer' };
      const module = await modules[route.path]!() as Record<string, Handler>;
      const request = new Request('https://gym.example/api/classes', { method: route.method, body: '{' });
      const json = vi.spyOn(request, 'json');
      const response = await (module[route.method] as Handler)(request, { params: Promise.resolve(route.params) });
      expect(json).not.toHaveBeenCalled();
      expect(response.status).toBe(403); expect(h.rpc).not.toHaveBeenCalled(); expect(h.from).not.toHaveBeenCalled();
    });
  }
});

describe('CLS exact booking DTO and refusals', () => {
  const booking = routes[0];
  it('returns only safe camelCase facts from the member command', async () => {
    h.identity = member;
    h.rpc.mockResolvedValue({ data: [{ booking_id: id, status: 'booked', spots_left: 9 }], error: null });
    const response = await invoke(booking);
    expect(await response.json()).toEqual({ ok: true, data: { bookingId: id, status: 'booked', spotsLeft: 9 } });
    expect(h.rpc).toHaveBeenCalledWith('book_class_session', { p_session_id: id });
  });
  it.each([null, [], [{ booking_id: id, status: 'booked', spots_left: 1 }, { booking_id: second, status: 'booked', spots_left: 1 }], [{ booking_id: 'bad', status: 'booked', spots_left: 1 }], [{ booking_id: id, status: 'active', spots_left: 1 }], [{ booking_id: id, status: 'booked', spots_left: -1 }], [{ booking_id: id, status: 'booked', spots_left: '1' }]].map((data) => [data]))('rejects an ambiguous or malformed success %j', async (data) => {
    h.identity = member; h.rpc.mockResolvedValue({ data, error: null });
    const response = await invoke(booking);
    expect(response.status).toBe(500); expect(await response.json()).toMatchObject({ ok: false, error: { code: 'booking_failed' } });
  });
  it.each([
    ['42501', 404, 'session_not_found'], ['GL090', 409, 'class_full'], ['GL091', 409, 'already_booked'],
    ['GL092', 409, 'not_bookable'], ['GL093', 403, 'membership_not_live'], ['GL094', 409, 'other_branch'],
  ])('maps member booking %s to %s %s', async (sqlstate, status, code) => {
    h.identity = member; h.rpc.mockResolvedValue({ data: null, error: { code: sqlstate, message: 'SECRET' } });
    const response = await invoke(booking); expect(response.status).toBe(status);
    expect(await response.json()).toMatchObject({ ok: false, error: { code } });
  });
  it('keeps activation separate from the exact five editable service fields', async () => {
    h.rpc.mockResolvedValue({ data: null, error: null });
    await invoke(routes[6]);
    expect(h.rpc).toHaveBeenCalledWith('update_service', { p_service_id: id, p_name: 'Yoga', p_description: 'Quiet practice', p_default_duration_minutes: 60, p_default_capacity: 20, p_sort_order: 0 });
    h.rpc.mockClear();
    const response = await invoke(routes[6], { ...service, isActive: false });
    expect(response.status).toBe(400); expect(h.rpc).not.toHaveBeenCalled();
  });
  it.each([
    [1, '42501', 404, 'booking_not_found'], [1, 'GL095', 409, 'cancel_window_closed'], [1, 'GL113', 409, 'booking_not_cancellable'],
    [2, '42501', 404, 'reference_not_found'], [2, 'GL090', 409, 'class_full'], [2, 'GL091', 409, 'already_booked'], [2, 'GL092', 409, 'not_bookable'], [2, 'GL093', 403, 'membership_not_live'], [2, 'GL094', 409, 'other_branch'],
    [3, '42501', 404, 'booking_not_found'], [3, 'GL113', 409, 'booking_not_cancellable'], [3, 'GL111', 409, 'session_not_open'],
    [4, '42501', 404, 'booking_not_found'], [4, 'GL113', 409, 'booking_not_markable'], [4, 'GL111', 409, 'session_not_open'],
    [5, '23505', 409, 'service_name_taken'], [5, 'GL114', 409, 'limit_reached'], [6, '42501', 404, 'service_not_found'], [6, '23505', 409, 'service_name_taken'],
    [8, '42501', 404, 'reference_not_found'], [8, 'GL110', 409, 'service_inactive'], [8, 'GL114', 409, 'limit_reached'], [8, '23505', 409, 'rule_exists'], [8, '22023', 400, 'invalid_request'],
    [9, '42501', 404, 'rule_not_found'], [10, 'GL110', 409, 'service_inactive'], [10, '23505', 409, 'session_exists'],
    [11, 'GL111', 409, 'session_not_open'], [11, 'GL112', 409, 'session_has_bookings'], [12, 'GL111', 409, 'session_not_open'],
  ] as const)('maps route %s SQLSTATE %s to %s %s', async (index, sqlstate, status, code) => {
    const route = routes[index];
    h.identity = route.audience === 'member' ? member : owner;
    h.rpc.mockResolvedValue({ data: null, error: { code: sqlstate, message: 'SECRET' } });
    const response = await invoke(route);
    expect(response.status).toBe(status); expect(await response.json()).toMatchObject({ ok: false, error: { code } });
  });
  it.each([
    [1, [{ booking_id: id, status: 'cancelled_by_member' }], { bookingId: id, status: 'cancelled_by_member' }],
    [2, [{ booking_id: id, status: 'booked', spots_left: 2 }], { bookingId: id, status: 'booked', spotsLeft: 2 }],
    [3, [{ booking_id: id, status: 'cancelled_by_gym' }], { bookingId: id, status: 'cancelled_by_gym' }],
    [4, 'attended', { bookingId: id, status: 'attended' }],
    [5, id, { serviceId: id }], [6, null, { serviceId: id }],
    [7, true, { serviceId: id, isActive: false, changed: true }],
    [8, [{ rule_id: id, weekday: 1, sessions_created: 4 }, { rule_id: second, weekday: 3, sessions_created: 0 }], { rules: [{ ruleId: id, weekday: 1, sessionsCreated: 4 }, { ruleId: second, weekday: 3, sessionsCreated: 0 }] }],
    [9, [{ sessions_created: 2, sessions_updated: 3, sessions_removed: 1, sessions_kept: 4 }], { ruleId: id, sessionsCreated: 2, sessionsUpdated: 3, sessionsRemoved: 1, sessionsKept: 4 }],
    [10, id, { sessionId: id }], [11, null, { sessionId: id }],
    [12, [{ bookings_cancelled: 7, notices_written: 5, notices_withheld: 2, members_without_app: 1 }], { sessionId: id, bookingsCancelled: 7, noticesWritten: 5, noticesWithheld: 2, membersWithoutApp: 1 }],
  ] as const)('returns exact public DTO for route %s', async (index, data, expected) => {
    const route = routes[index]; h.identity = route.audience === 'member' ? member : owner;
    h.rpc.mockResolvedValue({ data, error: null });
    const response = await invoke(route); expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true, data: expected });
  });
  it.each([
    { name: 'missing requested weekday', data: [{ rule_id: id, weekday: 1, sessions_created: 4 }] },
    { name: 'duplicate weekday', data: [{ rule_id: id, weekday: 1, sessions_created: 4 }, { rule_id: second, weekday: 1, sessions_created: 2 }] },
    { name: 'unrequested weekday', data: [{ rule_id: id, weekday: 1, sessions_created: 4 }, { rule_id: second, weekday: 5, sessions_created: 2 }] },
    { name: 'extra result', data: [{ rule_id: id, weekday: 1, sessions_created: 4 }, { rule_id: second, weekday: 3, sessions_created: 2 }, { rule_id: id, weekday: 5, sessions_created: 1 }] },
    { name: 'missing generated count', data: [{ rule_id: id, weekday: 1, sessions_created: 4 }, { rule_id: second, weekday: 3 }] },
  ])('fails closed on rule creation $name without reporting partial success', async ({ data }) => {
    h.rpc.mockResolvedValue({ data, error: null });
    const response = await invoke(routes[8]);
    expect(response.status).toBe(500);
    expect(response.headers.get('cache-control')).toBe('no-store');
    const payload = await response.json();
    expect(payload).toMatchObject({ ok: false, error: { code: 'class_failed' } });
    expect(payload).not.toHaveProperty('data');
    expect(JSON.stringify(payload)).not.toContain(id);
    expect(JSON.stringify(payload)).not.toContain(second);
    expect(h.rpc).toHaveBeenCalledWith('create_class_rules', expect.objectContaining({ p_weekdays: [1, 3] }));
  });
  it.each([
    [{ rule_id: id, weekday: 1, sessions_created: 4 }, { rule_id: second, weekday: 3, sessions_created: 0 }],
    [{ rule_id: second, weekday: 3, sessions_created: 0 }, { rule_id: id, weekday: 1, sessions_created: 4 }],
  ].map((data) => [data]))('accepts exactly all requested rule weekdays regardless of response order %#', async (data) => {
    h.rpc.mockResolvedValue({ data, error: null });
    const response = await invoke(routes[8]);
    expect(response.status).toBe(200);
    expect(response.headers.get('cache-control')).toBe('no-store');
    const payload = await response.json();
    expect(payload.ok).toBe(true);
    expect(payload.data.rules).toHaveLength(2);
    expect(payload.data.rules).toEqual(expect.arrayContaining([{ ruleId: id, weekday: 1, sessionsCreated: 4 }, { ruleId: second, weekday: 3, sessionsCreated: 0 }]));
  });
  it.each([0, 1, 2, 3, 4, 5, 7, 8, 9, 10, 12])('route %s rejects missing or unrecognised RPC facts', async (index) => {
    const route = routes[index]!; h.identity = route.audience === 'member' ? member : owner;
    for (const data of [null, [], [{ private: 'SECRET' }], { private: 'SECRET' }]) {
      h.rpc.mockResolvedValue({ data, error: null });
      const response = await invoke(route); expect(response.status).toBe(500);
      expect(await response.json()).toMatchObject({ ok: false, error: { code: route.failure } });
    }
  });
  it('settings update uses only caller tenant and returns not found for zero rows', async () => {
    const eq = vi.fn(); const update = vi.fn(); const select = vi.fn();
    const outcome = { data: [], error: null };
    const query = {
      update: (...args: unknown[]) => { update(...args); return query; },
      eq: (...args: unknown[]) => { eq(...args); return query; },
      select: (...args: unknown[]) => { select(...args); return query; },
      single: async () => ({ data: null, error: null }),
      maybeSingle: async () => ({ data: null, error: null }),
      then: (resolve: (value: typeof outcome) => unknown) => Promise.resolve(outcome).then(resolve),
    };
    h.from.mockReturnValue(query);
    const response = await invoke(routes[13]);
    expect(response.status).toBe(404); expect(await response.json()).toMatchObject({ ok: false, error: { code: 'settings_not_found' } });
    expect(h.from).toHaveBeenCalledWith('organization_settings');
    expect(update).toHaveBeenCalledWith({ class_cancel_window_hours: 2, class_allow_cross_branch: false });
    expect(eq).toHaveBeenCalledWith('tenant_id', owner.tenantId); expect(h.rpc).not.toHaveBeenCalled();
  });
});


