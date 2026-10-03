import { describe, expect, it, vi } from 'vitest';

type Section = { data: unknown; error: string | null };
type Adapter = (...args: unknown[]) => Promise<Section>;
const targetPath = '../../apps/web/lib/training-console';
async function target(name: string): Promise<Adapter> {
  const module = await import(targetPath).catch(() => ({})) as Record<string, unknown>;
  expect(module[name], `Frozen console adapter ${name} must exist`).toBeTypeOf('function');
  return module[name] as Adapter;
}
const ids = { tenant: '80100000-0000-4000-8000-000000000001', actor: '80100000-0000-4000-8000-000000000002', staff: '80100000-0000-4000-8000-000000000003', other: '80100000-0000-4000-8000-000000000004' };
function caller(role = 'gym_owner') {
  return { identity: { kind: 'staff', userId: ids.actor, tenantId: ids.tenant, staffId: ids.staff, role }, viewer: { role, staffId: ids.staff, readOnly: false, scopeKey: `${ids.tenant}:${ids.staff}:${role}` } };
}
const preview = { identity: { kind: 'impersonation', userId: ids.actor, tenantId: ids.tenant, impersonationSessionId: ids.other }, viewer: { role: null, staffId: null, readOnly: true, scopeKey: 'preview-session' } };
function database(rows: Record<string, unknown[]> = {}, rpcReply: (name: string, args: Record<string, unknown>) => unknown = () => ({ data: [], error: null })) {
  const calls: { table: string; method: string; args: unknown[] }[] = [];
  const rpc = vi.fn(async (name: string, args: Record<string, unknown>) => rpcReply(name, args));
  const from = vi.fn((table: string) => {
    const builder: Record<string, unknown> = {};
    for (const method of ['select', 'eq', 'in', 'is', 'order', 'range', 'limit', 'gt', 'gte', 'lt', 'lte']) {
      builder[method] = (...args: unknown[]) => { calls.push({ table, method, args }); return builder; };
    }
    const result = { data: rows[table] ?? [], error: null };
    builder.then = (resolve: (value: unknown) => unknown) => Promise.resolve(result).then(resolve);
    builder.maybeSingle = async () => ({ data: rows[table]?.[0] ?? null, error: null });
    builder.single = builder.maybeSingle;
    return builder;
  });
  return { client: { from, rpc }, calls, from, rpc };
}
function pack(order_id: string, state = 'live', sessions_scheduled = 2) {
  return { order_id, state, sessions_scheduled, member_code: 'H-17', member_id: ids.other, member_name: 'Held member', programme_name: 'Sold programme', sessions_total: 8, sessions_used: 1, sessions_remaining: 5, starts_on: '2027-01-01', expires_on: '2027-06-01', timezone: 'Asia/Kolkata', trainer_active: true, trainer_name: 'Held trainer', trainer_staff_id: ids.staff };
}
const range = { p_from: '2027-01-01T00:00:00Z', p_to: '2027-01-02T00:00:00Z' };

