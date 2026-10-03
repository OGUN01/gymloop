import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Database } from '../../packages/db/types/database';

type HeldRole = Database['public']['Enums']['app_role'];

type Node = { type?: unknown; props?: Record<string, unknown> };
const boundary = vi.hoisted(() => ({ slots: [] as unknown[], cursor: 0, effects: [] as { deps?: unknown[]; cleanup?: () => void }[], effectCursor: 0, online: true, refresh: vi.fn(), audience: vi.fn(), send: vi.fn(), fetch: vi.fn() }));
vi.mock('react', async () => {
  const actual = await vi.importActual<Record<string, unknown>>('react');
  return { ...actual,
    useState: (initial: unknown) => { const index = boundary.cursor++; if (!(index in boundary.slots)) boundary.slots[index] = typeof initial === 'function' ? (initial as () => unknown)() : initial; return [boundary.slots[index], (value: unknown) => { boundary.slots[index] = typeof value === 'function' ? (value as (previous: unknown) => unknown)(boundary.slots[index]) : value; }]; },
    useRef: (initial: unknown) => { const index = boundary.cursor++; if (!(index in boundary.slots)) boundary.slots[index] = { current: initial }; return boundary.slots[index]; },
    useMemo: (factory: () => unknown) => factory(), useCallback: (callback: unknown) => callback,
    useEffect: (effect: () => void | (() => void), deps?: unknown[]) => { const index = boundary.effectCursor++; const previous = boundary.effects[index]; if (!previous || !deps || deps.some((dep, offset) => !Object.is(dep, previous.deps?.[offset]))) { previous?.cleanup?.(); boundary.effects[index] = { deps, cleanup: effect() || undefined }; } },
  };
});
vi.mock('next/navigation', () => ({ useRouter: () => ({ refresh: boundary.refresh, push: vi.fn() }), notFound: () => { throw new Error('NOT_FOUND'); }, redirect: () => { throw new Error('REDIRECT'); } }));
vi.mock('../../apps/web/lib/identity-session', () => ({ requireAudience: boundary.audience }));
vi.mock('../../apps/web/lib/media-upload', () => ({ uploadMediaFile: boundary.send }));
vi.mock('../../apps/web/app/(console)/field', () => ({ Field: ({ label, children }: { label: string; children: unknown }) => ({ type: 'label', props: { children: [label, children] } }), inputClass: 'cl-input' }));
const viewer: { role: HeldRole; staffId: string; readOnly: boolean; scopeKey: string } = { role: 'gym_owner', staffId: '80200000-0000-4000-8000-000000000001', readOnly: false, scopeKey: 'tenant:actor:owner' };
const nouns = { place: 'studio', person: 'client', people: 'clients', membership: 'membership', memberships: 'memberships', trainer: 'coach', trainers: 'coaches', activity: 'activity' };
async function exported(path: string, name: string): Promise<(props: Record<string, unknown>) => unknown> {
  const module = await import(path).catch(() => ({})) as Record<string, unknown>; expect(module[name], `Frozen ${path}#${name} must be renderable`).toBeTypeOf('function'); return module[name] as (props: Record<string, unknown>) => unknown;
}
function render(component: (props: Record<string, unknown>) => unknown, props: Record<string, unknown>) { boundary.cursor = 0; boundary.effectCursor = 0; return component(props); }
function flatten(value: unknown): Node[] {
  if (Array.isArray(value)) return value.flatMap(flatten);
  if (!value || typeof value !== 'object') return [];
  const node = value as Node;
  if (typeof node.type === 'function') return flatten((node.type as (props: unknown) => unknown)(node.props));
  return [node, ...flatten(node.props?.children)];
}
function text(value: unknown): string {
  if (typeof value === 'string' || typeof value === 'number') return String(value);
  if (Array.isArray(value)) return value.map(text).join(' ');
  if (!value || typeof value !== 'object') return '';
  const node = value as Node; if (typeof node.type === 'function') return text((node.type as (props: unknown) => unknown)(node.props)); return text(node.props?.children);
}
function deferred() { let resolve!: (value: unknown) => void; const promise = new Promise<unknown>(done => { resolve = done; }); return { promise, resolve }; }
function hookOptions(overrides: Record<string, unknown> = {}) { return { viewer, operationKey: 'session:A', nouns, canSubmit: () => true, send: boundary.send, accepted: (result: unknown) => !!result && typeof result === 'object' && (result as { accepted?: unknown }).accepted === true, refresh: boundary.refresh, ...overrides }; }
type Coordinator = { pending: boolean; error: string | null; submit: (body: unknown) => Promise<unknown> };
beforeEach(() => { boundary.slots = []; boundary.effects.forEach(effect => effect.cleanup?.()); boundary.effects = []; boundary.cursor = 0; boundary.effectCursor = 0; boundary.online = true; vi.clearAllMocks(); vi.stubGlobal('fetch', boundary.fetch); vi.stubGlobal('navigator', { get onLine() { return boundary.online; } }); vi.stubGlobal('window', { addEventListener: vi.fn(), removeEventListener: vi.fn() }); });

