import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { ReactElement, ReactNode } from 'react';
import type { Database } from '../../../../packages/db/types/database';

type Role = Database['public']['Enums']['app_role'];
type Viewer = { role: Role | null; staffId: string | null; readOnly: boolean; scopeKey: string };
type Booking = Omit<Database['public']['Functions']['read_pt_bookings']['Returns'][number], 'cancelled_at'> & { cancelled_at: string | null };
type Pack = Database['public']['Functions']['read_pt_packs']['Returns'][number];
type Props = Record<string, unknown>;
type Component = (props: Props) => ReactNode | Promise<ReactNode>;
type Element = ReactElement<Props>;
type Slot = { value: unknown; deps?: readonly unknown[]; cleanup?: () => void };
type Controller = { slots: Slot[]; cursor: number; effects: (() => void)[]; live: boolean };
const runtime = vi.hoisted(() => ({ current: null as Controller | null, refresh: vi.fn(), audience: vi.fn(), readIdentity: vi.fn(), upload: vi.fn(), display: vi.fn(), nouns: vi.fn() }));
vi.mock('react', async importOriginal => {
  const actual = await importOriginal<typeof import('react')>();
  const controller = () => { if (!runtime.current) throw new Error('React controller boundary needs a rendered owner'); return runtime.current; };
  const changed = (a?: readonly unknown[], b?: readonly unknown[]) => !a || !b || a.length !== b.length || a.some((v, n) => !Object.is(v, b[n]));
  const state = <T,>(initial: T | (() => T)) => { const c = controller(); const index = c.cursor++; if (!c.slots[index]) c.slots[index] = { value: typeof initial === 'function' ? (initial as () => T)() : initial }; return [c.slots[index]?.value, (value: T | ((prior: T) => T)) => { if (c.live) { const slot = c.slots[index]; if (slot) slot.value = typeof value === 'function' ? (value as (prior: T) => T)(slot.value as T) : value; } }] as const; };
  const ref = <T,>(value: T) => { const c = controller(); const index = c.cursor++; c.slots[index] ??= { value: { current: value } }; return c.slots[index]?.value; };
  const memo = <T,>(make: () => T, deps?: readonly unknown[]) => { const c = controller(); const index = c.cursor++; const old = c.slots[index]; if (!old || changed(old.deps, deps)) c.slots[index] = { value: make(), ...(deps ? { deps } : {}) }; return c.slots[index]?.value; };
  const effect = (make: () => void | (() => void), deps?: readonly unknown[]) => { const c = controller(); const index = c.cursor++; const old = c.slots[index]; if (!old || changed(old.deps, deps)) { old?.cleanup?.(); const slot: Slot = { value: null, ...(deps ? { deps } : {}) }; c.slots[index] = slot; c.effects.push(() => { const cleanup = make(); if (typeof cleanup === 'function') slot.cleanup = cleanup; }); } };
  return { ...actual, useState: state, useReducer: <T, A>(reduce: (s: T, a: A) => T, initial: T) => { const [value, set] = state(initial); return [value, (action: A) => set(prior => reduce(prior, action))]; }, useRef: ref, useMemo: memo, useCallback: <T,>(fn: T, deps?: readonly unknown[]) => memo(() => fn, deps), useEffect: effect, useLayoutEffect: effect, useId: () => memo(() => 'visible-control-id', []), useTransition: () => [false, (fn: () => void) => fn()], useSyncExternalStore: (_subscribe: unknown, snapshot: () => unknown) => snapshot() };
});
vi.mock('next/navigation', () => ({ useRouter: () => ({ refresh: runtime.refresh, push: vi.fn(), replace: vi.fn() }), notFound: () => { throw new Error('NEXT_NOT_FOUND'); }, redirect: () => { throw new Error('NEXT_REDIRECT'); } }));
vi.mock('next/link', () => ({ default: ({ children, ...props }: Props) => ({ type: 'a', props: { ...props, children }, key: null, $$typeof: Symbol.for('react.transitional.element') }) }));
vi.mock('next/image', () => ({ default: (props: Props) => ({ type: 'img', props, key: null, $$typeof: Symbol.for('react.transitional.element') }) }));
vi.mock('../../lib/identity-session', () => ({ requireAudience: runtime.audience, readIdentity: runtime.readIdentity }));
vi.mock('../../lib/business-type', () => ({ loadBusinessNouns: runtime.nouns }));
vi.mock('../../lib/media-upload', () => ({ uploadMediaFile: runtime.upload }));
vi.mock('../../lib/media', () => ({ mediaDisplayUrl: runtime.display }));
vi.mock('../(console)/field', async () => { const React = await import('react'); return { inputClass: 'cl-input', Field: ({ label, children }: { label: string; children: ReactNode }) => React.createElement('label', {}, label, children) }; });