describe('held PTF console verified caller refusal before reads', () => {
  it.each(['loadPtBookings', 'loadPtPacks', 'loadTrainerChoices', 'loadPtPolicy', 'loadReassignmentCandidates', 'loadTimeOffBookings'])('%s rejects an unsupported role before touching data', async name => {
    const load = await target(name); const db = database();
    await load(db.client, caller('accountant'), range, ids.staff, '2027-01-01', '2027-01-02', 'Asia/Kolkata').catch(() => null);
    expect(db.from).not.toHaveBeenCalled(); expect(db.rpc).not.toHaveBeenCalled();
  });
  it.each(['loadPtBookings', 'loadPtPacks', 'loadTrainerChoices', 'loadPtPolicy', 'loadReassignmentCandidates', 'loadTimeOffBookings'])('%s cannot acquire owner authority from viewer props', async name => {
    const load = await target(name); const db = database(); const forged = caller('trainer'); forged.viewer.role = 'gym_owner';
    await load(db.client, forged, range, ids.staff, '2027-01-01', '2027-01-02', 'Asia/Kolkata').catch(() => null);
    expect(db.from).not.toHaveBeenCalled(); expect(db.rpc).not.toHaveBeenCalled();
  });
  it('trainer detail refuses another trainer before feature access', async () => {
    const load = await target('loadTrainerDetail'); const db = database();
    await load(db.client, caller('trainer'), ids.other).catch(() => null);
    expect(db.from).not.toHaveBeenCalled(); expect(db.rpc).not.toHaveBeenCalled();
  });
  it.each(['loadPtPolicy', 'loadReassignmentCandidates'])('%s refuses front desk before privileged projections', async name => {
    const load = await target(name); const db = database(); await load(db.client, caller('front_desk'), ids.staff).catch(() => null);
    expect(db.from).not.toHaveBeenCalled(); expect(db.rpc).not.toHaveBeenCalled();
  });
  it('preview cannot prepare a mutable reassignment', async () => {
    const load = await target('loadReassignmentCandidates'); const db = database(); await load(db.client, preview, ids.staff).catch(() => null);
    expect(db.from).not.toHaveBeenCalled(); expect(db.rpc).not.toHaveBeenCalled();
  });
  it.each([{ ...range, p_status: 'scheduled' }, { ...range, p_after_id: ids.other }, { ...range, p_from: 'not-a-date' }, { ...range, p_to: '2028-01-01T00:00:00Z' }])('invalid booking filters never reach an RPC: %j', async args => {
    const load = await target('loadPtBookings'); const db = database(); await load(db.client, caller(), args).catch(() => null); expect(db.rpc).not.toHaveBeenCalled();
  });
});

describe('held console exact public read facts', () => {
  it.each(['gym_owner', 'manager', 'front_desk', 'trainer'])('bookings preserve nullable cancellation and exact balances for %s', async role => {
    const load = await target('loadPtBookings'); const row = { session_id: ids.other, cancelled_at: null, status: 'booked', sessions_total: 8, sessions_used: 1, sessions_remaining: 5 };
    const db = database({}, () => ({ data: [row], error: null })); const result = await load(db.client, caller(role), range);
    expect(result).toEqual({ data: [row], error: null }); expect(db.rpc.mock.calls[0]?.[0]).toBe('read_pt_bookings');
    expect(db.from).not.toHaveBeenCalled();
    if (role === 'trainer') expect(db.rpc.mock.calls[0]?.[1]).toMatchObject({ p_trainer_staff_id: ids.staff });
  });
  it.each([undefined, 0, 900])('pack limit %s clamps within RPC page range', async p_limit => {
    const load = await target('loadPtPacks'); const db = database(); await load(db.client, caller(), { p_limit });
    const limit = db.rpc.mock.calls[0]?.[1].p_limit; expect(limit).toBeGreaterThanOrEqual(1); expect(limit).toBeLessThanOrEqual(50);
  });
  it('backend failures are sanitized and do not become empty success', async () => {
    const load = await target('loadPtBookings'); const db = database({}, () => ({ data: null, error: { message: 'secret-key contact@example.com SQL internal', code: 'XX000' } }));
    const result = await load(db.client, caller(), range); expect(result.data).toBeNull(); expect(result.error).toBeTruthy(); expect(result.error).not.toMatch(/secret-key|contact@|SQL internal/);
  });
  it('absent policy is a failed read rather than editable defaults', async () => {
    const load = await target('loadPtPolicy'); const result = await load(database().client, caller()); expect(result.data).toBeNull(); expect(result.error).toBeTruthy();
  });
  it('trainer choices strip contact identifiers and resolve branch fallback', async () => {
    const load = await target('loadTrainerChoices'); const db = database({ staff: [{ id: ids.staff, full_name: 'Held trainer', is_active: true, qualification: 'CPT', branch_id: null, email: 'private@example.com', phone: 'SECRET_PHONE', user_id: 'SECRET_USER' }], organizations: [{ timezone: 'Asia/Kolkata' }], branches: [] });
    const result = await load(db.client, caller()); expect(result.data).toEqual([{ staffId: ids.staff, displayName: 'Held trainer', isActive: true, qualification: 'CPT', timezone: 'Asia/Kolkata', branchName: null }]);
    for (const call of db.calls.filter(item => item.method === 'select')) expect(String(call.args[0])).not.toMatch(/\*|email|phone|user_id/);
    expect(db.calls).toContainEqual({ table: 'staff', method: 'eq', args: ['role', 'trainer'] });
  });
});