describe('held usePtCommand public lifetime controller', () => {
  it('one flight, accepted-only refresh and no queued second submission', async () => {
    const hook = await exported('../../apps/web/lib/use-pt-command', 'usePtCommand'); const request = deferred(); boundary.send.mockReturnValue(request.promise); const options = hookOptions();
    const state = render(hook, options) as Coordinator; const first = state.submit({ reason: 'Valid reason' }); await state.submit({ reason: 'Second reason' }); expect(boundary.send).toHaveBeenCalledTimes(1);
    request.resolve({ accepted: true }); await first; expect(boundary.refresh).toHaveBeenCalledTimes(1); expect((render(hook, options) as Coordinator).pending).toBe(false);
  });
  it.each([null, {}, { accepted: false }, { accepted: 'true' }])('malformed/unaccepted result %j never refreshes', async result => {
    const hook = await exported('../../apps/web/lib/use-pt-command', 'usePtCommand'); boundary.send.mockResolvedValue(result); const options = hookOptions(); await (render(hook, options) as Coordinator).submit({}); expect(boundary.refresh).not.toHaveBeenCalled(); expect((render(hook, options) as Coordinator).error).toBeTruthy();
  });
  it('positive offline refuses without send; reconnect does not replay', async () => {
    const hook = await exported('../../apps/web/lib/use-pt-command', 'usePtCommand'); const options = hookOptions(); boundary.online = false; await (render(hook, options) as Coordinator).submit({}); expect(boundary.send).not.toHaveBeenCalled(); expect((render(hook, options) as Coordinator).error).toBeTruthy(); boundary.online = true; render(hook, options); expect(boundary.send).not.toHaveBeenCalled();
  });
  it.each(['viewer', 'operation'])('%s A-B-A permanently invalidates retained A callback and late result', async dimension => {
    const hook = await exported('../../apps/web/lib/use-pt-command', 'usePtCommand'); const options = hookOptions(); const old = render(hook, options) as Coordinator; const request = deferred(); boundary.send.mockReturnValue(request.promise); const flight = old.submit({});
    render(hook, dimension === 'viewer' ? hookOptions({ viewer: { ...viewer, scopeKey: 'different' } }) : hookOptions({ operationKey: 'session:B' })); render(hook, options); request.resolve({ accepted: true }); await flight; expect(boundary.refresh).not.toHaveBeenCalled(); await old.submit({}); expect(boundary.send).toHaveBeenCalledTimes(1); expect((render(hook, options) as Coordinator).error).toBeNull();
  });
  it('unmount invalidates retained callback before submission and pending feedback', async () => {
    const hook = await exported('../../apps/web/lib/use-pt-command', 'usePtCommand'); const options = hookOptions(); const old = render(hook, options) as Coordinator; boundary.effects.forEach(effect => effect.cleanup?.()); await old.submit({}); expect(boundary.send).not.toHaveBeenCalled(); expect(boundary.refresh).not.toHaveBeenCalled();
  });
  it.each([{ ...viewer, readOnly: true }, { ...viewer, role: 'trainer' }])('submission rechecks immutable presentation permission %j', async actor => {
    const hook = await exported('../../apps/web/lib/use-pt-command', 'usePtCommand'); await (render(hook, hookOptions({ viewer: actor, canSubmit: (input: typeof viewer) => input.role === 'gym_owner' })) as Coordinator).submit({}); expect(boundary.send).not.toHaveBeenCalled();
  });
  it('transport failure is sanitized and retry remains possible', async () => {
    const hook = await exported('../../apps/web/lib/use-pt-command', 'usePtCommand'); const options = hookOptions(); boundary.send.mockRejectedValue(new Error('secret JWT contact@example.com')); await (render(hook, options) as Coordinator).submit({}); const state = render(hook, options) as Coordinator; expect(state.error).toBeTruthy(); expect(state.error).not.toMatch(/secret|JWT|contact@/); expect(boundary.refresh).not.toHaveBeenCalled(); boundary.send.mockResolvedValue({ accepted: true }); await state.submit({}); expect(boundary.refresh).toHaveBeenCalledTimes(1);
  });
});

const trainer = { staffId: viewer.staffId, displayName: 'Independent Coach', isActive: true, qualification: 'CPT', timezone: 'Asia/Kolkata', branchName: null };
const booking = { session_id: '80200000-0000-4000-8000-000000000009', trainer_staff_id: viewer.staffId, status: 'booked', consumed: false, cancelled_at: null, starts_at: '2027-01-12T06:00:00Z', ends_at: '2027-01-12T07:00:00Z', timezone: 'Asia/Kolkata' };
const controls = [
  { path: '../../apps/web/app/(console)/training/booking-actions', name: 'BookingRowActions', props: { booking } },
  { path: '../../apps/web/app/(console)/training/reassign-panel', name: 'ReassignPacksPanel', props: { fromStaffId: null, candidates: { data: { packs: [], scheduledCount: 0, overLimit: false }, error: null }, trainers: [trainer] } },
  { path: '../../apps/web/app/(console)/training/trainers/[staffId]/trainer-forms', name: 'TrainerProfileForm', props: { trainer, profile: { bio: 'Held bio', specialities: ['Strength'], photo_asset_id: null, is_listed: false }, imageUrl: null } },
  { path: '../../apps/web/app/(console)/training/trainers/[staffId]/trainer-forms', name: 'TrainerAvailabilityEditor', props: { trainer, windows: [] } },
  { path: '../../apps/web/app/(console)/training/trainers/[staffId]/trainer-forms', name: 'TrainerTimeOffPanel', props: { trainer, entries: [], bookings: { data: [], error: null } } },
  { path: '../../apps/web/app/(console)/training/policy/pt-policy-form', name: 'PtPolicyForm', props: { policy: { cancelWindowHours: 24, lateCancelConsumes: true, sessionMinutes: 60 } } },
];
describe('held actual console controls preserve role boundaries', () => {
  it.each(controls)('$name has no writable control in canonical support preview', async ({ path, name, props }) => {
    const component = await exported(path, name); const view = render(component, { ...props, viewer: { role: null, staffId: null, readOnly: true, scopeKey: 'preview:session' }, nouns });
    const writable = flatten(view).filter(node => ['button', 'input', 'select', 'textarea'].includes(String(node.type)) && !node.props?.disabled && !node.props?.readOnly); expect(writable).toEqual([]);
  });
  it('own trainer profile exposes bio/specialities but never listing or photo', async () => {
    const fixture = controls[2]; const component = await exported(fixture.path, fixture.name); const view = render(component, { ...fixture.props, viewer: { ...viewer, role: 'trainer' }, nouns }); const words = text(view); expect(words).toMatch(/bio/i); expect(words).toMatch(/special/i); expect(words).not.toMatch(/list this|listed|upload|photo/i); expect(flatten(view).filter(node => node.type === 'input' && node.props?.type === 'file')).toEqual([]);
  });
  it('cancellation is a reason-and-confirmation action before any network call', async () => {
    const fixture = controls[0]; const component = await exported(fixture.path, fixture.name); const props = { ...fixture.props, viewer, nouns }; const view = render(component, props); const cancel = flatten(view).find(node => node.type === 'button' && /cancel/i.test(text(node))); expect(cancel).toBeTruthy(); const onClick = cancel?.props?.onClick; expect(onClick).toBeTypeOf('function'); await (onClick as () => unknown)(); expect(boundary.fetch).not.toHaveBeenCalled(); const confirm = render(component, props); expect(text(confirm)).toMatch(/reason/i); expect(text(confirm)).toMatch(/confirm/i);
  });
  it('policy states consequences for hours, consumption and session duration', async () => {
    const fixture = controls[5]; const component = await exported(fixture.path, fixture.name); const words = text(render(component, { ...fixture.props, viewer, nouns })); expect(words).toMatch(/24/); expect(words).toMatch(/60/); expect(words).toMatch(/cancel/i); expect(words).toMatch(/session.*(?:use|consum)|(?:use|consum).*session/i);
  });
  it('a failed complete reassignment count provides no enabled commit', async () => {
    const fixture = controls[1]; const component = await exported(fixture.path, fixture.name); const view = render(component, { ...fixture.props, candidates: { data: null, error: 'Unable to load packs. Try again.' }, viewer, nouns }); expect(text(view)).toMatch(/try again|retry|unable/i); expect(flatten(view).filter(node => node.type === 'button' && /confirm|reassign/i.test(text(node)) && !node.props?.disabled)).toEqual([]);
  });
  it('time off shows standing bookings without promising automatic cancellation', async () => {
    const fixture = controls[4]; const component = await exported(fixture.path, fixture.name); const view = render(component, { ...fixture.props, bookings: { data: [{ ...booking, member_name: 'Held standing client', member_code: 'H-77' }], error: null }, entries: [{ id: 'off-1', starts_on: '2027-01-12', ends_on: '2027-01-12', reason: 'Leave', removed_at: null }], viewer, nouns }); expect(text(view)).toContain('Held standing client'); expect(text(view)).toMatch(/(?:remain|stand|already booked|existing)/i); expect(text(view)).not.toMatch(/automatically cancel/i);
  });
});

