import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '../../../../packages/db/types/database';

type Role = Database['public']['Enums']['app_role'];
type Viewer = { role: Role | null; staffId: string | null; readOnly: boolean; scopeKey: string };
type Caller = { identity: { kind: 'staff'; userId: string; tenantId: string; staffId: string; role: Role } | { kind: 'impersonation'; userId: string; tenantId: string; impersonationSessionId: string }; viewer: Viewer };
type Pack = Database['public']['Functions']['read_pt_packs']['Returns'][number];
type Booking = Omit<Database['public']['Functions']['read_pt_bookings']['Returns'][number], 'cancelled_at'> & { cancelled_at: string | null };
type Section<T> = { data: T[] | null; error: string | null };
type Value<T> = { data: T | null; error: string | null };
type Choice = { staffId: string; displayName: string; isActive: boolean; qualification: string | null; timezone: string; branchName: string | null };
type Adapters = {
  loadPtBookings(c: SupabaseClient<Database>, v: Caller, a: Database['public']['Functions']['read_pt_bookings']['Args']): Promise<Section<Booking>>;
  loadPtPacks(c: SupabaseClient<Database>, v: Caller, a: Database['public']['Functions']['read_pt_packs']['Args']): Promise<Section<Pack>>;
  loadTrainerChoices(c: SupabaseClient<Database>, v: Caller): Promise<Section<Choice>>;
  loadTrainerDetail(c: SupabaseClient<Database>, v: Caller, id: string): Promise<{ trainer: Value<Choice>; profile: Value<unknown>; windows: Section<unknown>; timeOff: Section<unknown>; imageUrl: Value<string> }>;
  loadPtPolicy(c: SupabaseClient<Database>, v: Caller): Promise<Value<{ cancelWindowHours: number; lateCancelConsumes: boolean; sessionMinutes: number }>>;
  loadReassignmentCandidates(c: SupabaseClient<Database>, v: Caller, id: string): Promise<Value<{ packs: Pack[]; scheduledCount: number; overLimit: boolean }>>;
  loadTimeOffBookings(c: SupabaseClient<Database>, v: Caller, id: string, from: string, to: string, zone: string): Promise<Section<Booking>>;
};
const tenant = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const trainer = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const otherTrainer = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const userId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const from = '2026-01-01T00:00:00Z';
const to = '2026-03-04T00:00:00Z';
const media = vi.hoisted(() => ({ display: vi.fn() }));
vi.mock('../media', () => ({ mediaDisplayUrl: media.display }));
const targetPath = '../training-console';
const load = async (): Promise<Adapters> => await import(targetPath) as Adapters;
const caller = (role: Role = 'gym_owner'): Caller => ({ identity: { kind: 'staff', userId, tenantId: tenant, staffId: trainer, role }, viewer: { role, staffId: trainer, readOnly: false, scopeKey: `staff:${tenant}:${trainer}:${role}` } });
const preview = (): Caller => ({ identity: { kind: 'impersonation', userId, tenantId: tenant, impersonationSessionId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee' }, viewer: { role: null, staffId: null, readOnly: true, scopeKey: 'preview:live' } });
const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const pack = (n: number, overrides: Partial<Pack> = {}): Pack => ({ order_id: id(n), programme_name: 'Frozen PT programme', member_id: id(900), member_code: 'M001', member_name: 'Member One', trainer_staff_id: trainer, trainer_name: 'Trainer One', trainer_active: true, starts_on: '2026-01-01', expires_on: '2026-12-31', sessions_total: 12, sessions_used: 2, sessions_scheduled: 3, sessions_remaining: 7, state: 'live', timezone: 'Asia/Kolkata', ...overrides });
const booking = (n: number, overrides: Partial<Booking> = {}): Booking => ({ session_id: id(n), order_id: id(800), member_id: id(900), member_code: 'M001', member_name: 'Member One', trainer_staff_id: trainer, trainer_name: 'Trainer One', starts_at: '2026-01-01T08:00:00Z', ends_at: '2026-01-01T09:00:00Z', status: 'booked', timezone: 'Asia/Kolkata', consumed: false, cancelled_at: null, sessions_total: 12, sessions_used: 2, sessions_remaining: 7, ...overrides });
type Row = Record<string, unknown>;
type Reply = { data: unknown; error: { message: string; code?: string } | null };
type Operation = { name: string; args: unknown[] };
type QueryRecord = { table: string; operations: Operation[] };
function boundary() {
  const queries: QueryRecord[] = [];
  const tables: Record<string, Row[]> = {
    staff: [{ id: trainer, full_name: 'Trainer One', role: 'trainer', is_active: true, qualification: 'Certified', branch_id: id(700), tenant_id: tenant, email: 'private@invalid.test', phone: 'PRIVATE_PHONE', user_id: userId }],
    branches: [{ id: id(700), name: 'Branch', timezone: 'Asia/Kolkata' }],
    organizations: [{ id: tenant, timezone: 'Asia/Kolkata' }],
    trainer_profiles: [{ staff_id: trainer, bio: 'Safe bio', specialities: ['Strength'], photo_asset_id: id(600), is_listed: true }],
    trainer_availability: [{ staff_id: trainer, weekday: 1, start_minute: 360, end_minute: 480 }],
    trainer_time_off: [{ id: id(500), staff_id: trainer, starts_on: '2026-02-01', ends_on: '2026-02-02', reason: 'Leave', removed_at: null }],
    organization_settings: [{ tenant_id: tenant, pt_cancel_window_hours: 24, pt_late_cancel_consumes_session: true, pt_session_minutes: 60 }], addon_orders: [],
  };
  const failed = new Set<string>();
  const rpc = vi.fn<(name: string, args?: Row) => Promise<Reply>>().mockResolvedValue({ data: [], error: null });
  const fromTable = vi.fn((table: string) => {
    const record: QueryRecord = { table, operations: [] }; queries.push(record);
    const chain: Record<string, unknown> = {};
    for (const name of ['select', 'eq', 'neq', 'in', 'is', 'gt', 'gte', 'lt', 'lte', 'order', 'range', 'limit', 'single', 'maybeSingle', 'match']) {
      chain[name] = (...args: unknown[]) => { record.operations.push({ name, args }); return chain; };
    }
    chain.then = (resolve: (v: Reply) => unknown, reject?: (e: unknown) => unknown) => {
      let rows = [...(tables[table] ?? [])];
      for (const op of record.operations) {
        const [field, value] = op.args;
        if (typeof field === 'string' && op.name === 'eq') rows = rows.filter(r => r[field] === value);
        if (typeof field === 'string' && op.name === 'gt') rows = rows.filter(r => String(r[field]) > String(value));
        if (typeof field === 'string' && op.name === 'in' && Array.isArray(value)) rows = rows.filter(r => value.includes(r[field]));
        if (op.name === 'range' && typeof field === 'number' && typeof value === 'number') rows = rows.slice(field, value + 1);
        if (op.name === 'limit' && typeof field === 'number') rows = rows.slice(0, field);
      }
      const single = record.operations.some(o => o.name === 'single' || o.name === 'maybeSingle');
      return Promise.resolve<Reply>(failed.has(table) ? { data: null, error: { message: 'SECRET database token private@invalid.test', code: '42501' } } : { data: single ? rows[0] ?? null : rows, error: null }).then(resolve, reject);
    };
    return chain;
  });
  return { client: { rpc, from: fromTable } as unknown as SupabaseClient<Database>, rpc, fromTable, queries, tables, failed };
}
async function refuses(action: () => Promise<unknown>) {
  let result: unknown;
  try { result = await action(); } catch { return; }
  expect(result).toMatchObject({ data: null });
}
beforeEach(() => { vi.clearAllMocks(); media.display.mockResolvedValue('https://safe.invalid/photo'); });

describe('PTF-028 console adapter audience and own-trainer authority', () => {
  it.each(['member', 'super_admin', 'platform_support'] as const)('refuses %s before every feature read', async role => {
    const a = await load(); const b = boundary(); const v = caller(role);
    for (const operation of [() => a.loadPtBookings(b.client, v, { p_from: from, p_to: to }), () => a.loadPtPacks(b.client, v, {}), () => a.loadTrainerChoices(b.client, v), () => a.loadPtPolicy(b.client, v), () => a.loadReassignmentCandidates(b.client, v, trainer), () => a.loadTimeOffBookings(b.client, v, trainer, '2026-01-01', '2026-01-01', 'Asia/Kolkata')]) await refuses(operation);
    expect(b.rpc).not.toHaveBeenCalled(); expect(b.fromTable).not.toHaveBeenCalled();
  });
  it.each(['gym_owner', 'gym_manager', 'front_desk', 'trainer'] as const)('admits %s to the existing booking and pack RPCs', async role => {
    const a = await load(); const b = boundary(); b.rpc.mockResolvedValueOnce({ data: [booking(1)], error: null }).mockResolvedValueOnce({ data: [pack(1)], error: null });
    expect((await a.loadPtBookings(b.client, caller(role), { p_from: from, p_to: to })).data).toEqual([booking(1)]);
    expect((await a.loadPtPacks(b.client, caller(role), {})).data).toEqual([pack(1)]);
    expect(b.fromTable).not.toHaveBeenCalled();
    if (role === 'trainer') for (const call of b.rpc.mock.calls) expect(call[1]).toMatchObject({ p_trainer_staff_id: trainer });
  });
  it('admits canonical preview reads without inventing a staff id and refuses reassignment before reads', async () => {
    const a = await load(); const b = boundary(); const v = preview();
    expect(await a.loadPtBookings(b.client, v, { p_from: from, p_to: to })).toEqual({ data: [], error: null });
    expect(await a.loadPtPacks(b.client, v, {})).toEqual({ data: [], error: null });
    expect(b.rpc.mock.calls.every(c => !c[1]?.p_trainer_staff_id)).toBe(true);
    b.rpc.mockClear(); await refuses(() => a.loadReassignmentCandidates(b.client, v, trainer)); expect(b.rpc).not.toHaveBeenCalled(); expect(b.fromTable).not.toHaveBeenCalled();
  });
  it.each(['role', 'staffId', 'readOnly'] as const)('identity/viewer %s mismatch cannot grant presentation authority', async field => {
    const a = await load(); const b = boundary(); const v = caller('trainer');
    if (field === 'role') v.viewer.role = 'gym_owner'; if (field === 'staffId') v.viewer.staffId = otherTrainer; if (field === 'readOnly') v.viewer.readOnly = true;
    await refuses(() => a.loadPtPacks(b.client, v, {})); await refuses(() => a.loadTrainerChoices(b.client, v)); expect(b.rpc).not.toHaveBeenCalled(); expect(b.fromTable).not.toHaveBeenCalled();
  });
  it('trainer foreign detail and optional foreign filters refuse before access', async () => {
    const a = await load(); const b = boundary(); const v = caller('trainer');
    await refuses(() => a.loadPtBookings(b.client, v, { p_from: from, p_to: to, p_trainer_staff_id: otherTrainer }));
    await refuses(() => a.loadPtPacks(b.client, v, { p_trainer_staff_id: otherTrainer }));
    try { const d = await a.loadTrainerDetail(b.client, v, otherTrainer); expect(d.trainer.data).toBeNull(); } catch { /* A guarded not-found throw is also valid. */ }
    expect(b.rpc).not.toHaveBeenCalled(); expect(b.fromTable).not.toHaveBeenCalled();
  });
});

describe('PTF console safe projections and independent errors', () => {
  it('projects only safe trainer metadata and maps display timezone without PII', async () => {
    const a = await load(); const b = boundary(); const r = await a.loadTrainerChoices(b.client, caller());
    expect(r).toEqual({ data: [{ staffId: trainer, displayName: 'Trainer One', isActive: true, qualification: 'Certified', branchName: 'Branch', timezone: 'Asia/Kolkata' }], error: null });
    for (const q of b.queries) for (const op of q.operations.filter(o => o.name === 'select')) expect(String(op.args[0])).not.toMatch(/\*|email|phone|user_id/);
    expect(b.queries.find(q => q.table === 'staff')?.operations).toContainEqual({ name: 'eq', args: ['role', 'trainer'] });
    expect(JSON.stringify(r)).not.toMatch(/PRIVATE|private@|user_id|tenant_id/);
  });
  it('own trainer choices are own-only even when raw staff RLS is broader', async () => {
    const a = await load(); const b = boundary(); b.tables.staff?.push({ id: otherTrainer, full_name: 'Foreign Trainer', role: 'trainer', is_active: true, qualification: null, branch_id: null });
    const r = await a.loadTrainerChoices(b.client, caller('trainer')); expect(r.data?.map(t => t.staffId)).toEqual([trainer]);
    expect(b.queries.find(q => q.table === 'staff')?.operations).toContainEqual({ name: 'eq', args: ['id', trainer] });
  });
  it('falls back from a branch without timezone to organization timezone and preserves nullable branch', async () => {
    const a = await load(); const b = boundary(); b.tables.branches = [{ id: id(700), name: 'Branch', timezone: null }]; b.tables.organizations = [{ id: tenant, timezone: 'Asia/Colombo' }];
    expect((await a.loadTrainerChoices(b.client, caller())).data?.[0]?.timezone).toBe('Asia/Colombo');
    b.tables.staff = [{ id: trainer, full_name: 'Trainer One', role: 'trainer', is_active: true, qualification: null, branch_id: null }];
    expect((await a.loadTrainerChoices(b.client, caller())).data?.[0]?.branchName).toBeNull();
  });
  it.each(['trainer_profiles', 'trainer_availability', 'trainer_time_off'] as const)('a failed %s section preserves independent successful detail', async table => {
    const a = await load(); const b = boundary(); b.failed.add(table); const r = await a.loadTrainerDetail(b.client, caller(), trainer);
    expect(r.trainer.data?.staffId).toBe(trainer);
    const failedSection = table === 'trainer_profiles' ? r.profile : table === 'trainer_availability' ? r.windows : r.timeOff;
    expect(failedSection.data).toBeNull(); expect(failedSection.error).toBeTruthy(); expect(JSON.stringify(r)).not.toContain('SECRET');
    if (table !== 'trainer_availability') expect(r.windows.data).toEqual([{ weekday: 1, startMinute: 360, endMinute: 480 }]);
    if (table !== 'trainer_time_off') expect(r.timeOff.data).toEqual([{ id: id(500), starts_on: '2026-02-01', ends_on: '2026-02-02', reason: 'Leave', removed_at: null }]);
  });
  it('missing profile and image are successful absence, not fabricated errors', async () => {
    const a = await load(); const b = boundary(); b.tables.trainer_profiles = []; const d = await a.loadTrainerDetail(b.client, caller(), trainer);
    expect(d.profile).toEqual({ data: null, error: null }); expect(d.imageUrl).toEqual({ data: null, error: null }); expect(media.display).not.toHaveBeenCalled();
  });
  it('image uses caller-forwarded display seam and exposes no asset metadata', async () => {
    const a = await load(); const b = boundary(); const d = await a.loadTrainerDetail(b.client, caller(), trainer);
    expect(media.display).toHaveBeenCalledWith(b.client, id(600)); expect(d.imageUrl).toEqual({ data: 'https://safe.invalid/photo', error: null });
    expect(JSON.stringify(d)).not.toMatch(/storage_key|mime_type|etag|private@|PRIVATE_PHONE/);
  });
  it('failed prerequisite trainer cannot authorize downstream profile, availability or image reads', async () => {
    const a = await load(); const b = boundary(); b.failed.add('staff'); const d = await a.loadTrainerDetail(b.client, caller(), trainer);
    expect(d.trainer.data).toBeNull(); expect(d.trainer.error).toBeTruthy(); expect(b.queries.some(q => /^trainer_/.test(q.table))).toBe(false); expect(media.display).not.toHaveBeenCalled();
  });
  it.each(['gym_owner', 'gym_manager'] as const)('policy admits %s with exact current facts', async role => {
    const a = await load(); const b = boundary(); expect(await a.loadPtPolicy(b.client, caller(role))).toEqual({ data: { cancelWindowHours: 24, lateCancelConsumes: true, sessionMinutes: 60 }, error: null });
  });
  it('canonical preview sees policy read-only', async () => {
    const a = await load(); const b = boundary(); expect((await a.loadPtPolicy(b.client, preview())).data?.sessionMinutes).toBe(60);
  });
  it.each(['front_desk', 'trainer'] as const)('policy refuses %s before settings access', async role => {
    const a = await load(); const b = boundary(); await refuses(() => a.loadPtPolicy(b.client, caller(role))); expect(b.fromTable).not.toHaveBeenCalled();
  });
  it.each(['failed', 'missing'] as const)('policy %s never supplies editable defaults', async mode => {
    const a = await load(); const b = boundary(); if (mode === 'failed') b.failed.add('organization_settings'); else b.tables.organization_settings = [];
    const r = await a.loadPtPolicy(b.client, caller()); expect(r.data).toBeNull(); expect(r.error).toBeTruthy(); expect(JSON.stringify(r)).not.toContain('SECRET');
  });
});

describe('PTF staff one-page RPC and malformed filter guards', () => {
  it.each([undefined, 0, 1, 50, 51, 500])('clamps page limit %s to 1..50 without changing frozen projection', async limit => {
    const a = await load(); const b = boundary(); const args = limit === undefined ? {} : { p_limit: limit };
    await a.loadPtPacks(b.client, caller(), args); const actual = b.rpc.mock.calls[0]?.[1]?.p_limit;
    expect(actual).toBe(limit === undefined ? 50 : Math.min(50, Math.max(1, limit))); expect(b.rpc).toHaveBeenCalledTimes(1);
  });
  it('booking null cancellation remains nullable and no direct ledger table read is used', async () => {
    const a = await load(); const b = boundary(); b.rpc.mockResolvedValue({ data: [booking(1)], error: null });
    expect((await a.loadPtBookings(b.client, caller(), { p_from: from, p_to: to })).data?.[0]?.cancelled_at).toBeNull(); expect(b.fromTable).not.toHaveBeenCalled();
  });
  it.each([{ p_after_id: id(1) }, { p_after_starts_at: from }, { p_from: 'garbage' }, { p_to: '2026-04-01T00:00:00Z' }, { p_to: from }, { p_trainer_staff_id: 'not-a-uuid' }, { p_status: 'invented' }])('refuses malformed booking filter %j before RPC', async overrides => {
    const a = await load(); const b = boundary(); await refuses(() => a.loadPtBookings(b.client, caller(), { p_from: from, p_to: to, ...overrides } as Database['public']['Functions']['read_pt_bookings']['Args'])); expect(b.rpc).not.toHaveBeenCalled();
  });
  it('62 elapsed days succeeds even beyond the new-booking horizon and forwards a complete cursor', async () => {
    const a = await load(); const b = boundary(); await a.loadPtBookings(b.client, caller(), { p_from: from, p_to: to, p_after_starts_at: from, p_after_id: id(1), p_status: 'booked' });
    expect(b.rpc).toHaveBeenCalledWith('read_pt_bookings', expect.objectContaining({ p_from: from, p_to: to, p_after_starts_at: from, p_after_id: id(1), p_status: 'booked' }));
  });
  it('RPC errors are sanitized null sections while successful empty remains empty', async () => {
    const a = await load(); const b = boundary(); b.rpc.mockResolvedValueOnce({ data: null, error: { message: 'SECRET SQL JWT private@invalid.test' } });
    const failed = await a.loadPtPacks(b.client, caller(), {}); expect(failed.data).toBeNull(); expect(failed.error).toBeTruthy(); expect(JSON.stringify(failed)).not.toContain('SECRET'); expect(await a.loadPtPacks(b.client, caller(), {})).toEqual({ data: [], error: null });
  });
});

describe('PTF reassignment complete underlying ACTIVE intersection', () => {
  it.each(['gym_owner', 'gym_manager'] as const)('%s includes future closed and expired ACTIVE, excluding completed/refunded and non-PT', async role => {
    const a = await load(); const b = boundary(); const rows = [pack(1, { state: 'closed', starts_on: '2027-01-01', sessions_scheduled: 4 }), pack(2, { state: 'expired', sessions_scheduled: 5 }), pack(3, { state: 'spent' }), pack(4, { state: 'closed' })];
    b.tables.addon_orders = [1, 2, 5].map(n => ({ id: id(n), status: 'active', trainer_staff_id: trainer, tenant_id: tenant }));
    b.rpc.mockImplementation(async (name, args) => ({ data: name === 'read_pt_packs' && !args?.p_after_id ? rows : [], error: null }));
    const r = await a.loadReassignmentCandidates(b.client, caller(role), trainer);
    expect(r).toEqual({ data: { packs: rows.slice(0, 2), scheduledCount: 9, overLimit: false }, error: null });
    for (const call of b.rpc.mock.calls) expect(call[1]).not.toHaveProperty('p_state');
    for (const q of b.queries.filter(q => q.table === 'addon_orders')) {
      expect(q.operations).toContainEqual({ name: 'eq', args: ['tenant_id', tenant] }); expect(q.operations).toContainEqual({ name: 'eq', args: ['trainer_staff_id', trainer] }); expect(q.operations).toContainEqual({ name: 'eq', args: ['status', 'active'] });
      expect(q.operations.find(o => o.name === 'select')?.args[0]).toMatch(/id/); expect(String(q.operations.find(o => o.name === 'select')?.args[0])).not.toMatch(/\*|member|payment|snapshot|price/);
    }
  });
  it('exhausts every RPC and ACTIVE page, never truncates 101 to fit a 100-order command', async () => {
    const a = await load(); const b = boundary(); const rows = Array.from({ length: 101 }, (_, n) => pack(n + 1, { sessions_scheduled: n === 100 ? 8 : 1 }));
    b.tables.addon_orders = rows.map(p => ({ id: p.order_id, status: 'active', trainer_staff_id: trainer, tenant_id: tenant }));
    b.rpc.mockImplementation(async (_name, args) => ({ data: rows.filter(p => p.order_id > String(args?.p_after_id ?? '')).slice(0, Number(args?.p_limit ?? 50)), error: null }));
    const r = await a.loadReassignmentCandidates(b.client, caller(), trainer); expect(r.data?.packs).toHaveLength(101); expect(r.data?.scheduledCount).toBe(108); expect(r.data?.overLimit).toBe(true);
    expect(b.rpc.mock.calls.length).toBeGreaterThanOrEqual(3); expect(b.queries.filter(q => q.table === 'addon_orders').length).toBeGreaterThan(1);
  });
  it.each(['rpc-failure', 'active-failure', 'nonprogress'] as const)('fails closed on %s rather than returning a complete-looking partial count', async mode => {
    const a = await load(); const b = boundary(); b.tables.addon_orders = [{ id: id(1), status: 'active', trainer_staff_id: trainer, tenant_id: tenant }];
    if (mode === 'active-failure') b.failed.add('addon_orders');
    let pages = 0; b.rpc.mockImplementation(async () => { pages += 1; if (mode === 'rpc-failure' && pages > 1) return { data: null, error: { message: 'SECRET' } }; return { data: mode === 'nonprogress' || pages === 1 ? Array.from({ length: 50 }, (_, n) => pack(n + 1)) : [], error: null }; });
    const r = await a.loadReassignmentCandidates(b.client, caller(), trainer); expect(r.data).toBeNull(); expect(r.error).toBeTruthy(); expect(JSON.stringify(r)).not.toContain('SECRET');
  });
  it.each(['front_desk', 'trainer'] as const)('reassignment refuses %s before ledger access', async role => {
    const a = await load(); const b = boundary(); await refuses(() => a.loadReassignmentCandidates(b.client, caller(role), trainer)); expect(b.rpc).not.toHaveBeenCalled(); expect(b.fromTable).not.toHaveBeenCalled();
  });
});

describe('PTF-007 standing booking completeness across local time-off dates', () => {
  it.each(['Asia/Kolkata', 'America/New_York'] as const)('resolves %s local midnight and exhausts paged half-open chunks beyond 62 and 28 days', async zone => {
    const a = await load(); const b = boundary(); const seen = new Set<string>();
    b.rpc.mockImplementation(async (_name, args) => { const key = `${String(args?.p_from)}:${String(args?.p_to)}`; if (!seen.has(key)) { seen.add(key); return { data: Array.from({ length: 50 }, (_, n) => booking(n + 1, { starts_at: String(args?.p_from) })), error: null }; } return { data: args?.p_after_id === id(50) ? [booking(51, { starts_at: String(args?.p_from) })] : [], error: null }; });
    const r = await a.loadTimeOffBookings(b.client, caller(), trainer, '2026-01-01', '2026-06-30', zone); expect(r.error).toBeNull(); expect(r.data?.length).toBeGreaterThan(100);
    const calls = b.rpc.mock.calls.map(c => c[1] ?? {}); const chunks = calls.filter(c => !c.p_after_id); expect(chunks.length).toBeGreaterThan(2);
    expect(chunks[0]?.p_from).toBe(zone === 'Asia/Kolkata' ? '2025-12-31T18:30:00.000Z' : '2026-01-01T05:00:00.000Z');
    expect(chunks.at(-1)?.p_to).toBe(zone === 'Asia/Kolkata' ? '2026-06-30T18:30:00.000Z' : '2026-07-01T04:00:00.000Z');
    for (const [n, chunk] of chunks.entries()) { expect(Date.parse(String(chunk.p_to)) - Date.parse(String(chunk.p_from))).toBeLessThanOrEqual(62 * 24 * 60 * 60 * 1000); if (n) expect(chunk.p_from).toBe(chunks[n - 1]?.p_to); }
    for (const args of calls) expect(args).toMatchObject({ p_status: 'booked', p_trainer_staff_id: trainer });
    for (const args of calls.filter(c => c.p_after_id)) expect(args.p_after_starts_at).toBeTruthy();
  });
  it('a single local date includes the full local day through next midnight', async () => {
    const a = await load(); const b = boundary(); await a.loadTimeOffBookings(b.client, caller('trainer'), trainer, '2026-01-01', '2026-01-01', 'Asia/Kolkata');
    expect(b.rpc).toHaveBeenCalledWith('read_pt_bookings', expect.objectContaining({ p_from: '2025-12-31T18:30:00.000Z', p_to: '2026-01-01T18:30:00.000Z' }));
  });
  it.each(['invalid-zone', 'invalid-date', 'reverse', 'foreign-trainer'] as const)('%s refuses before booking access', async fault => {
    const a = await load(); const b = boundary(); await refuses(() => a.loadTimeOffBookings(b.client, caller('trainer'), fault === 'foreign-trainer' ? otherTrainer : trainer, fault === 'invalid-date' ? '2026-02-30' : '2026-01-01', fault === 'reverse' ? '2025-12-31' : '2026-01-01', fault === 'invalid-zone' ? 'Not/AZone' : 'Asia/Kolkata')); expect(b.rpc).not.toHaveBeenCalled();
  });
  it('later chunk failure returns no partial affected count', async () => {
    const a = await load(); const b = boundary(); let firstChunk: unknown;
    b.rpc.mockImplementation(async (_name, args) => { firstChunk ??= args?.p_from; return args?.p_from === firstChunk ? { data: args?.p_after_id ? [] : [booking(1)], error: null } : { data: null, error: { message: 'SECRET SQL' } }; });
    const r = await a.loadTimeOffBookings(b.client, caller(), trainer, '2026-01-01', '2026-12-31', 'Asia/Kolkata'); expect(r.data).toBeNull(); expect(r.error).toBeTruthy(); expect(JSON.stringify(r)).not.toContain('SECRET');
  });
});