describe('held exact ACTIVE reassignment set', () => {
  it.each(['gym_owner', 'manager'])('intersects complete RPC PT ids with underlying ACTIVE for %s', async role => {
    const load = await target('loadReassignmentCandidates'); const a = '80100000-0000-4000-8000-000000000010'; const b = '80100000-0000-4000-8000-000000000011'; const c = '80100000-0000-4000-8000-000000000012';
    const first = [pack(a, 'closed', 3), pack(b, 'closed', 7), pack(c, 'expired', 4)];
    const db = database({ addon_orders: [{ id: a, status: 'active', trainer_staff_id: ids.staff }, { id: c, status: 'active', trainer_staff_id: ids.staff }, { id: ids.other, status: 'active', trainer_staff_id: ids.staff }] }, (_name, args) => ({ data: args.p_after_id ? [] : first, error: null }));
    const result = await load(db.client, caller(role), ids.staff);
    expect(result).toEqual({ data: { packs: [first[0], first[2]], scheduledCount: 7, overLimit: false }, error: null });
    expect(db.rpc.mock.calls.every(([, args]) => args.p_state === undefined)).toBe(true);
    expect(db.calls).toContainEqual({ table: 'addon_orders', method: 'eq', args: ['status', 'active'] });
    const projection = db.calls.find(item => item.table === 'addon_orders' && item.method === 'select'); expect(String(projection?.args[0]).replace(/\s/g, '').split(',').sort()).toEqual(['id', 'status', 'trainer_staff_id'].sort());
  });
  it('all-source maximum is flagged without truncating 101 eligible orders', async () => {
    const load = await target('loadReassignmentCandidates'); const rows = Array.from({ length: 101 }, (_, index) => pack(`80100000-0000-4000-8000-${String(index + 100).padStart(12, '0')}`));
    const db = database({ addon_orders: rows.map(row => ({ id: row.order_id, status: 'active', trainer_staff_id: ids.staff })) }, (_name, args) => { const start = args.p_after_id ? rows.findIndex(row => row.order_id === args.p_after_id) + 1 : 0; return { data: rows.slice(start, start + 50), error: null }; });
    const result = await load(db.client, caller(), ids.staff); expect(result.data).toMatchObject({ packs: rows, scheduledCount: 202, overLimit: true });
  });
  it.each(['error', 'repeat'])('a later %s page invalidates completeness', async mode => {
    const load = await target('loadReassignmentCandidates'); const row = pack(ids.other); const db = database({ addon_orders: [{ id: ids.other, status: 'active', trainer_staff_id: ids.staff }] }, (_name, args) => args.p_after_id && mode === 'error' ? { data: null, error: { message: 'private sql' } } : { data: [row], error: null });
    const result = await load(db.client, caller(), ids.staff); expect(result.data).toBeNull(); expect(result.error).toBeTruthy();
  });
});

describe('held time off standing-booking completeness', () => {
  it.each([['Asia/Kolkata', '2027-01-01', '2027-08-01', '2026-12-31T18:30:00.000Z', '2027-08-01T18:30:00.000Z'], ['America/New_York', '2027-03-13', '2027-03-15', '2027-03-13T05:00:00.000Z', '2027-03-16T04:00:00.000Z']])('inclusive local dates in %s span every half-open chunk', async (zone, start, end, from, to) => {
    const load = await target('loadTimeOffBookings'); const db = database(); const result = await load(db.client, caller(), ids.staff, start, end, zone); expect(result).toEqual({ data: [], error: null });
    const args = db.rpc.mock.calls.map(([, input]) => input); expect(new Date(String(args[0]?.p_from)).toISOString()).toBe(from); expect(new Date(String(args.at(-1)?.p_to)).toISOString()).toBe(to);
    args.forEach((arg, index) => { expect(arg).toMatchObject({ p_trainer_staff_id: ids.staff, p_status: 'booked' }); expect(Date.parse(String(arg.p_to)) - Date.parse(String(arg.p_from))).toBeLessThanOrEqual(62 * 24 * 60 * 60 * 1000); if (index) expect(arg.p_from).toBe(args[index - 1]?.p_to); });
  });
  it('any later chunk failure hides an incomplete affected count', async () => {
    const load = await target('loadTimeOffBookings'); let count = 0; const db = database({}, () => { count += 1; return count === 1 ? { data: [], error: null } : { data: null, error: { message: 'SECRET' } }; });
    const result = await load(db.client, caller(), ids.staff, '2027-01-01', '2027-08-01', 'Asia/Kolkata'); expect(result.data).toBeNull(); expect(result.error).toBeTruthy();
  });
});