describe('held all fixed server pages guard audience before feature reads', () => {
  it.each(['../../apps/web/app/(console)/training/page', '../../apps/web/app/(console)/training/packs/page', '../../apps/web/app/(console)/training/trainers/page', '../../apps/web/app/(console)/training/trainers/[staffId]/page', '../../apps/web/app/(console)/training/policy/page'])('%s uses the existing console audience guard', async path => {
    const page = await exported(path, 'default'); boundary.audience.mockRejectedValue(new Error('AUDIENCE_REFUSAL')); await expect(page({ searchParams: Promise.resolve({}), params: Promise.resolve({ staffId: viewer.staffId }) })).rejects.toThrow('AUDIENCE_REFUSAL'); expect(boundary.audience).toHaveBeenCalledWith('console');
  });
});

describe('held control ownership and permanent feedback revocation', () => {
  it.each(controls.filter(item => item.name !== 'BookingRowActions'))('$name cannot mutate with a trainer targeting another trainer', async ({ path, name, props }) => {
    const component = await exported(path, name); const view = render(component, { ...props, viewer: { ...viewer, role: 'trainer', staffId: '80200000-0000-4000-8000-000000000002' }, nouns }); expect(flatten(view).filter(node => ['button', 'input', 'textarea', 'select'].includes(String(node.type)) && !node.props?.disabled && !node.props?.readOnly)).toEqual([]);
  });
  it('front desk has cancel but no late-forfeit waiver', async () => {
    const fixture = controls[0]; const component = await exported(fixture.path, fixture.name); const view = render(component, { booking: { ...booking, status: 'cancelled_by_member', consumed: true }, viewer: { ...viewer, role: 'front_desk' }, nouns }); expect(flatten(view).filter(node => node.type === 'button' && /waive/i.test(text(node)))).toEqual([]);
  });
  it('owner consumed late cancellation exposes waiver confirmation with a reason', async () => {
    const fixture = controls[0]; const component = await exported(fixture.path, fixture.name); const props = { booking: { ...booking, status: 'cancelled_by_member', consumed: true }, viewer, nouns }; const view = render(component, props); const waiver = flatten(view).find(node => node.type === 'button' && /waive/i.test(text(node))); expect(waiver).toBeTruthy(); await (waiver?.props?.onClick as () => unknown)(); const confirm = render(component, props); expect(text(confirm)).toMatch(/reason/i); expect(text(confirm)).toMatch(/confirm/i);
  });
  it('three independent weekly windows stay on the same editable screen', async () => {
    const fixture = controls[3]; const component = await exported(fixture.path, fixture.name); const windows = [{ weekday: 1, startMinute: 480, endMinute: 540 }, { weekday: 3, startMinute: 600, endMinute: 660 }, { weekday: 5, startMinute: 720, endMinute: 780 }]; const view = render(component, { ...fixture.props, windows, viewer, nouns }); expect(flatten(view).filter(node => ['input', 'select'].includes(String(node.type))).length).toBeGreaterThanOrEqual(9); expect(text(view)).toMatch(/save/i);
  });
  it('overlapping same-day windows show inline refusal and cannot be committed', async () => {
    const fixture = controls[3]; const component = await exported(fixture.path, fixture.name); const view = render(component, { ...fixture.props, windows: [{ weekday: 1, startMinute: 480, endMinute: 600 }, { weekday: 1, startMinute: 540, endMinute: 660 }], viewer, nouns }); expect(text(view)).toMatch(/overlap/i); expect(flatten(view).filter(node => node.type === 'button' && /save/i.test(text(node)) && !node.props?.disabled)).toEqual([]);
  });
  it('incomplete affected bookings remain failure text rather than a zero-booking promise', async () => {
    const fixture = controls[4]; const component = await exported(fixture.path, fixture.name); const view = render(component, { ...fixture.props, bookings: { data: null, error: 'Unable to load sessions. Try again.' }, viewer, nouns }); expect(text(view)).toMatch(/unable|retry|try again/i); expect(text(view)).not.toMatch(/no (?:affected|existing|booked) sessions/i);
  });
  it('source snapshot replacement invalidates an old reassignment confirmation', async () => {
    const fixture = controls[1]; const component = await exported(fixture.path, fixture.name); const oldProps = { ...fixture.props, fromStaffId: viewer.staffId, candidates: { data: { packs: [{ order_id: '80200000-0000-4000-8000-000000000010', trainer_staff_id: viewer.staffId, sessions_scheduled: 3, member_name: 'Held client', programme_name: 'Held pack' }], scheduledCount: 3, overLimit: false }, error: null }, trainers: [trainer, { ...trainer, staffId: '80200000-0000-4000-8000-000000000002' }], viewer, nouns }; render(component, oldProps); const view = render(component, { ...oldProps, candidates: { data: null, error: 'Reload source packs.' } }); expect(flatten(view).filter(node => node.type === 'button' && /confirm/i.test(text(node)) && !node.props?.disabled)).toEqual([]); expect(text(view)).toMatch(/reload|retry|source/i);
  });
  it('unmount while a request is pending discards late accepted feedback', async () => {
    const hook = await exported('../../apps/web/lib/use-pt-command', 'usePtCommand'); const request = deferred(); boundary.send.mockReturnValue(request.promise); const state = render(hook, hookOptions()) as Coordinator; const flight = state.submit({}); boundary.effects.forEach(effect => effect.cleanup?.()); request.resolve({ accepted: true }); await flight; expect(boundary.refresh).not.toHaveBeenCalled();
  });
  it('stable current callbacks do not revoke the pending accepted command', async () => {
    const hook = await exported('../../apps/web/lib/use-pt-command', 'usePtCommand'); const request = deferred(); boundary.send.mockReturnValue(request.promise); const options = hookOptions(); const flight = (render(hook, options) as Coordinator).submit({}); render(hook, options); request.resolve({ accepted: true }); await flight; expect(boundary.refresh).toHaveBeenCalledTimes(1);
  });
});