const staffId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const otherStaff = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const tenantId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const sessionId = '00000000-0000-4000-8000-000000000001';
const orderId = '00000000-0000-4000-8000-000000000002';
const viewer = (role: Role | null = 'gym_owner', readOnly = false): Viewer => ({ role, staffId: role === null ? null : staffId, readOnly, scopeKey: `${role ?? 'preview'}:${staffId}` });
const trainer = { staffId, displayName: 'Trainer One', isActive: true, qualification: 'Certified', timezone: 'Asia/Kolkata', branchName: 'East' };
const booking: Booking = { session_id: sessionId, order_id: orderId, member_id: '00000000-0000-4000-8000-000000000003', member_code: 'M001', member_name: 'Member One', trainer_staff_id: staffId, trainer_name: 'Trainer One', starts_at: '2027-01-01T08:00:00Z', ends_at: '2027-01-01T09:00:00Z', status: 'booked', timezone: 'Asia/Kolkata', consumed: false, cancelled_at: null, sessions_total: 12, sessions_used: 2, sessions_remaining: 7 };
const pack: Pack = { order_id: orderId, programme_name: 'Frozen PT programme', member_id: booking.member_id, member_code: booking.member_code, member_name: booking.member_name, trainer_staff_id: staffId, trainer_name: trainer.displayName, trainer_active: true, starts_on: '2026-01-01', expires_on: '2026-09-30', sessions_total: 12, sessions_used: 2, sessions_scheduled: 3, sessions_remaining: 10, state: 'expired', timezone: trainer.timezone };
let nouns: unknown;
let api: ReturnType<typeof vi.fn>;
const controllers: Controller[] = [];
function mount<P, R>(component: (p: P) => R, props: P) {
  const c: Controller = { slots: [], cursor: 0, effects: [], live: true }; controllers.push(c);
  let currentProps = props;
  const render = (): R => { c.cursor = 0; runtime.current = c; try { const result = component(currentProps); for (const effect of c.effects.splice(0)) effect(); return result; } finally { runtime.current = null; } };
  return { render, update: (p: P) => { currentProps = p; return render(); }, unmount: () => { for (const slot of c.slots) slot.cleanup?.(); c.live = false; } };
}
function nodes(tree: ReactNode): Element[] {
  if (Array.isArray(tree)) return tree.flatMap(nodes);
  if (tree === null || typeof tree !== 'object' || !('props' in tree)) return [];
  const element = tree as Element; return [element, ...nodes(element.props.children as ReactNode)];
}
function text(tree: ReactNode): string {
  if (Array.isArray(tree)) return tree.map(text).join(' ');
  if (tree === null || tree === undefined || typeof tree === 'boolean') return '';
  if (typeof tree === 'string' || typeof tree === 'number') return String(tree);
  return typeof tree === 'object' && 'props' in tree ? text((tree as Element).props.children as ReactNode) : '';
}
function action(tree: ReactNode, pattern: RegExp): Element {
  const found = nodes(tree).find(n => (n.type === 'button' || n.props.role === 'button') && pattern.test(String(n.props['aria-label'] ?? text(n.props.children as ReactNode)))); expect(found, `Expected accessible action ${pattern} in ${text(tree)}`).toBeDefined();
  if (found && !found.props.onClick && found.props.type !== 'button') { const form = nodes(tree).find(n => n.type === 'form' && nodes(n.props.children as ReactNode).includes(found)); if (form?.props.onSubmit) return { ...found, props: { ...found.props, onClick: form.props.onSubmit } }; }
  return found!;
}
function invoke(node: Element, event = 'onClick', value?: unknown): unknown {
  const fn = node.props[event]; expect(typeof fn).toBe('function'); return (fn as (e: unknown) => unknown)({ preventDefault: () => undefined, target: { value, checked: value, files: value }, currentTarget: { value, checked: value, files: value } });
}
function input(tree: ReactNode, pattern: RegExp): Element {
  const label = nodes(tree).find(n => n.type === 'label' && pattern.test(text(n.props.children as ReactNode))); const candidates = label ? nodes(label.props.children as ReactNode) : nodes(tree).filter(n => pattern.test(String(n.props['aria-label'] ?? n.props.placeholder ?? n.props.name ?? ''))); const found = candidates.find(n => ['input', 'textarea', 'select'].includes(String(n.type))); expect(found, `Expected labelled input ${pattern}`).toBeDefined(); return found!;
}
async function expanded(tree: ReactNode): Promise<ReactNode> {
  if (Array.isArray(tree)) return Promise.all(tree.map(expanded));
  if (!tree || typeof tree !== 'object' || !('props' in tree)) return tree;
  const element = tree as Element;
  if (typeof element.type === 'function') return expanded(await mount(element.type as Component, element.props).render());
  return { ...element, props: { ...element.props, children: await expanded(element.props.children as ReactNode) } };
}
const paths = {
  bookings: '../(console)/training/page', packs: '../(console)/training/packs/page', trainers: '../(console)/training/trainers/page', detail: '../(console)/training/trainers/[staffId]/page', policy: '../(console)/training/policy/page',
  actions: '../(console)/training/booking-actions', reassign: '../(console)/training/reassign-panel', forms: '../(console)/training/trainers/[staffId]/trainer-forms', policyForm: '../(console)/training/policy/pt-policy-form', command: '../../lib/use-pt-command',
};
async function component(path: string, name: string): Promise<Component> { const module = await import(path) as Record<string, Component>; expect(module[name]).toBeTypeOf('function'); return module[name]!; }
function readBoundary(role: Role | null = 'gym_owner') {
  const rows: Record<string, unknown[]> = { staff: [{ id: staffId, role: 'trainer', full_name: trainer.displayName, is_active: true, qualification: 'Certified', branch_id: null, tenant_id: tenantId }], organizations: [{ id: tenantId, timezone: trainer.timezone }], branches: [], trainer_profiles: [{ bio: 'Independent bio', specialities: ['Strength'], photo_asset_id: null, is_listed: false }], trainer_availability: [], trainer_time_off: [], organization_settings: [{ pt_cancel_window_hours: 24, pt_late_cancel_consumes_session: true, pt_session_minutes: 60 }], addon_orders: [] };
  const failures = new Set<string>(); const accessed: string[] = [];
  const rpc = vi.fn(async (name: string) => { accessed.push(name); return failures.has(name) ? { data: null, error: { message: 'PRIVATE SQL ERROR' } } : { data: name === 'read_pt_bookings' ? [booking] : name === 'read_pt_packs' ? [pack] : [], error: null }; });
  const from = vi.fn((name: string) => { accessed.push(name); let single = false; const chain: Record<string, unknown> = {}; for (const method of ['select', 'eq', 'in', 'is', 'gt', 'gte', 'lte', 'lt', 'order', 'range', 'limit']) chain[method] = () => chain; for (const method of ['single', 'maybeSingle']) chain[method] = () => { single = true; return chain; }; chain.then = (resolve: (v: unknown) => unknown) => Promise.resolve(failures.has(name) ? { data: null, error: { message: 'PRIVATE SQL ERROR' } } : { data: single ? rows[name]?.[0] ?? null : rows[name] ?? [], error: null }).then(resolve); return chain; });
  const supabase = { from, rpc }; const identity = role === null ? { kind: 'impersonation', tenantId, userId: tenantId, impersonationSessionId: orderId } : { kind: 'staff', tenantId, userId: tenantId, staffId, role };
  runtime.audience.mockImplementation(async (audience: string) => { expect(audience).toBe('console'); expect(accessed).toEqual([]); return { supabase, identity }; });
  runtime.readIdentity.mockResolvedValue({ supabase, identity, signedIn: true, authenticatedUser: true });
  return { rows, failures, accessed, rpc, from };
}
async function page(path: string, props: Props = {}) { const Page = await component(path, 'default'); return expanded(await mount(Page, props).render()); }
async function ownControl(path: string, name: string, props: Props) { const C = await component(path, name); const harness = mount(C, props); return { ...harness, tree: await expanded(await harness.render()) }; }
async function flush() { await Promise.resolve(); await Promise.resolve(); }
function deferred<T>() { let resolve!: (v: T) => void; let reject!: (e: unknown) => void; const promise = new Promise<T>((yes, no) => { resolve = yes; reject = no; }); return { promise, resolve, reject }; }
beforeEach(async () => {
  vi.clearAllMocks(); const shared = await import('@gymloop/shared'); nouns = shared.businessNouns('dance'); runtime.nouns.mockResolvedValue(nouns); runtime.display.mockResolvedValue(null); runtime.upload.mockResolvedValue({ assetId: orderId });
  api = vi.fn().mockResolvedValue(new Response(JSON.stringify({ data: { saved: true, sessionId, status: 'cancelled_by_gym', profileId: orderId, windows: 3, timeOffId: orderId, removed: true, sessionsUsed: 1, results: [] }, error: null }), { status: 200, headers: { 'content-type': 'application/json' } })); vi.stubGlobal('fetch', api);
  const events = new EventTarget(); vi.stubGlobal('window', events); vi.stubGlobal('navigator', { onLine: true });
});

