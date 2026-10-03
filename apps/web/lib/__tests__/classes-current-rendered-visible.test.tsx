import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { businessNouns, type MemberClassSession } from '@gymloop/shared';
import MemberClassesPage from '../../app/member/classes/page';
import { ClassActions, useClassCommand } from '../../app/member/classes/class-actions';

type Props = Record<string, unknown>;
type Node = { type: unknown; props: Props };
type Slot = { value?: unknown; deps?: readonly unknown[] | undefined; cleanup?: (() => void) | undefined };
const seam = vi.hoisted(() => ({ stores: new Map<string, Slot[]>(), path: '', cursor: 0, effects: [] as Array<() => void>, refresh: vi.fn(), fetch: vi.fn(), audience: vi.fn(), schedule: vi.fn(), organization: vi.fn(), nouns: vi.fn() }));
vi.mock('react', async importOriginal => {
  const actual = await importOriginal<typeof import('react')>();
  function slot() { const slots = seam.stores.get(seam.path) ?? []; seam.stores.set(seam.path, slots); const index = seam.cursor++; slots[index] ??= {}; return slots[index]; }
  function same(a?: readonly unknown[], b?: readonly unknown[]) { return a !== undefined && b !== undefined && a.length === b.length && a.every((value, index) => Object.is(value, b[index])); }
  return { ...actual,
    useState: (initial: unknown) => { const current = slot(); if (!('value' in current)) current.value = typeof initial === 'function' ? initial() : initial; return [current.value, (next: unknown) => { current.value = typeof next === 'function' ? next(current.value) : next; }]; },
    useRef: (initial: unknown) => { const current = slot(); current.value ??= { current: initial }; return current.value; },
    useMemo: (factory: () => unknown, deps?: readonly unknown[]) => { const current = slot(); if (!same(current.deps, deps)) { current.value = factory(); current.deps = deps; } return current.value; },
    useCallback: (callback: unknown, deps?: readonly unknown[]) => { const current = slot(); if (!same(current.deps, deps)) { current.value = callback; current.deps = deps; } return current.value; },
    useEffect: (effect: () => void | (() => void), deps?: readonly unknown[]) => { const current = slot(); if (!same(current.deps, deps)) { current.deps = deps; seam.effects.push(() => { current.cleanup?.(); current.cleanup = effect() || undefined; }); } },
  };
});
vi.mock('react-dom', () => ({ createPortal: (children: unknown) => children }));
vi.mock('next/navigation', () => ({ useRouter: () => ({ refresh: seam.refresh }) }));
vi.mock('../../app/preview-context', () => ({ usePreviewReadOnly: () => false }));
vi.mock('../../lib/identity-session', () => ({ requireAudience: seam.audience }));
vi.mock('../../lib/classes', () => ({ loadMemberClassSchedule: seam.schedule, loadClassSettings: async () => ({ cancelWindowHours: 2, allowCrossBranch: false }) }));
vi.mock('../../lib/business-type', () => ({ loadBusinessOrganization: seam.organization, loadBusinessNouns: seam.nouns }));
const booked: MemberClassSession = {
  sessionId: '74000000-0000-4000-8000-000000000001', serviceId: '74000000-0000-4000-8000-000000000002', branchId: '74000000-0000-4000-8000-000000000003',
  serviceName: 'Evening mobility', serviceDescription: 'Move comfortably', branchName: 'East studio', timezone: 'Asia/Kolkata', sessionDate: '2026-10-03',
  startsAt: '2026-10-03T18:00:00+05:30', endsAt: '2026-10-03T19:00:00+05:30', trainerName: 'Coach Kavya', capacity: 13, bookedCount: 9, spotsLeft: 4,
  sessionStatus: 'scheduled', myBookingId: '74000000-0000-4000-8000-000000000016', myBookingStatus: 'booked', availability: 'booked', canCancel: true, cancelBy: '2026-10-03T16:00:00+05:30',
};
let nodes: Node[] = [];
let scope = 'member:A';
let mode: 'command' | 'actions' = 'command';
let current: ReturnType<typeof useClassCommand>;
let read: (() => Promise<MemberClassSession | null>) | undefined;
function Probe() { current = Reflect.apply(useClassCommand, undefined, [scope]) as ReturnType<typeof useClassCommand>; return null; }
function visit(value: unknown, path: string): void {
  if (Array.isArray(value)) { value.forEach((child, index) => visit(child, `${path}/${index}`)); return; }
  if (value === null || typeof value !== 'object' || !('type' in value) || !('props' in value)) return;
  const node = value as Node;
  if (typeof node.type === 'function') { const prior = seam.path; const cursor = seam.cursor; seam.path = path; seam.cursor = 0; const output: unknown = node.type(node.props); seam.path = prior; seam.cursor = cursor; visit(output, `${path}/render`); return; }
  nodes.push(node); visit(node.props.children, `${path}/children`);
}
function draw() { nodes = []; visit({ type: mode === 'command' ? Probe : ClassActions, props: mode === 'command' ? {} : { session: booked, cancelWindowHours: 2, scopeKey: scope, ...(read === undefined ? {} : { refreshSession: read }) } }, 'root'); seam.effects.splice(0).forEach(effect => effect()); }
async function settle() { for (let i = 0; i < 16; i++) { await Promise.resolve(); draw(); } }
function words(value: unknown): string { if (typeof value === 'string' || typeof value === 'number') return String(value); if (Array.isArray(value)) return value.map(words).join(' '); if (value !== null && typeof value === 'object' && 'props' in value) return words((value as Node).props.children); return ''; }
function visible() { return nodes.map(node => words(node.props.children)).join(' ').replace(/\s+/g, ' '); }
function action(label: RegExp) { return [...nodes].reverse().find(node => typeof node.props.onClick === 'function' && [words(node.props.children), words(node.props['aria-label'])].some(value => label.test(value.trim()))); }
async function press(label: RegExp) { const node = action(label); expect(node, `web action ${label.source} exists`).toBeDefined(); if (!node) return; expect(node.props.disabled, `web action ${label.source} enabled`).not.toBe(true); if (typeof node.props.onClick === 'function') await node.props.onClick(); await settle(); }
function cleanup() { seam.stores.forEach(slots => slots.forEach(slot => slot.cleanup?.())); seam.stores.clear(); seam.effects = []; }
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(yes => { resolve = yes; }); return { promise, resolve }; }
const confirmation = /^Confirm(?: cancellation)?$|^Cancel booking$/;
beforeEach(() => {
  cleanup(); vi.clearAllMocks(); vi.useFakeTimers(); vi.setSystemTime(new Date('2026-10-03T10:00:00+05:30')); scope = 'member:A'; mode = 'command'; read = undefined;
  vi.stubGlobal('navigator', { onLine: true });
  const windowHost = new EventTarget(); vi.stubGlobal('window', Object.assign(windowHost, { matchMedia: () => ({ matches: false, addEventListener: vi.fn(), removeEventListener: vi.fn() }) }));
  vi.stubGlobal('document', Object.assign(new EventTarget(), { body: { style: {}, appendChild: vi.fn(), removeChild: vi.fn() }, activeElement: null, querySelectorAll: () => [], getElementById: () => null }));
  vi.stubGlobal('fetch', seam.fetch); seam.fetch.mockResolvedValue({ ok: true, json: async () => ({ ok: true, data: { bookingId: booked.myBookingId, status: 'cancelled_by_member' } }) });
});
afterEach(() => { cleanup(); vi.unstubAllGlobals(); vi.useRealTimers(); });
describe('CLS actual web command permanent lifetime', () => {
  it('discards a late refusal instead of adding old-caller feedback to a replacement', async () => {
    const waiting = deferred<{ ok: boolean; json(): Promise<unknown> }>(); seam.fetch.mockReturnValue(waiting.promise);
    draw(); await settle(); const pending = current.send('/api/class-bookings/cancel', { bookingId: booked.myBookingId }); await settle();
    scope = 'member:B'; draw(); await settle();
    waiting.resolve({ ok: false, json: async () => ({ ok: false, error: { code: 'cancel_window_closed', message: 'Old feedback sentinel' } }) });
    await pending; await settle();
    expect(current.message, 'replacement has no old refusal feedback').toBeFalsy();
    expect(seam.refresh, 'old refusal cannot refresh replacement').not.toHaveBeenCalled();
  });
  it.each(['unmount', 'A-B-A'] as const)('invalidates retained send after %s', async transition => {
    draw(); await settle(); const retained = current.send;
    if (transition === 'unmount') cleanup(); else { scope = 'member:B'; draw(); await settle(); scope = 'member:A'; draw(); await settle(); }
    const outcome = await retained('/api/class-bookings/cancel', { bookingId: booked.myBookingId });
    expect(seam.fetch, 'expired send cannot start fetch').not.toHaveBeenCalled();
    expect(outcome, 'expired send cannot return success').toBeNull();
    expect(seam.refresh, 'expired send cannot refresh replacement').not.toHaveBeenCalled();
  });
  it.each(['unmount', 'A-B-A'] as const)('discards late pending success after %s', async transition => {
    const waiting = deferred<{ ok: boolean; json(): Promise<unknown> }>(); seam.fetch.mockReturnValue(waiting.promise);
    draw(); await settle(); const pending = current.send('/api/class-bookings/cancel', { bookingId: booked.myBookingId }); await settle();
    expect(seam.fetch, 'authorized pending command started once').toHaveBeenCalledTimes(1);
    if (transition === 'unmount') cleanup(); else { scope = 'member:B'; draw(); await settle(); scope = 'member:A'; draw(); await settle(); }
    waiting.resolve({ ok: true, json: async () => ({ ok: true, data: { bookingId: booked.myBookingId, status: 'cancelled_by_member' } }) });
    expect(await pending, 'old continuation cannot consume late success').toBeNull();
    expect(seam.refresh, 'late old result cannot refresh').not.toHaveBeenCalled();
    if (transition !== 'unmount') { await settle(); expect(current.message, 'late result cannot alter feedback').toBeFalsy(); }
  });
});
describe('CLS actual web existing cancellation current facts', () => {
  it('does not replace a missing refreshed deadline with a client cancellation window', async () => {
    read = async () => ({ ...booked, cancelBy: null }); mode = 'actions'; draw(); await settle(); await press(/^Cancel(?: booking)?$/);
    const confirm = action(confirmation); if (confirm && confirm.props.disabled !== true && typeof confirm.props.onClick === 'function') { await confirm.props.onClick(); await settle(); }
    expect(seam.fetch, 'missing refreshed cutoff cannot authorize cancellation').not.toHaveBeenCalled();
    expect(visible(), 'no fabricated deadline replaces missing authoritative facts').not.toMatch(/16:00|4:00\s*[pP][mM]/);
  });
  it('fails closed without a current-session callback', async () => {
    mode = 'actions'; draw(); await settle();
    const cancel = action(/^Cancel(?: booking)?$/); if (cancel && cancel.props.disabled !== true && typeof cancel.props.onClick === 'function') { await cancel.props.onClick(); await settle(); }
    const confirm = action(confirmation); if (confirm && confirm.props.disabled !== true && typeof confirm.props.onClick === 'function') { await confirm.props.onClick(); await settle(); }
    expect(seam.fetch, 'missing current read cannot authorize a cancellation').not.toHaveBeenCalled();
  });
  it('refreshes before preparation and reopening and displays authoritative local cutoff', async () => {
    const refresh = vi.fn().mockResolvedValue(booked); read = refresh; mode = 'actions'; draw(); await settle();
    await press(/^Cancel(?: booking)?$/);
    expect(refresh, 'preparation performs current read').toHaveBeenCalledTimes(1);
    expect(visible(), 'local authoritative cutoff displayed').toMatch(/16:00|4:00\s*[pP][mM]/);
    await press(/^Keep booking$|^Close(?: confirmation)?$|^Back$|^Cancel$/); await press(/^Cancel(?: booking)?$/);
    expect(refresh, 'reopening refreshes current facts').toHaveBeenCalledTimes(2);
  });
  it('permits cancellation at the inclusive current cutoff with exact current booking id', async () => {
    const refresh = vi.fn().mockResolvedValue(booked); read = refresh; mode = 'actions'; draw(); await settle(); await press(/^Cancel(?: booking)?$/);
    vi.setSystemTime(new Date(booked.cancelBy!)); await press(confirmation);
    expect(refresh.mock.calls.length, 'confirm performs a second read').toBeGreaterThan(1);
    expect(seam.fetch, 'inclusive cutoff sends once').toHaveBeenCalledTimes(1);
    const request = seam.fetch.mock.calls[0]; expect(request?.[0], 'existing cancellation endpoint').toBe('/api/class-bookings/cancel');
    expect(JSON.parse(String((request?.[1] as { body?: unknown }).body)), 'exact current booking id only').toEqual({ bookingId: booked.myBookingId });
  });
  it('rechecks the clock when confirmation happens after the cutoff', async () => {
    read = async () => booked; mode = 'actions'; draw(); await settle(); await press(/^Cancel(?: booking)?$/);
    vi.setSystemTime(new Date('2026-10-03T16:00:00.001+05:30')); await press(confirmation);
    expect(seam.fetch, 'expired confirmation submits nothing').not.toHaveBeenCalled();
    expect(visible(), 'closed window states next action').toContain("It's too close to the start time to cancel online. Speak to the front desk if you can't make it.");
  });
  it('requires renewed confirmation after changed cancellation policy facts', async () => {
    const updated = { ...booked, cancelBy: '2026-10-03T15:00:00+05:30' };
    const refresh = vi.fn().mockResolvedValueOnce(booked).mockResolvedValue(updated); read = refresh; mode = 'actions'; draw(); await settle(); await press(/^Cancel(?: booking)?$/); await press(confirmation);
    expect(seam.fetch, 'changed displayed deadline cannot reuse old confirmation').not.toHaveBeenCalled();
    expect(visible(), 'new deadline replaces old facts').toMatch(/15:00|3:00\s*[pP][mM]/);
    await press(confirmation); expect(seam.fetch, 'renewed explicit confirmation sends once').toHaveBeenCalledTimes(1);
  });
  it.each([
    { name: 'failed current read', row: null },
    { name: 'missing deadline', row: { ...booked, cancelBy: null } },
    { name: 'wrong session', row: { ...booked, sessionId: '74000000-0000-4000-8000-000000000020' } },
    { name: 'cancelled session', row: { ...booked, sessionStatus: 'cancelled' as const } },
  ])('fails closed for $name during confirmation', async ({ row }) => {
    const refresh = vi.fn().mockResolvedValueOnce(booked).mockResolvedValue(row); read = refresh; mode = 'actions'; draw(); await settle(); await press(/^Cancel(?: booking)?$/); await press(confirmation);
    expect(seam.fetch, 'invalid current facts cannot authorize command').not.toHaveBeenCalled();
  });
});
describe('CLS actual server callback caller guard', () => {
  it.each(['replacement-member', 'replacement-user', 'replacement-tenant', 'refused', 'unchanged'] as const)('handles a %s caller with the frozen read guard', async change => {
    const identity = { kind: 'member', userId: '74000000-0000-4000-8000-000000000011', tenantId: '74000000-0000-4000-8000-000000000012', memberId: '74000000-0000-4000-8000-000000000013' };
    const client = { from: () => ({ select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: { branch_id: booked.branchId, timezone: booked.timezone }, error: null }) }) }) }) };
    seam.audience.mockResolvedValue({ identity, supabase: client }); seam.schedule.mockResolvedValue([booked]); seam.nouns.mockResolvedValue(businessNouns('gym'));
    seam.organization.mockResolvedValue({ data: { name: 'Fixture gym', business_type: 'gym', timezone: booked.timezone }, error: null });
    const tree = await MemberClassesPage();
    function callback(value: unknown): (() => Promise<unknown>) | null {
      if (Array.isArray(value)) { for (const child of value) { const found = callback(child); if (found) return found; } }
      if (value !== null && typeof value === 'object' && 'props' in value) {
        const props = (value as Node).props;
        if (typeof props.refreshSessions === 'function') return props.refreshSessions as () => Promise<unknown>;
        return callback(props.children);
      }
      return null;
    }
    const refresh = callback(tree); expect(refresh, 'actual member page wires a read-only refresh callback').toBeTypeOf('function');
    const reads = seam.schedule.mock.calls.length;
    if (change === 'refused') seam.audience.mockRejectedValue(new Error('Caller unavailable')); else if (change !== 'unchanged') seam.audience.mockResolvedValue({ identity: { ...identity, ...(change === 'replacement-member' ? { memberId: '74000000-0000-4000-8000-000000000015' } : change === 'replacement-user' ? { userId: '74000000-0000-4000-8000-000000000015' } : { tenantId: '74000000-0000-4000-8000-000000000015' }) }, supabase: client });
    const result = refresh ? await refresh() : undefined;
    if (change === 'unchanged') {
      expect(result, 'unchanged verified caller receives current bounded facts').toEqual([booked]);
      expect(seam.schedule.mock.calls.length, 'unchanged caller refreshes once').toBe(reads + 1);
      expect(seam.schedule.mock.calls[reads], 'refresh reuses original caller client and bounded window').toEqual(seam.schedule.mock.calls[0]);
      expect(seam.schedule.mock.calls[reads]?.length, 'feature reader receives only client and window').toBe(2);
    } else {
      expect(result, 'changed or refused caller returns null').toBeNull();
      expect(seam.schedule.mock.calls.length, 'feature reader never runs for changed caller').toBe(reads);
    }
  });
});