vi.mock('../../apps/web/lib/business-type', () => ({ loadBusinessNouns: async () => nouns }));
vi.mock('../../apps/web/lib/media', () => ({ mediaDisplayUrl: async () => null }));
function pageClient() {
  const rpc = vi.fn(async () => ({ data: [], error: null })); const from = vi.fn(() => { const query: Record<string, unknown> = {}; for (const method of ['select', 'eq', 'in', 'is', 'order', 'range', 'limit', 'gt', 'gte', 'lt', 'lte']) query[method] = () => query; query.then = (done: (value: unknown) => unknown) => Promise.resolve({ data: [], error: null }).then(done); query.maybeSingle = async () => ({ data: null, error: null }); query.single = query.maybeSingle; return query; }); return { rpc, from };
}
const pagePaths = ['../../apps/web/app/(console)/training/page', '../../apps/web/app/(console)/training/packs/page', '../../apps/web/app/(console)/training/trainers/page', '../../apps/web/app/(console)/training/trainers/[staffId]/page', '../../apps/web/app/(console)/training/policy/page'];
describe('held server page role, empty and invalid-input boundaries', () => {
  it.each(pagePaths)('%s denies unsupported identity before feature data', async path => {
    const page = await exported(path, 'default'); const client = pageClient(); boundary.audience.mockResolvedValue({ supabase: client, identity: { kind: 'staff', userId: viewer.staffId, tenantId: viewer.staffId, staffId: viewer.staffId, role: 'accountant' } }); await expect(page({ searchParams: Promise.resolve({}), params: Promise.resolve({ staffId: viewer.staffId }) })).rejects.toThrow('NOT_FOUND'); expect(client.rpc).not.toHaveBeenCalled(); expect(client.from).not.toHaveBeenCalled();
  });
  it.each([['../../apps/web/app/(console)/training/page', 'No sessions in this range.'], ['../../apps/web/app/(console)/training/packs/page', 'No packs match.'], ['../../apps/web/app/(console)/training/trainers/page', 'No trainers yet. Invite one from Team.']])('%s renders successful empty separately from failed reads', async (path, empty) => {
    const page = await exported(path, 'default'); const client = pageClient(); boundary.audience.mockResolvedValue({ supabase: client, identity: { kind: 'staff', userId: viewer.staffId, tenantId: viewer.staffId, staffId: viewer.staffId, role: 'gym_owner' } }); const view = await page({ searchParams: Promise.resolve({ from: '2027-01-01T00:00:00Z', to: '2027-01-02T00:00:00Z' }) }); expect(text(view)).toContain(empty);
  });
  it.each(['../../apps/web/app/(console)/training/page', '../../apps/web/app/(console)/training/packs/page'])('%s names own-trainer scope without leaking verified identity/client props', async path => {
    const page = await exported(path, 'default'); const client = pageClient(); boundary.audience.mockResolvedValue({ supabase: client, identity: { kind: 'staff', userId: 'PRIVATE_ACTOR_IDENTIFIER', tenantId: 'PRIVATE_TENANT_IDENTIFIER', staffId: viewer.staffId, role: 'trainer' } }); const view = await page({ searchParams: Promise.resolve({ from: '2027-01-01T00:00:00Z', to: '2027-01-02T00:00:00Z' }) }); expect(text(view)).toContain('Showing your own clients.'); const serialized = JSON.stringify(view); expect(serialized).not.toContain('PRIVATE_ACTOR_IDENTIFIER'); expect(serialized).not.toContain('PRIVATE_TENANT_IDENTIFIER');
  });
  it('policy failed read does not mount default editable policy form', async () => {
    const page = await exported(pagePaths[4], 'default'); const client = pageClient(); boundary.audience.mockResolvedValue({ supabase: client, identity: { kind: 'staff', userId: viewer.staffId, tenantId: viewer.staffId, staffId: viewer.staffId, role: 'gym_owner' } }); const view = await page({}); expect(text(view)).toMatch(/retry|try again|unable|failed/i); expect(flatten(view).filter(node => ['input', 'select'].includes(String(node.type)) && !node.props?.disabled)).toEqual([]);
  });
  it('malformed booking search strings never reach feature RPCs', async () => {
    const page = await exported(pagePaths[0], 'default'); const client = pageClient(); boundary.audience.mockResolvedValue({ supabase: client, identity: { kind: 'staff', userId: viewer.staffId, tenantId: viewer.staffId, staffId: viewer.staffId, role: 'gym_owner' } }); await Promise.resolve(page({ searchParams: Promise.resolve({ from: 'invalid', to: '2027-01-01', status: 'scheduled', afterId: viewer.staffId }) })).catch(() => null); expect(client.rpc).not.toHaveBeenCalled();
  });
});