function posted(path: string): Props {
  const call = api.mock.calls.find(c => c[0] === path); expect(call, `Expected POST ${path}`).toBeDefined(); const request = call?.[1] as RequestInit;
  expect(request.method).toBe('POST'); expect(JSON.stringify(request.headers ?? {})).not.toMatch(/authorization|service_role/i); return JSON.parse(String(request.body)) as Props;
}
async function change(h: { render: () => ReactNode | Promise<ReactNode> }, pattern: RegExp, value: unknown) { invoke(input(await expanded(await h.render()), pattern), 'onChange', value); return expanded(await h.render()); }
const profileProps = () => ({ trainer, profile: { bio: 'Bio', specialities: ['Strength'], photo_asset_id: null, is_listed: false }, imageUrl: null, viewer: viewer(), nouns });
const reassignmentProps = () => ({ fromStaffId: staffId, candidates: { data: { packs: [pack], scheduledCount: 3, overLimit: false }, error: null }, trainers: [trainer, { ...trainer, staffId: otherStaff, displayName: 'Trainer Two' }], viewer: viewer(), nouns });

describe('PTF actual console controls and ordinary cookie POST fields', () => {
  it.each(['gym_owner', 'gym_manager', 'front_desk'] as const)('%s cancellation asks reason and confirmation before exact body', async role => {
    const h = await ownControl(paths.actions, 'BookingRowActions', { booking, viewer: viewer(role), nouns }); invoke(action(h.tree, /cancel/i)); await flush(); let tree = await expanded(await h.render()); expect(api).not.toHaveBeenCalled();
    const confirm = action(tree, /confirm|cancel .*session|cancel .*lesson/i); if (!confirm.props.disabled) invoke(confirm); await flush(); expect(api).not.toHaveBeenCalled();
    tree = await change(h, /reason/i, 'Owner requested cancellation'); invoke(action(tree, /confirm|cancel .*session|cancel .*lesson/i)); await flush(); expect(posted('/api/pt-bookings/cancel')).toEqual({ sessionId, reason: 'Owner requested cancellation' });
  });
  it.each(['trainer', null] as const)('%s gets no gym cancel or waive', async role => { const h = await ownControl(paths.actions, 'BookingRowActions', { booking, viewer: viewer(role, role === null), nouns }); expect(nodes(h.tree).filter(n => n.type === 'button' && /cancel|waive/i.test(text(n.props.children as ReactNode)))).toEqual([]); });
  it.each(['gym_owner', 'gym_manager'] as const)('%s waiver uses effective consumed late cancel and required reason', async role => {
    const h = await ownControl(paths.actions, 'BookingRowActions', { booking: { ...booking, status: 'cancelled_by_member', consumed: true, cancelled_at: '2026-01-01T08:00:00Z' }, viewer: viewer(role), nouns }); invoke(action(h.tree, /waive/i)); expect(api).not.toHaveBeenCalled(); const tree = await change(h, /reason/i, 'Owner approved waiver'); invoke(action(tree, /confirm|waive/i)); await flush(); expect(posted('/api/pt-forfeits/waive')).toEqual({ sessionId, reason: 'Owner approved waiver' });
  });
  it.each(['front_desk', 'trainer', null] as const)('%s gets no consumed-cancel waiver', async role => { const h = await ownControl(paths.actions, 'BookingRowActions', { booking: { ...booking, status: 'cancelled_by_member', consumed: true }, viewer: viewer(role, role === null), nouns }); expect(nodes(h.tree).filter(n => n.type === 'button' && /waive/i.test(text(n.props.children as ReactNode)))).toEqual([]); });
  it('nonconsumed cancellation never offers waiver', async () => { const h = await ownControl(paths.actions, 'BookingRowActions', { booking: { ...booking, status: 'cancelled_by_member', consumed: false }, viewer: viewer(), nouns }); expect(nodes(h.tree).filter(n => n.type === 'button' && /waive/i.test(text(n.props.children as ReactNode)))).toEqual([]); });
  it('own trainer profile has only bio and specialities, own route and strict own fields', async () => {
    const h = await ownControl(paths.forms, 'TrainerProfileForm', { ...profileProps(), viewer: viewer('trainer') }); expect(nodes(h.tree).filter(n => n.props.type === 'file' || n.props.type === 'checkbox')).toEqual([]); expect(text(h.tree)).not.toMatch(/upload|listed|unlisted/i);
    const tree = await change(h, /bio/i, 'Updated bio'); invoke(action(tree, /save/i)); await flush(); expect(posted('/api/trainer-profiles/own')).toEqual({ bio: 'Updated bio', specialities: ['Strength'] });
  });
  it.each(['gym_owner', 'gym_manager'] as const)('%s full profile sends current photo and listing facts', async role => {
    const h = await ownControl(paths.forms, 'TrainerProfileForm', { ...profileProps(), viewer: viewer(role) }); const tree = await change(h, /bio/i, 'Updated bio'); invoke(action(tree, /save/i)); await flush(); expect(posted('/api/trainer-profiles')).toEqual({ staffId, bio: 'Updated bio', specialities: ['Strength'], photoAssetId: null, isListed: false });
  });
  it.each(['front_desk', null] as const)('%s has no editable trainer controls', async role => { for (const name of ['TrainerProfileForm', 'TrainerAvailabilityEditor', 'TrainerTimeOffPanel']) { const h = await ownControl(paths.forms, name, { ...profileProps(), windows: [], entries: [], bookings: { data: [], error: null }, viewer: viewer(role, role === null) }); expect(nodes(h.tree).filter(n => ['input', 'textarea', 'select'].includes(String(n.type)) && !n.props.disabled && !n.props.readOnly)).toEqual([]); } });
  it('foreign trainer target exposes no self-edit actions', async () => { for (const name of ['TrainerProfileForm', 'TrainerAvailabilityEditor', 'TrainerTimeOffPanel']) { const h = await ownControl(paths.forms, name, { ...profileProps(), trainer: { ...trainer, staffId: otherStaff }, windows: [], entries: [], bookings: { data: [], error: null }, viewer: viewer('trainer') }); expect(nodes(h.tree).filter(n => n.type === 'button' && /save|add|remove/i.test(text(n.props.children as ReactNode)))).toEqual([]); } expect(api).not.toHaveBeenCalled(); });
  it.each(['gym_owner', 'gym_manager', 'trainer'] as const)('%s saves three windows without leaving and sends strict camelCase', async role => {
    const windows = [{ weekday: 1, startMinute: 360, endMinute: 480 }, { weekday: 3, startMinute: 540, endMinute: 660 }, { weekday: 5, startMinute: 720, endMinute: 840 }]; const h = await ownControl(paths.forms, 'TrainerAvailabilityEditor', { trainer, windows, viewer: viewer(role), nouns }); invoke(action(h.tree, /save/i)); await flush(); expect(posted('/api/trainer-availability')).toEqual({ staffId, windows });
  });
  it('inline overlap refuses saving offending windows', async () => {
    const h = await ownControl(paths.forms, 'TrainerAvailabilityEditor', { trainer, windows: [{ weekday: 1, startMinute: 360, endMinute: 480 }, { weekday: 1, startMinute: 420, endMinute: 540 }], viewer: viewer(), nouns }); const save = action(h.tree, /save/i); if (!save.props.disabled) invoke(save); await flush(); expect(text(await expanded(await h.render()))).toMatch(/overlap/i); expect(api).not.toHaveBeenCalled();
  });
  it('time-off lists existing standing booking beside range and does not cancel it', async () => {
    const h = await ownControl(paths.forms, 'TrainerTimeOffPanel', { trainer, entries: [{ id: orderId, starts_on: '2027-01-01', ends_on: '2027-01-01', reason: 'Leave', removed_at: null }], bookings: { data: [booking], error: null }, viewer: viewer(), nouns }); expect(text(h.tree)).toContain('Member One'); expect(text(h.tree)).toMatch(/remain|already booked|standing|still booked/i); expect(api).not.toHaveBeenCalled();
  });
  it.each(['gym_owner', 'gym_manager', 'trainer'] as const)('%s adds time off through exact public fields, never cancellation', async role => {
    const h = await ownControl(paths.forms, 'TrainerTimeOffPanel', { trainer, entries: [], bookings: { data: [booking], error: null }, viewer: viewer(role), nouns }); await change(h, /start|from/i, '2027-01-01'); await change(h, /end|to date/i, '2027-01-02'); const tree = await change(h, /reason/i, 'Leave'); invoke(action(tree, /add|save/i)); await flush(); expect(posted('/api/trainer-time-off')).toEqual({ staffId, startsOn: '2027-01-01', endsOn: '2027-01-02', reason: 'Leave' }); expect(api.mock.calls.some(c => String(c[0]).includes('cancel'))).toBe(false);
  });
  it('removes time off with id only and no deletion/booking mutation', async () => {
    const h = await ownControl(paths.forms, 'TrainerTimeOffPanel', { trainer, entries: [{ id: orderId, starts_on: '2027-01-01', ends_on: '2027-01-02', reason: 'Leave', removed_at: null }], bookings: { data: [], error: null }, viewer: viewer(), nouns }); invoke(action(h.tree, /remove/i)); await flush(); expect(posted('/api/trainer-time-off/remove')).toEqual({ timeOffId: orderId });
  });
  it('failed affected booking section has retry and no complete zero-count', async () => { const h = await ownControl(paths.forms, 'TrainerTimeOffPanel', { trainer, entries: [], bookings: { data: null, error: 'Please try again.' }, viewer: viewer(), nouns }); expect(text(h.tree)).toMatch(/try again|retry/i); expect(text(h.tree)).not.toMatch(/0 .*cancel|no .*booked/i); });
  it.each(['gym_owner', 'gym_manager'] as const)('%s saves exact current policy with consequences', async role => {
    const policy = { cancelWindowHours: 24, lateCancelConsumes: true, sessionMinutes: 60 }; const h = await ownControl(paths.policyForm, 'PtPolicyForm', { policy, viewer: viewer(role), nouns }); expect(text(h.tree)).toMatch(/cancel/i); expect(text(h.tree)).toMatch(/use|consume/i); expect(text(h.tree)).toMatch(/minute|duration|length/i); invoke(action(h.tree, /save/i)); await flush(); expect(posted('/api/pt-policy')).toEqual(policy);
  });
  it.each(['front_desk', 'trainer', null] as const)('%s never gets policy save', async role => { const h = await ownControl(paths.policyForm, 'PtPolicyForm', { policy: { cancelWindowHours: 24, lateCancelConsumes: true, sessionMinutes: 60 }, viewer: viewer(role, role === null), nouns }); expect(nodes(h.tree).filter(n => n.type === 'button' && /save/i.test(text(n.props.children as ReactNode)))).toEqual([]); });
  it.each(['front_desk', 'trainer', null] as const)('%s never gets reassignment', async role => { const h = await ownControl(paths.reassign, 'ReassignPacksPanel', { ...reassignmentProps(), viewer: viewer(role, role === null) }); expect(nodes(h.tree).filter(n => n.type === 'button' && /reassign|confirm/i.test(text(n.props.children as ReactNode)))).toEqual([]); });
  it.each(['null-source', 'empty', 'foreign', 'failed'] as const)('reassignment %s fails closed with no all-source submission', async fault => {
    const props = reassignmentProps(); const h = await ownControl(paths.reassign, 'ReassignPacksPanel', { ...props, fromStaffId: fault === 'null-source' ? null : staffId, candidates: fault === 'failed' ? { data: null, error: 'Please try again.' } : { data: { packs: fault === 'empty' ? [] : fault === 'foreign' ? [{ ...pack, trainer_staff_id: otherStaff }] : [pack], scheduledCount: fault === 'empty' ? 0 : 3, overLimit: false }, error: null } });
    for (const node of nodes(h.tree).filter(n => n.type === 'button' && /reassign|confirm/i.test(text(n.props.children as ReactNode)))) if (!node.props.disabled && node.props.onClick) invoke(node); await flush(); expect(api).not.toHaveBeenCalled(); if (fault === 'empty') expect(text(h.tree)).toMatch(/0|no .*active/i); if (fault === 'failed') expect(text(h.tree)).toMatch(/try again|retry/i);
  });
  it.each(['gym_owner', 'gym_manager'] as const)('%s all-source confirms exact count and notices, then sends exact supplied source', async role => {
    const h = await ownControl(paths.reassign, 'ReassignPacksPanel', { ...reassignmentProps(), viewer: viewer(role) }); await change(h, /target|to .*trainer|new .*trainer|move to/i, otherStaff); await change(h, /reason/i, 'Trainer leaving'); const tree = await expanded(await h.render()); invoke(action(tree, /reassign|review|continue/i)); await flush(); const confirm = await expanded(await h.render()); expect(text(confirm)).toMatch(/3/); expect(text(confirm)).toMatch(/notif/i); expect(api).not.toHaveBeenCalled(); invoke(action(confirm, /confirm/i)); await flush(); expect(posted('/api/pt-reassignments')).toEqual({ fromStaffId: staffId, toStaffId: otherStaff, reason: 'Trainer leaving' });
  });
  it('source switch permanently invalidates retained confirmation even after A→B→A', async () => {
    const props = reassignmentProps(); const h = await ownControl(paths.reassign, 'ReassignPacksPanel', props); await change(h, /target|to .*trainer|new .*trainer|move to/i, otherStaff); await change(h, /reason/i, 'Trainer leaving'); invoke(action(await expanded(await h.render()), /reassign|review|continue/i)); const old = action(await expanded(await h.render()), /confirm/i); h.update({ ...props, fromStaffId: otherStaff, candidates: { data: { packs: [{ ...pack, trainer_staff_id: otherStaff }], scheduledCount: 3, overLimit: false }, error: null } }); h.update(props); invoke(old); await flush(); expect(api).not.toHaveBeenCalled();
  });
  it('101 active packs do not silently truncate the all-source command', async () => { const props = reassignmentProps(); const packs = Array.from({ length: 101 }, (_, n) => ({ ...pack, order_id: `00000000-0000-4000-8000-${String(n + 1).padStart(12, '0')}` })); const h = await ownControl(paths.reassign, 'ReassignPacksPanel', { ...props, candidates: { data: { packs, scheduledCount: 303, overLimit: true }, error: null } }); expect(text(h.tree)).toMatch(/100/); expect(text(h.tree)).toMatch(/101|too many|select/i); expect(api).not.toHaveBeenCalled(); });
  it('photo upload shows uploading then verifying before profile attachment', async () => {
    const wait = deferred<{ assetId: string }>(); let stage: ((s: 'uploading' | 'verifying') => void) | undefined; runtime.upload.mockImplementation((_file: unknown, _kind: unknown, callback: typeof stage) => { stage = callback; callback?.('uploading'); return wait.promise; }); const h = await ownControl(paths.forms, 'TrainerProfileForm', profileProps()); const file = nodes(h.tree).find(n => n.type === 'input' && n.props.type === 'file'); expect(file).toBeDefined(); invoke(file!, 'onChange', [{ name: 'trainer.png', type: 'image/png' }]); await flush(); expect(text(await expanded(await h.render()))).toMatch(/upload/i); stage?.('verifying'); expect(text(await expanded(await h.render()))).toMatch(/verif/i); expect(api).not.toHaveBeenCalled(); wait.resolve({ assetId: orderId }); await flush(); invoke(action(await expanded(await h.render()), /save/i)); await flush(); expect(posted('/api/trainer-profiles')).toMatchObject({ staffId, photoAssetId: orderId });
  });
  it('profile A→B→A discards old upload completion', async () => {
    const wait = deferred<{ assetId: string }>(); runtime.upload.mockReturnValue(wait.promise); const props = profileProps(); const h = await ownControl(paths.forms, 'TrainerProfileForm', props); const file = nodes(h.tree).find(n => n.type === 'input' && n.props.type === 'file'); expect(file).toBeDefined(); invoke(file!, 'onChange', [{ name: 'trainer.png', type: 'image/png' }]); h.update({ ...props, trainer: { ...trainer, staffId: otherStaff } }); h.update(props); wait.resolve({ assetId: orderId }); await flush(); invoke(action(await expanded(await h.render()), /save/i)); await flush(); expect(posted('/api/trainer-profiles').photoAssetId).not.toBe(orderId);
  });
});
afterEach(() => { for (const c of controllers.splice(0)) { for (const slot of c.slots) slot.cleanup?.(); c.live = false; } vi.unstubAllGlobals(); });

