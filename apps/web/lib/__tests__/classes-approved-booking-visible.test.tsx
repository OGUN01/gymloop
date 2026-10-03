// Independently authored from frozen approved CLS declarations; no source or holdouts read.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { businessNouns, type MemberClassSession } from '@gymloop/shared';
import { MemberClassesView } from '../../app/member/classes/member-classes-view';


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
const initial: MemberClassSession = {
  sessionId: '74000000-0000-4000-8000-000000000001', serviceId: '74000000-0000-4000-8000-000000000002', branchId: '74000000-0000-4000-8000-000000000003',
  serviceName: 'Evening mobility', serviceDescription: 'Move comfortably', branchName: 'East studio', timezone: 'Asia/Kolkata', sessionDate: '2026-10-03',
  startsAt: '2026-10-03T18:00:00+05:30', endsAt: '2026-10-03T19:00:00+05:30', trainerName: 'Coach Kavya', capacity: 13, bookedCount: 9, spotsLeft: 4,
  sessionStatus: 'scheduled', myBookingId: null, myBookingStatus: null, availability: 'open', canCancel: false, cancelBy: '2026-10-03T16:00:00+05:30',
};
let nodes: Node[] = [];
let scope = 'member:A';
let read: (() => Promise<MemberClassSession[] | null>) | undefined;
function visit(value: unknown, path: string): void {
  if (Array.isArray(value)) { value.forEach((child, index) => visit(child, `${path}/${index}`)); return; }
  if (value === null || typeof value !== 'object' || !('type' in value) || !('props' in value)) return;
  const node = value as Node;
  if (typeof node.type === 'function') { const prior = seam.path; const cursor = seam.cursor; seam.path = path; seam.cursor = 0; const output: unknown = node.type(node.props); seam.path = prior; seam.cursor = cursor; visit(output, `${path}/render`); return; }
  nodes.push(node); visit(node.props.children, `${path}/children`);
}
function draw() { nodes = []; visit({ type: MemberClassesView, props: { sessions: [initial], today: '2026-10-03', nouns: businessNouns('gym'), cancelWindowHours: 99, scopeKey: scope, ...(read === undefined ? {} : { refreshSessions: read }) } }, 'root'); seam.effects.splice(0).forEach(effect => effect()); }
async function settle() { for (let i = 0; i < 16; i++) { await Promise.resolve(); draw(); } }
function words(value: unknown): string { if (typeof value === 'string' || typeof value === 'number') return String(value); if (Array.isArray(value)) return value.map(words).join(' '); if (value !== null && typeof value === 'object' && 'props' in value) return words((value as Node).props.children); return ''; }
function visible() { return nodes.map(node => words(node.props.children)).join(' ').replace(/\s+/g, ' '); }
function action(label: RegExp) { return [...nodes].reverse().find(node => typeof node.props.onClick === 'function' && [words(node.props.children), words(node.props['aria-label'])].some(value => label.test(value.trim()))); }
async function press(label: RegExp) { const node = action(label); expect(node, `web action ${label.source} exists`).toBeDefined(); if (!node) return; expect(node.props.disabled, `web action ${label.source} enabled`).not.toBe(true); if (typeof node.props.onClick === 'function') await node.props.onClick(); await settle(); }
function cleanup() { seam.stores.forEach(slots => slots.forEach(slot => slot.cleanup?.())); seam.stores.clear(); seam.effects = []; }
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(yes => { resolve = yes; }); return { promise, resolve }; }
const confirmation = /^Confirm(?: booking)?$|^Book class$/;
async function tryConfirm() { const node = action(confirmation); if (node && node.props.disabled !== true && typeof node.props.onClick === 'function') { await node.props.onClick(); await settle(); } }
beforeEach(() => {
  cleanup(); vi.clearAllMocks(); vi.useFakeTimers(); vi.setSystemTime(new Date('2026-10-03T10:00:00+05:30')); scope = 'member:A'; read = undefined;
  vi.stubGlobal('navigator', { onLine: true });
  const windowHost = new EventTarget(); vi.stubGlobal('window', Object.assign(windowHost, { matchMedia: () => ({ matches: false, addEventListener: vi.fn(), removeEventListener: vi.fn() }) }));
  vi.stubGlobal('document', Object.assign(new EventTarget(), { body: { style: {}, appendChild: vi.fn(), removeChild: vi.fn() }, activeElement: null, querySelectorAll: () => [], getElementById: () => null }));
  vi.stubGlobal('fetch', seam.fetch); seam.fetch.mockResolvedValue({ ok: true, json: async () => ({ ok: true, data: { bookingId: '74000000-0000-4000-8000-000000000016', status: 'booked', spotsLeft: 3 } }) });
});
afterEach(() => { cleanup(); vi.unstubAllGlobals(); vi.useRealTimers(); });
describe('CLS approved actual web booking confirmation', () => {
  it('refreshes exact own schedule before enabling commitment and on reopening', async () => {
    const refresh = vi.fn().mockResolvedValue([initial]); read = refresh;
    draw(); await settle(); await press(/^Book$/);
    expect(refresh).toHaveBeenCalledTimes(1);
    expect(refresh.mock.calls[0]).toEqual([]);
    expect(seam.fetch).not.toHaveBeenCalled();
    expect(visible()).toMatch(/16:00|4:00\s*[pP][mM]/);
    await press(/^Back$|^Close(?: confirmation)?$|^Cancel$/); await press(/^Book$/);
    expect(refresh).toHaveBeenCalledTimes(2);
    await press(confirmation);
    expect(seam.fetch).toHaveBeenCalledTimes(1);
    const request = seam.fetch.mock.calls[0];
    expect(request?.[0]).toBe('/api/class-bookings');
    expect(JSON.parse(String((request?.[1] as { body?: unknown }).body))).toEqual({ sessionId: initial.sessionId });
  });

  it('keeps confirmation unavailable while the preparation read is pending', async () => {
    const waiting = deferred<MemberClassSession[] | null>(); read = () => waiting.promise;
    draw(); await settle(); const book = action(/^Book$/);
    expect(book).toBeDefined();
    const pending = typeof book?.props.onClick === 'function' ? book.props.onClick() : undefined;
    await settle(); await tryConfirm();
    expect(seam.fetch).not.toHaveBeenCalled();
    waiting.resolve([initial]); await pending; await settle();
    await press(confirmation); expect(seam.fetch).toHaveBeenCalledTimes(1);
  });

  it.each([
    ['failed', null],
    ['missing exact row', []],
    ['wrong session', [{ ...initial, sessionId: '74000000-0000-4000-8000-000000000099' }]],
    ['missing deadline', [{ ...initial, cancelBy: null }]],
    ['full', [{ ...initial, availability: 'full' as const, spotsLeft: 0 }]],
    ['closed', [{ ...initial, availability: 'closed' as const }]],
    ['cancelled', [{ ...initial, availability: 'cancelled' as const, sessionStatus: 'cancelled' as const }]],
  ])('does not commit %s refreshed preparation facts', async (_name, rows) => {
    read = async () => rows; draw(); await settle(); await press(/^Book$/); await tryConfirm();
    expect(seam.fetch).not.toHaveBeenCalled();
  });

  it('uses the refreshed deadline in its returned timezone instead of initial settings', async () => {
    read = async () => [{ ...initial, timezone: 'UTC', cancelBy: '2026-10-03T15:00:00+05:30' }];
    draw(); await settle(); await press(/^Book$/);
    expect(visible()).toMatch(/09:30|9:30\s*[aA][mM]/);
    expect(visible()).not.toMatch(/16:00|4:00\s*[pP][mM]/);
    await press(confirmation); expect(seam.fetch).toHaveBeenCalledTimes(1);
  });

  it('cannot commit a retained confirmation after permanent caller revocation', async () => {
    read = async () => [initial]; draw(); await settle(); await press(/^Book$/);
    const retained = action(confirmation)?.props.onClick; expect(retained).toBeTypeOf('function');
    scope = 'member:B'; draw(); await settle(); scope = 'member:A'; draw(); await settle();
    if (typeof retained === 'function') await retained(); await settle();
    expect(seam.fetch).not.toHaveBeenCalled();
  });
  it.each([
    ['read failure', null],
    ['missing exact row', []],
    ['lost deadline', [{ ...initial, cancelBy: null }]],
    ['capacity taken', [{ ...initial, availability: 'full' as const, spotsLeft: 0 }]],
  ])('cannot reuse prepared facts when confirmation sees %s', async (_name, rows) => {
    const refresh = vi.fn().mockResolvedValueOnce([initial]).mockResolvedValue(rows); read = refresh;
    draw(); await settle(); await press(/^Book$/); await press(confirmation);
    expect(refresh.mock.calls.length).toBeGreaterThan(1);
    expect(seam.fetch).not.toHaveBeenCalled();
  });
  it('requires renewed explicit booking confirmation when the current cutoff changes', async () => {
    const updated = { ...initial, cancelBy: '2026-10-03T15:00:00+05:30' };
    read = vi.fn().mockResolvedValueOnce([initial]).mockResolvedValue([updated]);
    draw(); await settle(); await press(/^Book$/); await press(confirmation);
    expect(seam.fetch).not.toHaveBeenCalled();
    expect(visible()).toMatch(/15:00|3:00\s*[pP][mM]/);
    await press(confirmation); expect(seam.fetch).toHaveBeenCalledTimes(1);
  });
  it('fails closed when current-caller refresh metadata is unavailable', async () => {
    read = undefined; draw(); await settle(); await press(/^Book$/); await tryConfirm();
    expect(seam.fetch).not.toHaveBeenCalled();
  });
});