describe('held profile MEDIA result and handler leases', () => {
  it('owner profile has listing and upload while support preview has neither writable field', async () => {
    const fixture = controls[2]; const component = await exported(fixture.path, fixture.name); const view = render(component, { ...fixture.props, viewer, nouns }); expect(text(view)).toMatch(/list/i); expect(flatten(view).some(node => node.type === 'input' && node.props?.type === 'file')).toBe(true);
  });
  it('a staged upload result after viewer A-B-A cannot attach the old asset', async () => {
    const fixture = controls[2]; const component = await exported(fixture.path, fixture.name); const props = { ...fixture.props, viewer, nouns }; const request = deferred(); boundary.send.mockReturnValue(request.promise); const first = render(component, props); const upload = flatten(first).find(node => node.type === 'input' && node.props?.type === 'file'); expect(upload).toBeTruthy(); const flight = (upload?.props?.onChange as (event: unknown) => unknown)({ target: { files: [{ name: 'photo.png', type: 'image/png', size: 1 }], value: '' }, currentTarget: { files: [{ name: 'photo.png', type: 'image/png', size: 1 }], value: '' } });
    render(component, { ...props, viewer: { ...viewer, scopeKey: 'other-scope' } }); render(component, props); request.resolve({ assetId: 'STALE_PRIVATE_ASSET' }); await flight; expect(JSON.stringify(render(component, props))).not.toContain('STALE_PRIVATE_ASSET');
  });
  it('retained upload handler revoked before await cannot start a new upload', async () => {
    const fixture = controls[2]; const component = await exported(fixture.path, fixture.name); const props = { ...fixture.props, viewer, nouns }; const first = render(component, props); const upload = flatten(first).find(node => node.type === 'input' && node.props?.type === 'file'); expect(upload).toBeTruthy(); render(component, { ...props, trainer: { ...trainer, staffId: '80200000-0000-4000-8000-000000000002' } }); render(component, props); await (upload?.props?.onChange as (event: unknown) => unknown)({ target: { files: [{ name: 'photo.png', type: 'image/png', size: 1 }], value: '' }, currentTarget: { files: [{ name: 'photo.png', type: 'image/png', size: 1 }], value: '' } }); expect(boundary.send).not.toHaveBeenCalled();
  });
});


describe('held reassignment confirmation arithmetic and service notices', () => {
  it('complete source selection confirms scheduled sessions and member notification before POST', async () => {
    const fixture = controls[1]; const component = await exported(fixture.path, fixture.name);
    const destination = '80200000-0000-4000-8000-000000000002';
    const props = { ...fixture.props, fromStaffId: viewer.staffId, candidates: { data: { packs: [{ order_id: '80200000-0000-4000-8000-000000000010', trainer_staff_id: viewer.staffId, trainer_name: trainer.displayName, member_name: 'Held client', member_code: 'H-10', programme_name: 'Held pack', state: 'expired', sessions_total: 8, sessions_used: 1, sessions_remaining: 7, sessions_scheduled: 3, starts_on: '2026-01-01', expires_on: '2026-09-01', timezone: 'Asia/Kolkata', trainer_active: true }], scheduledCount: 3, overLimit: false }, error: null }, trainers: [trainer, { ...trainer, staffId: destination, displayName: 'Next Coach' }], viewer, nouns };
    let view = render(component, props);
    const selects = flatten(view).filter(node => node.type === 'select');
    const destinationSelect = selects.at(-1); const changeDestination = destinationSelect?.props?.onChange; expect(changeDestination).toBeTypeOf('function'); (changeDestination as (event: unknown) => void)({ target: { value: destination } });
    view = render(component, props);
    for (const node of flatten(view)) { if (node.type === 'textarea' || (node.type === 'input' && /reason/i.test(String(node.props?.name ?? node.props?.placeholder ?? node.props?.['aria-label'] ?? '')))) { const change = node.props?.onChange; if (typeof change === 'function') change({ target: { value: 'Trainer moving away' } }); } }
    view = render(component, props);
    const prepare = flatten(view).find(node => node.type === 'button' && /reassign|review|continue/i.test(text(node)) && !node.props?.disabled);
    expect(prepare, 'A complete admissible source has a review action').toBeTruthy();
    const activation = prepare?.props?.onClick ?? flatten(view).find(node => node.type === 'form')?.props?.onSubmit; expect(activation).toBeTypeOf('function'); await (activation as (event: unknown) => unknown)({ preventDefault: () => undefined }); expect(boundary.fetch).not.toHaveBeenCalled();
    const confirmation = text(render(component, props)); expect(confirmation).toMatch(/3\s+(?:scheduled\s+)?sessions/i); expect(confirmation).toMatch(/(?:members|clients).*notif|notif.*(?:members|clients)/i); expect(confirmation).toMatch(/confirm/i);
  });
});