describe('PTF-028 five actual server pages verify console audience before feature access', () => {
  it.each(['bookings', 'packs', 'trainers', 'detail', 'policy'] as const)('%s page calls its own audience boundary before any read', async name => {
    readBoundary(); const tree = await page(paths[name], { searchParams: Promise.resolve({ from: '2027-01-01T00:00:00Z', to: '2027-01-02T00:00:00Z' }), params: Promise.resolve({ staffId }) }); expect(runtime.audience).toHaveBeenCalledWith('console'); expect(text(tree)).not.toMatch(/PRIVATE SQL ERROR/);
  });
  it.each(['bookings', 'packs', 'trainers', 'detail', 'policy'] as const)('%s refuses unsupported audience without a feature read', async name => {
    await component(paths[name], 'default');
    const b = readBoundary('member'); try { await page(paths[name], { searchParams: Promise.resolve({}), params: Promise.resolve({ staffId }) }); } catch { /* The canonical route guard may redirect/not-found. */ } expect(runtime.audience).toHaveBeenCalled(); expect(b.accessed).toEqual([]);
  });
  it.each(['bookings', 'packs', 'trainers', 'detail', 'policy'] as const)('%s canonical preview has no mutation control', async name => {
    readBoundary(null); const tree = await page(paths[name], { searchParams: Promise.resolve({ from: '2027-01-01T00:00:00Z', to: '2027-01-02T00:00:00Z' }), params: Promise.resolve({ staffId }) });
    const mutable = nodes(tree).filter(n => n.type === 'button' && /save|cancel|waive|reassign|upload|remove|add time off/i.test(text(n.props.children as ReactNode))); expect(mutable).toEqual([]);
    expect(JSON.stringify(tree)).not.toMatch(/impersonationSessionId|userId|supabase/);
  });
  it.each(['front_desk', 'trainer'] as const)('policy page refuses %s before settings access', async role => { await component(paths.policy, 'default'); const b = readBoundary(role); try { await page(paths.policy); } catch { /* Not-found route is accepted. */ } expect(b.accessed).toEqual([]); });
  it('trainer foreign detail is refused before any feature access', async () => { await component(paths.detail, 'default'); const b = readBoundary('trainer'); try { await page(paths.detail, { params: Promise.resolve({ staffId: otherStaff }) }); } catch { /* Guarded not-found is accepted. */ } expect(b.accessed).toEqual([]); });
  it.each([{ status: 'made-up' }, { trainerStaffId: 'bad' }, { afterId: sessionId }, { afterStartsAt: '2027-01-01T00:00:00Z' }, { from: 'bad', to: 'bad' }])('booking page rejects malformed search params %j before RPC', async filters => {
    await component(paths.bookings, 'default');
    const b = readBoundary(); try { await page(paths.bookings, { searchParams: Promise.resolve(filters) }); } catch { /* Guarded not-found is accepted. */ } expect(b.rpc).not.toHaveBeenCalled();
  });
  it.each([{ state: 'made-up' }, { afterId: 'bad' }, { trainerStaffId: 'bad' }])('pack page rejects malformed filters %j before RPC', async filters => {
    await component(paths.packs, 'default');
    const b = readBoundary(); try { await page(paths.packs, { searchParams: Promise.resolve(filters) }); } catch { /* Guarded not-found is accepted. */ } expect(b.rpc).not.toHaveBeenCalled();
  });
  it('failed policy renders retry and never mounts a policy default form', async () => {
    const b = readBoundary(); b.failures.add('organization_settings'); const tree = await page(paths.policy); expect(text(tree)).toMatch(/try again|retry/i); expect(nodes(tree).filter(n => n.type === 'input' || n.type === 'select')).toEqual([]); expect(text(tree)).not.toContain('PRIVATE');
  });
  it('trainer detail keeps successful profile visible when availability fails without editable windows', async () => {
    const b = readBoundary(); b.failures.add('trainer_availability'); const tree = await page(paths.detail, { params: Promise.resolve({ staffId }) }); expect(text(tree)).toContain('Independent bio'); expect(text(tree)).toMatch(/try again|retry/i); expect(text(tree)).not.toContain('PRIVATE');
  });
  it('booking empty is the range state, not a failed-read empty', async () => {
    const b = readBoundary(); b.rpc.mockResolvedValue({ data: [], error: null }); const tree = await page(paths.bookings, { searchParams: Promise.resolve({ from: '2027-01-01T00:00:00Z', to: '2027-01-02T00:00:00Z' }) }); expect(text(tree)).toMatch(/no .*in this range/i); expect(nodes(tree).some(n => n.type === 'input' || n.type === 'select')).toBe(true);
  });
  it('booking failure has retry without masquerading as empty', async () => {
    const b = readBoundary(); b.failures.add('read_pt_bookings'); const tree = await page(paths.bookings, { searchParams: Promise.resolve({ from: '2027-01-01T00:00:00Z', to: '2027-01-02T00:00:00Z' }) }); expect(text(tree)).toMatch(/try again|retry/i); expect(text(tree)).not.toMatch(/no .*in this range/i);
  });
  it('pack renders expired unspent and separately scheduled facts without price invention', async () => {
    readBoundary(); const tree = await page(paths.packs, { searchParams: Promise.resolve({ state: 'expired' }) }); const copy = text(tree); expect(copy).toContain('Frozen PT programme'); expect(copy).toMatch(/expired/i); expect(copy).toMatch(/10/); expect(copy).toMatch(/3/); expect(copy).toContain('2026'); expect(copy).not.toMatch(/NaN|₹|INR/);
  });
  it('no-show uses zero and elapsed unmarked booking remains Booked with trainer-recording caption', async () => {
    const b = readBoundary(); b.rpc.mockResolvedValue({ data: [{ ...booking, starts_at: '2020-01-01T08:00:00Z', ends_at: '2020-01-01T09:00:00Z' }, { ...booking, session_id: orderId, status: 'no_show' }], error: null });
    const tree = await page(paths.bookings, { searchParams: Promise.resolve({ from: '2020-01-01T00:00:00Z', to: '2020-01-02T00:00:00Z' }) }); expect(text(tree)).toContain('Booked'); expect(text(tree)).toContain('No-show'); expect(text(tree)).toMatch(/waiting.*record/i); expect(text(tree)).not.toMatch(/scheduled|no_show|completed/);
  });
});