describe('held independent detail sections and preview reads', () => {
  it('preview keeps canonical null staff/role while reading ordinary booking RPC', async () => {
    const load = await target('loadPtBookings'); const db = database(); expect(await load(db.client, preview, range)).toEqual({ data: [], error: null }); expect(db.rpc.mock.calls[0]?.[1].p_trainer_staff_id).toBeUndefined();
  });
  it('a failed trainer prerequisite never opens downstream profile or media reads', async () => {
    const load = await target('loadTrainerDetail'); const db = database(); const result = await load(db.client, caller(), ids.staff) as unknown as Record<string, Section>;
    expect(result.trainer?.data).toBeNull(); expect(result.trainer?.error).toBeTruthy();
    expect(db.calls.filter(call => ['trainer_profiles', 'trainer_availability', 'trainer_time_off'].includes(call.table))).toEqual([]);
  });
  it('successful detail maps strict camelCase windows, preserves absent image and does not leak private fields', async () => {
    const load = await target('loadTrainerDetail'); const db = database({ staff: [{ id: ids.staff, full_name: 'Held trainer', is_active: true, qualification: null, branch_id: null }], organizations: [{ timezone: 'Asia/Kolkata' }], trainer_profiles: [{ bio: 'Public bio', specialities: ['Strength'], photo_asset_id: null, is_listed: false }], trainer_availability: [{ weekday: 1, start_minute: 480, end_minute: 540 }], trainer_time_off: [] });
    const result = await load(db.client, caller(), ids.staff) as unknown as Record<string, Section>;
    expect(result.windows).toEqual({ data: [{ weekday: 1, startMinute: 480, endMinute: 540 }], error: null }); expect(result.imageUrl).toEqual({ data: null, error: null }); expect(result.timeOff).toEqual({ data: [], error: null });
    for (const call of db.calls.filter(item => item.method === 'select')) expect(String(call.args[0])).not.toMatch(/\*|phone|email|user_id|object_key/);
  });
  it('time-off exhausts tuple-keyset pages rather than stopping at a short nonempty page', async () => {
    const load = await target('loadTimeOffBookings'); const row = { session_id: ids.other, starts_at: '2027-01-01T12:00:00Z', ends_at: '2027-01-01T13:00:00Z', status: 'booked', cancelled_at: null }; const db = database({}, (_name, args) => ({ data: args.p_after_id ? [] : [row], error: null }));
    expect(await load(db.client, caller('trainer'), ids.staff, '2027-01-01', '2027-01-01', 'Asia/Kolkata')).toEqual({ data: [row], error: null }); expect(db.rpc.mock.calls[1]?.[1]).toMatchObject({ p_after_id: ids.other, p_after_starts_at: row.starts_at });
  });
  it('a repeated time-off tuple cursor fails instead of looping or overcounting', async () => {
    const load = await target('loadTimeOffBookings'); const row = { session_id: ids.other, starts_at: '2027-01-01T12:00:00Z', status: 'booked' }; const db = database({}, () => ({ data: [row], error: null }));
    const result = await load(db.client, caller(), ids.staff, '2027-01-01', '2027-01-01', 'Asia/Kolkata'); expect(result.data).toBeNull(); expect(result.error).toBeTruthy();
  });
});