function labelledControls(view: unknown): { node: Node; label: string }[] {
  const all = flatten(view); const inputs = all.filter(node => ['input', 'textarea', 'select'].includes(String(node.type)));
  return inputs.map(node => { const parent = all.find(item => item.type === 'label' && flatten(item.props?.children).includes(node)); const linked = all.find(item => item.type === 'label' && item.props?.htmlFor === node.props?.id); return { node, label: [node.props?.['aria-label'], node.props?.name, node.props?.placeholder, text(parent ?? linked)].filter(Boolean).join(' ') }; });
}
function changeField(view: unknown, label: RegExp, value: unknown) {
  const entry = labelledControls(view).find(field => label.test(field.label)); expect(entry, `Accessible field ${label} must exist`).toBeTruthy(); const change = entry?.node.props?.onChange; expect(change).toBeTypeOf('function'); (change as (event: unknown) => void)({ target: { value, checked: value }, currentTarget: { value, checked: value } });
}
async function activate(view: unknown, words: RegExp) {
  const button = flatten(view).find(node => node.type === 'button' && words.test(text(node)) && !node.props?.disabled); expect(button, `Enabled action ${words} must exist`).toBeTruthy(); const callback = button?.props?.onClick ?? flatten(view).find(node => node.type === 'form')?.props?.onSubmit; expect(callback).toBeTypeOf('function'); await (callback as (event: unknown) => unknown)({ preventDefault: () => undefined });
}
function acceptedResponse(data: unknown) { return { ok: true, status: 200, json: async () => ({ data }), text: async () => JSON.stringify({ data }) }; }
function sent() { expect(boundary.fetch).toHaveBeenCalledTimes(1); const [url, init] = boundary.fetch.mock.calls[0] as [string, { method?: string; body?: string }]; expect(init.method).toBe('POST'); return { url, body: JSON.parse(init.body ?? '{}') as Record<string, unknown> }; }
const destinationId = '80200000-0000-4000-8000-000000000002';
const heldOrderA = '80200000-0000-4000-8000-000000000010';
const heldOrderB = '80200000-0000-4000-8000-000000000011';
function reassignProps(overrides: Record<string, unknown> = {}) {
  return { fromStaffId: viewer.staffId, candidates: { data: { packs: [heldOrderA, heldOrderB].map((order_id, index) => ({ order_id, trainer_staff_id: viewer.staffId, trainer_name: trainer.displayName, member_name: `Held client ${index}`, member_code: `H-${index}`, programme_name: 'Frozen programme', state: index ? 'closed' : 'expired', sessions_total: 8, sessions_used: 1, sessions_remaining: 7, sessions_scheduled: index ? 4 : 3, starts_on: '2026-01-01', expires_on: '2026-09-01', timezone: 'Asia/Kolkata', trainer_active: true })), scheduledCount: 7, overLimit: false }, error: null }, trainers: [trainer, { ...trainer, staffId: destinationId, displayName: 'Next Coach' }], viewer, nouns, ...overrides };
}
function chooseDestination(view: unknown) {
  const selects = labelledControls(view).filter(field => field.node.type === 'select'); const destination = selects.find(field => /(?:to|target|destination|new)\s*(?:coach|trainer)/i.test(field.label)) ?? selects.at(-1); expect(destination).toBeTruthy(); const change = destination?.node.props?.onChange; expect(change).toBeTypeOf('function'); (change as (event: unknown) => unknown)({ target: { value: destinationId } });
}
function chooseAll(view: unknown) {
  const options = labelledControls(view).filter(field => /all/i.test(field.label)); const all = options.find(field => ['radio', 'checkbox'].includes(String(field.node.props?.type)));
  if (all) { const change = all.node.props?.onChange; expect(change).toBeTypeOf('function'); (change as (event: unknown) => unknown)({ target: { checked: true, value: all.node.props?.value ?? 'all' } }); return; }
  const button = flatten(view).find(node => node.type === 'button' && /all.*(?:active|packs)|(?:active|packs).*all/i.test(text(node))); expect(button, 'An all-source choice is exposed').toBeTruthy(); (button?.props?.onClick as () => unknown)();
}