// This controller drives the actual hook; it does not replace command coordination.
type CommandResult = { pending: boolean; error: string | null; submit: (body: Props) => Promise<unknown> };
type CommandOptions = { viewer: Viewer; operationKey: string; nouns: unknown; canSubmit: (v: Viewer) => boolean; send: (body: Props) => Promise<unknown>; accepted: (result: unknown) => boolean; refresh: () => void };
async function command(options: CommandOptions) { const m = await import(paths.command) as { usePtCommand: (o: CommandOptions) => CommandResult }; return mount(m.usePtCommand, options); }
function options(overrides: Partial<CommandOptions> = {}): CommandOptions { return { viewer: viewer(), operationKey: sessionId, nouns, canSubmit: v => v.role === 'gym_owner', send: vi.fn().mockResolvedValue({ data: { saved: true } }), accepted: result => Boolean(result && typeof result === 'object' && 'data' in result), refresh: runtime.refresh, ...overrides }; }

describe('PTF-034 actual usePtCommand permanent lifetime and operation leases', () => {
  it('one in-flight write, exact body, accepted-envelope refresh only', async () => {
    const pending = deferred<unknown>(); const send = vi.fn().mockReturnValue(pending.promise); const h = await command(options({ send })); const retained = h.render(); const body = { sessionId, reason: 'Valid reason' }; const first = retained.submit(body); await retained.submit(body); expect(send).toHaveBeenCalledTimes(1); expect(send).toHaveBeenCalledWith(body); expect(h.render().pending).toBe(true); pending.resolve({ data: { saved: true } }); await first; expect(runtime.refresh).toHaveBeenCalledTimes(1); expect(h.render().pending).toBe(false);
  });
  it.each([null, { error: { code: 'retryable' } }, { unexpected: true }, { data: null, error: { code: 'pt_failed' } }])('nonaccepted result %j never refreshes or shows success', async response => {
    const send = vi.fn().mockResolvedValue(response); const h = await command(options({ send, accepted: result => Boolean(result && typeof result === 'object' && 'data' in result && result.data) })); await h.render().submit({ sessionId }); expect(runtime.refresh).not.toHaveBeenCalled(); expect(h.render().error).toBeTruthy(); expect(h.render().pending).toBe(false);
  });
  it('transport failures sanitize uncertainty and retry the same submitted target', async () => {
    const send = vi.fn().mockRejectedValueOnce(new Error('PRIVATE JWT SQL secret')).mockResolvedValueOnce({ data: { saved: true } }); const h = await command(options({ send })); const body = { sessionId, reason: 'Same reason' }; await h.render().submit(body); expect(h.render().error).toBeTruthy(); expect(h.render().error).not.toMatch(/PRIVATE|JWT|SQL|secret/); expect(runtime.refresh).not.toHaveBeenCalled(); await h.render().submit(body); expect(send).toHaveBeenNthCalledWith(2, body); expect(runtime.refresh).toHaveBeenCalledTimes(1);
  });
  it('positive offline blocks writes and reconnect never queues or auto-submits', async () => {
    vi.stubGlobal('navigator', { onLine: false }); const send = vi.fn(); const h = await command(options({ send })); await h.render().submit({ sessionId }); expect(send).not.toHaveBeenCalled(); expect(h.render().error).toMatch(/reconnect|try again|offline/i); vi.stubGlobal('navigator', { onLine: true }); window.dispatchEvent(new Event('online')); await flush(); expect(send).not.toHaveBeenCalled(); expect(runtime.refresh).not.toHaveBeenCalled();
  });
  it.each(['readOnly', 'role', 'scope', 'operation', 'unmount'] as const)('%s change invalidates retained submit and pending acceptance', async change => {
    const wait = deferred<unknown>(); const send = vi.fn().mockReturnValue(wait.promise); const original = options({ send }); const h = await command(original); const old = h.render(); const inflight = old.submit({ sessionId });
    if (change === 'unmount') h.unmount(); else h.update({ ...original, viewer: change === 'readOnly' ? viewer('gym_owner', true) : change === 'role' ? viewer('trainer') : change === 'scope' ? { ...original.viewer, scopeKey: 'new-gym' } : original.viewer, operationKey: change === 'operation' ? orderId : original.operationKey });
    await old.submit({ sessionId }); expect(send).toHaveBeenCalledTimes(1); wait.resolve({ data: { saved: true } }); await inflight; expect(runtime.refresh).not.toHaveBeenCalled(); if (change !== 'unmount') { expect(h.render().pending).toBe(false); expect(h.render().error).toBeNull(); }
  });
  it.each(['scope', 'operation'] as const)('%s A→B→A never revives first handlers', async change => {
    const send = vi.fn().mockResolvedValue({ data: { saved: true } }); const first = options({ send }); const h = await command(first); const old = h.render(); h.update(change === 'scope' ? { ...first, viewer: { ...first.viewer, scopeKey: 'B' } } : { ...first, operationKey: 'B' }); h.update(first); await old.submit({ sessionId }); expect(send).not.toHaveBeenCalled(); await h.render().submit({ sessionId }); expect(send).toHaveBeenCalledTimes(1);
  });
  it('current props permission is checked at submit without callback identity granting a lease', async () => {
    const send = vi.fn(); const first = options({ send }); const h = await command(first); const old = h.render(); h.update({ ...first, canSubmit: () => false }); await old.submit({ sessionId }); expect(send).not.toHaveBeenCalled();
  });
});