describe('held explicit frozen source and real reassignment POST', () => {
  it.each([
    { caseName: 'null source never inferred from viewer or rows', override: { fromStaffId: null } },
    { caseName: 'empty valid source remains zero and cannot submit all', override: { candidates: { data: { packs: [], scheduledCount: 0, overLimit: false }, error: null } } },
    { caseName: 'foreign-source row fails closed', override: { candidates: { data: { packs: [{ order_id: heldOrderA, trainer_staff_id: destinationId, sessions_scheduled: 3 }], scheduledCount: 3, overLimit: false }, error: null } } },
  ])('$caseName', async ({ override }) => {
    const component = await exported(controls[1].path, controls[1].name); const props = reassignProps(override); const view = render(component, props); expect(flatten(view).filter(node => node.type === 'button' && /confirm|reassign|review/i.test(text(node)) && !node.props?.disabled)).toEqual([]); expect(boundary.fetch).not.toHaveBeenCalled();
  });
  it.each((['gym_owner', 'gym_manager'] satisfies HeldRole[]))('all-source for %s submits exact provided source and omits orderIds', async role => {
    const component = await exported(controls[1].path, controls[1].name); const props = reassignProps({ viewer: { ...viewer, role } }); boundary.fetch.mockResolvedValue(acceptedResponse({ results: [{ orderId: heldOrderA, changed: true, cancelledSessions: 3 }, { orderId: heldOrderB, changed: true, cancelledSessions: 4 }] }));
    chooseDestination(render(component, props)); changeField(render(component, props), /reason/i, 'Trainer moving away'); chooseAll(render(component, props)); await activate(render(component, props), /reassign|review|continue/i); expect(boundary.fetch).not.toHaveBeenCalled(); const confirmation = render(component, props); expect(text(confirmation)).toMatch(/7\s+(?:scheduled\s+)?sessions/i); expect(text(confirmation)).toMatch(/notif/i); await activate(confirmation, /confirm/i);
    expect(sent()).toEqual({ url: '/api/pt-reassignments', body: { fromStaffId: viewer.staffId, toStaffId: destinationId, reason: 'Trainer moving away' } }); expect(boundary.refresh).toHaveBeenCalledTimes(1);
  });
  it('explicit source selection submits only selected IDs and their scheduled count', async () => {
    const component = await exported(controls[1].path, controls[1].name); const props = reassignProps(); boundary.fetch.mockResolvedValue(acceptedResponse({ results: [{ orderId: heldOrderA, changed: true, cancelledSessions: 3 }] })); chooseDestination(render(component, props)); changeField(render(component, props), /reason/i, 'Trainer moving away');
    const view = render(component, props); const checkbox = labelledControls(view).find(field => field.node.props?.type === 'checkbox' && (field.node.props?.value === heldOrderA || /Held client 0|H-0/.test(field.label))); expect(checkbox, 'Pack selection identifies the selected member').toBeTruthy(); (checkbox?.node.props?.onChange as (event: unknown) => unknown)({ target: { checked: true, value: heldOrderA } }); await activate(render(component, props), /reassign|review|continue/i); const confirmation = render(component, props); expect(text(confirmation)).toMatch(/3\s+(?:scheduled\s+)?sessions/i); expect(text(confirmation)).toMatch(/notif/i); await activate(confirmation, /confirm/i);
    expect(sent()).toEqual({ url: '/api/pt-reassignments', body: { fromStaffId: viewer.staffId, toStaffId: destinationId, orderIds: [heldOrderA], reason: 'Trainer moving away' } });
  });
  it('over-cap all-source cannot POST a silently truncated command', async () => {
    const component = await exported(controls[1].path, controls[1].name); const props = reassignProps({ candidates: { data: { packs: Array.from({ length: 101 }, (_, index) => ({ order_id: `80200000-0000-4000-8000-${String(index + 100).padStart(12, '0')}`, trainer_staff_id: viewer.staffId, sessions_scheduled: 1 })), scheduledCount: 101, overLimit: true }, error: null } }); chooseDestination(render(component, props)); changeField(render(component, props), /reason/i, 'Trainer moving away'); chooseAll(render(component, props)); const view = render(component, props); expect(text(view)).toMatch(/100|too many|limit/i); expect(flatten(view).filter(node => node.type === 'button' && /confirm|reassign/i.test(text(node)) && !node.props?.disabled)).toEqual([]); expect(boundary.fetch).not.toHaveBeenCalled();
  });
  it('source A-B-A revokes an already prepared confirmation handler permanently', async () => {
    const component = await exported(controls[1].path, controls[1].name); const props = reassignProps(); chooseDestination(render(component, props)); changeField(render(component, props), /reason/i, 'Trainer moving away'); chooseAll(render(component, props)); await activate(render(component, props), /reassign|review|continue/i); const confirmation = render(component, props); const retained = flatten(confirmation).find(node => node.type === 'button' && /confirm/i.test(text(node)))?.props?.onClick ?? flatten(confirmation).find(node => node.type === 'form')?.props?.onSubmit; expect(retained).toBeTypeOf('function'); render(component, { ...props, fromStaffId: destinationId, candidates: { data: { packs: [], scheduledCount: 0, overLimit: false }, error: null } }); render(component, props); await (retained as (event: unknown) => unknown)({ preventDefault: () => undefined }); expect(boundary.fetch).not.toHaveBeenCalled();
  });
  it.each(['', 'xy', 'x'.repeat(201)])('invalid required reassignment reason %j never becomes a POST', async reason => {
    const component = await exported(controls[1].path, controls[1].name); const props = reassignProps(); chooseDestination(render(component, props)); changeField(render(component, props), /reason/i, reason); chooseAll(render(component, props)); const view = render(component, props); const button = flatten(view).find(node => node.type === 'button' && /reassign|review/i.test(text(node)) && !node.props?.disabled); if (button) await activate(view, /reassign|review/i); expect(boundary.fetch).not.toHaveBeenCalled(); expect(text(render(component, props))).toMatch(/reason|characters|required/i);
  });
});

describe('held actual console service-command envelopes', () => {
  it.each((['gym_owner', 'gym_manager', 'front_desk'] satisfies HeldRole[]))('gym cancel by %s sends only confirmed session/reason', async role => {
    const component = await exported(controls[0].path, controls[0].name); const props = { booking, viewer: { ...viewer, role }, nouns }; boundary.fetch.mockResolvedValue(acceptedResponse({ sessionId: booking.session_id, status: 'cancelled_by_gym', replayed: false })); await activate(render(component, props), /cancel/i); expect(boundary.fetch).not.toHaveBeenCalled(); changeField(render(component, props), /reason/i, 'Trainer unavailable'); await activate(render(component, props), /confirm/i); expect(sent()).toEqual({ url: '/api/pt-bookings/cancel', body: { sessionId: booking.session_id, reason: 'Trainer unavailable' } }); expect(boundary.refresh).toHaveBeenCalledTimes(1);
  });
  it.each((['gym_owner', 'gym_manager'] satisfies HeldRole[]))('late forfeiture waiver by %s requires a reason then sends the exact session', async role => {
    const component = await exported(controls[0].path, controls[0].name); const props = { booking: { ...booking, status: 'cancelled_by_member', consumed: true }, viewer: { ...viewer, role }, nouns }; boundary.fetch.mockResolvedValue(acceptedResponse({ sessionId: booking.session_id, orderId: heldOrderA, sessionsUsed: 0, replayed: false })); await activate(render(component, props), /waive/i); expect(boundary.fetch).not.toHaveBeenCalled(); changeField(render(component, props), /reason/i, 'Exceptional circumstances'); await activate(render(component, props), /confirm/i); expect(sent()).toEqual({ url: '/api/pt-forfeits/waive', body: { sessionId: booking.session_id, reason: 'Exceptional circumstances' } });
  });
  it.each(['', 'xy', 'x'.repeat(201)])('cancel reason outside 3..200 never writes (%j)', async reason => {
    const component = await exported(controls[0].path, controls[0].name); const props = { booking, viewer, nouns }; await activate(render(component, props), /cancel/i); changeField(render(component, props), /reason/i, reason); const view = render(component, props); const enabled = flatten(view).find(node => node.type === 'button' && /confirm/i.test(text(node)) && !node.props?.disabled); if (enabled) await activate(view, /confirm/i); expect(boundary.fetch).not.toHaveBeenCalled();
  });
  it.each((['gym_owner', 'gym_manager', 'trainer'] satisfies HeldRole[]))('profile save for %s uses the correct endpoint and bounded fields', async role => {
    const component = await exported(controls[2].path, controls[2].name); const props = { ...controls[2].props, viewer: { ...viewer, role }, nouns }; boundary.fetch.mockResolvedValue(acceptedResponse({ profileId: heldOrderA })); changeField(render(component, props), /bio/i, 'Updated held biography'); await activate(render(component, props), /save/i); const command = sent(); expect(command.url).toBe(role === 'trainer' ? '/api/trainer-profiles/own' : '/api/trainer-profiles'); expect(command.body).toEqual(role === 'trainer' ? { bio: 'Updated held biography', specialities: ['Strength'] } : { staffId: viewer.staffId, bio: 'Updated held biography', specialities: ['Strength'], photoAssetId: null, isListed: false }); expect(boundary.refresh).toHaveBeenCalledTimes(1);
  });
  it('owner listing changes explicitly preserve the public profile command shape', async () => {
    const component = await exported(controls[2].path, controls[2].name); const props = { ...controls[2].props, viewer, nouns }; boundary.fetch.mockResolvedValue(acceptedResponse({ profileId: heldOrderA })); changeField(render(component, props), /list/i, true); await activate(render(component, props), /save/i); expect(sent().body).toEqual({ staffId: viewer.staffId, bio: 'Held bio', specialities: ['Strength'], photoAssetId: null, isListed: true });
  });
  it('availability submits all three camelCase windows without cancelling sessions', async () => {
    const component = await exported(controls[3].path, controls[3].name); const windows = [{ weekday: 1, startMinute: 480, endMinute: 540 }, { weekday: 3, startMinute: 600, endMinute: 660 }, { weekday: 5, startMinute: 720, endMinute: 780 }]; const props = { trainer, windows, viewer, nouns }; boundary.fetch.mockResolvedValue(acceptedResponse({ windows: 3 })); await activate(render(component, props), /save/i); expect(sent()).toEqual({ url: '/api/trainer-availability', body: { staffId: viewer.staffId, windows } }); expect(boundary.refresh).toHaveBeenCalledTimes(1);
  });
  it('time off submits inclusive selected dates and optional reason without cancelling standing bookings', async () => {
    const component = await exported(controls[4].path, controls[4].name); const props = { ...controls[4].props, viewer, nouns }; boundary.fetch.mockResolvedValue(acceptedResponse({ timeOffId: heldOrderA })); let view = render(component, props); const dates = labelledControls(view).filter(field => field.node.props?.type === 'date'); expect(dates).toHaveLength(2); dates.forEach((field, index) => (field.node.props?.onChange as (event: unknown) => unknown)({ target: { value: index ? '2027-04-08' : '2027-04-01' } })); view = render(component, props); changeField(view, /reason/i, 'Leave'); await activate(render(component, props), /add|save/i); expect(sent()).toEqual({ url: '/api/trainer-time-off', body: { staffId: viewer.staffId, startsOn: '2027-04-01', endsOn: '2027-04-08', reason: 'Leave' } });
  });
  it('time-off removal uses the entry ID rather than trainer or date IDs', async () => {
    const component = await exported(controls[4].path, controls[4].name); const props = { ...controls[4].props, entries: [{ id: heldOrderA, starts_on: '2027-04-01', ends_on: '2027-04-08', reason: 'Leave', removed_at: null }], viewer, nouns }; boundary.fetch.mockResolvedValue(acceptedResponse({ removed: true })); await activate(render(component, props), /remove/i); if (!boundary.fetch.mock.calls.length) await activate(render(component, props), /confirm/i); expect(sent()).toEqual({ url: '/api/trainer-time-off/remove', body: { timeOffId: heldOrderA } });
  });
  it('policy saves the three authoritative displayed settings only', async () => {
    const component = await exported(controls[5].path, controls[5].name); const props = { ...controls[5].props, viewer, nouns }; boundary.fetch.mockResolvedValue(acceptedResponse({ saved: true })); await activate(render(component, props), /save/i); expect(sent()).toEqual({ url: '/api/pt-policy', body: { cancelWindowHours: 24, lateCancelConsumes: true, sessionMinutes: 60 } }); expect(boundary.refresh).toHaveBeenCalledTimes(1);
  });
  it.each([{ saved: false }, { saved: 'true' }, {}, null])('malformed policy success body %j never creates fake success', async data => {
    const component = await exported(controls[5].path, controls[5].name); const props = { ...controls[5].props, viewer, nouns }; boundary.fetch.mockResolvedValue(acceptedResponse(data)); await activate(render(component, props), /save/i); expect(boundary.fetch).toHaveBeenCalledTimes(1); expect(boundary.refresh).not.toHaveBeenCalled(); expect(text(render(component, props))).toMatch(/try again|retry|couldn't|could not|failed|unable/i);
  });
  it('malformed policy error is sanitized instead of leaking server facts', async () => {
    const component = await exported(controls[5].path, controls[5].name); const props = { ...controls[5].props, viewer, nouns }; boundary.fetch.mockResolvedValue({ ok: false, status: 500, json: async () => ({ error: { code: 'UNKNOWN', message: 'PRIVATE SQL JWT contact@example.com' } }) }); await activate(render(component, props), /save/i); expect(boundary.refresh).not.toHaveBeenCalled(); expect(text(render(component, props))).not.toMatch(/PRIVATE|SQL|JWT|contact@/);
  });
});

