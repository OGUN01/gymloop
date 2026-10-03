// Independently authored from frozen approved CLS declarations; no source or holdouts read.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { businessNouns, type MemberClassSession } from '@gymloop/shared';
import { ClassesPane } from '../../components/classes-pane';

type Props = Record<string, unknown>;
type Node = { type: unknown; props: Props; path?: string };
type Slot = { value?: unknown; deps?: readonly unknown[] | undefined; cleanup?: (() => void) | undefined };
const seam = vi.hoisted(() => ({
  stores: new Map<string, Slot[]>(), path: '', cursor: 0, effects: [] as Array<() => void>,
  loadMember: vi.fn(), loadTimetable: vi.fn(), loadRoster: vi.fn(), search: vi.fn(),
  book: vi.fn(), cancel: vi.fn(), deskBook: vi.fn(), deskCancel: vi.fn(), mark: vi.fn(),
  network: true, probe: vi.fn(), insideHelper: false, finalWait: null as Promise<{ isConnected: boolean; isInternetReachable: boolean }> | null, networkListener: null as null | ((state: { isConnected: boolean; isInternetReachable: boolean }) => void),
  context: {} as Props,
}));
vi.mock('react', async importOriginal => {
  const actual = await importOriginal<typeof import('react')>();
  function slot() {
    const slots = seam.stores.get(seam.path) ?? [];
    seam.stores.set(seam.path, slots);
    const index = seam.cursor++;
    slots[index] ??= {};
    return slots[index];
  }
  function same(a?: readonly unknown[], b?: readonly unknown[]) { return a !== undefined && b !== undefined && a.length === b.length && a.every((v, i) => Object.is(v, b[i])); }
  return { ...actual,
    useState: (initial: unknown) => {
      const current = slot();
      if (!('value' in current)) current.value = typeof initial === 'function' ? initial() : initial;
      return [current.value, (next: unknown) => { current.value = typeof next === 'function' ? next(current.value) : next; }];
    },
    useRef: (initial: unknown) => { const current = slot(); current.value ??= { current: initial }; return current.value; },
    useMemo: (factory: () => unknown, deps?: readonly unknown[]) => { const current = slot(); if (!same(current.deps, deps)) { current.value = factory(); current.deps = deps; } return current.value; },
    useCallback: (callback: unknown, deps?: readonly unknown[]) => { const current = slot(); if (!same(current.deps, deps)) { current.value = callback; current.deps = deps; } return current.value; },
    useEffect: (effect: () => void | (() => void), deps?: readonly unknown[]) => {
      const current = slot();
      if (!same(current.deps, deps)) { current.deps = deps; seam.effects.push(() => { current.cleanup?.(); current.cleanup = effect() || undefined; }); }
    },
  };
});
vi.mock('../../lib/mobile-context', () => ({ useMobile: () => seam.context }));
vi.mock('../../lib/use-business-nouns', () => ({ useBusinessNouns: () => seam.context.nouns }));
vi.mock('../../lib/classes', async importOriginal => {
  const actual = await importOriginal<Record<string, unknown>>();
  return { ...actual, loadMemberClasses: seam.loadMember, loadDeskTimetable: seam.loadTimetable, loadDeskRoster: seam.loadRoster,
    cancelClassBooking: (...args: unknown[]) => {
      seam.insideHelper = true;
      if (typeof actual.cancelClassBooking !== 'function') throw new Error('Public cancellation helper absent');
      return Reflect.apply(actual.cancelClassBooking, undefined, args);
    },
  };
});
vi.mock('../../lib/mobile-data', () => ({ loadDeskMembers: seam.search }));
vi.mock('expo-network', () => ({
  getNetworkStateAsync: seam.probe,
  addNetworkStateListener: (callback: typeof seam.networkListener) => { seam.networkListener = callback; return { remove: vi.fn() }; },
}));
vi.mock('expo-router', () => ({ router: { push: vi.fn(), replace: vi.fn() }, useRouter: () => ({ push: vi.fn(), replace: vi.fn() }), useLocalSearchParams: () => ({}) }));
vi.mock('react-native', () => ({ View: 'View', Text: 'Text', ScrollView: 'ScrollView', Pressable: 'Pressable', TextInput: 'TextInput', ActivityIndicator: 'ActivityIndicator', StyleSheet: { create: (styles: unknown) => styles }, Platform: { OS: 'android' } }));
vi.mock('../../components/ui', () => {
  const host = (name: string) => (props: Props) => ({ type: name, props });
  return {
    ActionButton: host('ActionButton'), Body: host('Body'), EmptyState: host('EmptyState'), ErrorRetry: host('ErrorRetry'), LoadingState: host('LoadingState'), Row: host('Row'), RowAction: host('RowAction'), SearchField: host('SearchField'),
    Sheet: (props: Props) => props.visible ? { type: 'Sheet', props } : null,
    SheetHeader: host('SheetHeader'), StateMessage: host('StateMessage'), Status: host('Status'),
  };
});
const memberA = { kind: 'member', userId: '74000000-0000-4000-8000-000000000011', tenantId: '74000000-0000-4000-8000-000000000012', memberId: '74000000-0000-4000-8000-000000000013' };
const session: MemberClassSession = {
  sessionId: '74000000-0000-4000-8000-000000000001', serviceId: '74000000-0000-4000-8000-000000000002', branchId: '74000000-0000-4000-8000-000000000003',
  serviceName: 'Evening mobility', serviceDescription: 'Move comfortably', branchName: 'East studio', timezone: 'Asia/Kolkata', sessionDate: '2026-10-03',
  startsAt: '2026-10-03T18:00:00+05:30', endsAt: '2026-10-03T19:00:00+05:30', trainerName: 'Coach Kavya', capacity: 13, bookedCount: 9, spotsLeft: 4,
  sessionStatus: 'scheduled', myBookingId: null, myBookingStatus: null, availability: 'open', canCancel: false, cancelBy: '2026-10-03T16:00:00+05:30',
};
const booked: MemberClassSession = { ...session, myBookingId: '74000000-0000-4000-8000-000000000016', myBookingStatus: 'booked', availability: 'booked', canCancel: true, cancelBy: '2026-10-03T16:00:00+05:30' };
let desk = false;
let nodes: Node[] = [];
function visit(value: unknown, path: string): void {
  if (Array.isArray(value)) { value.forEach((child, index) => visit(child, `${path}/${index}`)); return; }
  if (value === null || typeof value !== 'object' || !('type' in value) || !('props' in value)) return;
  const node = value as Node;
  if (typeof node.type === 'function') {
    const prior = seam.path; const cursor = seam.cursor;
    seam.path = path; seam.cursor = 0;
    const output: unknown = node.type(node.props);
    seam.path = prior; seam.cursor = cursor;
    visit(output, `${path}/render`); return;
  }
  nodes.push({ ...node, path });
  for (const key of ['children', 'title', 'meta', 'status', 'trailing', 'icon']) visit(node.props[key], `${path}/${key}`);
}
function draw() { nodes = []; visit({ type: ClassesPane, props: { desk } }, 'root'); seam.effects.splice(0).forEach(effect => effect()); }
async function settle() { for (let i = 0; i < 16; i++) { await Promise.resolve(); draw(); } }
function words(value: unknown): string {
  if (typeof value === 'string' || typeof value === 'number') return String(value);
  if (Array.isArray(value)) return value.map(words).join(' ');
  if (value !== null && typeof value === 'object' && 'props' in value) return words((value as Node).props.children);
  return '';
}
function visible(items: Node[] = nodes) { return items.map(node => ['children', 'title', 'meta', 'detail', 'message', 'value'].map(key => words(node.props[key])).join(' ')).join(' ').replace(/\s+/g, ' '); }
function control(label: RegExp) { return [...nodes].reverse().find(node => [words(node.props.children), words(node.props.title), words(node.props.accessibilityLabel)].some(value => label.test(value.trim())) && (typeof node.props.onPress === 'function' || typeof node.props.onRetry === 'function')); }
async function press(label: RegExp) { const node = control(label); expect(node, `rendered action ${label.source} exists`).toBeDefined(); if (!node) return; expect(node.props.disabled, `action ${label.source} enabled`).not.toBe(true); const callback = node.props.onPress ?? node.props.onRetry; if (typeof callback === 'function') await callback(); await settle(); }
function cleanup() { seam.stores.forEach(slots => slots.forEach(slot => slot.cleanup?.())); seam.stores.clear(); seam.effects = []; }
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(yes => { resolve = yes; }); return { promise, resolve }; }
function context(identity: unknown) {
  return { identity, ready: true, nouns: businessNouns('gym'), palette: {}, session: { user: { id: memberA.userId }, access_token: 'fixture-token' }, api: { post: vi.fn().mockResolvedValue({ ok: true, data: { bookingId: booked.myBookingId, status: 'cancelled_by_member' } }) }, supabase: {
    from: () => ({ select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: { timezone: 'Asia/Kolkata', branch_id: session.branchId }, error: null }) }) }) }),
    auth: { onAuthStateChange: () => ({ data: { subscription: { unsubscribe: vi.fn() } } }) },
  }, webOrigin: 'https://gymloop.test' };
}
beforeEach(() => {
  cleanup(); vi.clearAllMocks(); vi.useFakeTimers(); vi.setSystemTime(new Date('2026-10-03T10:00:00+05:30'));
  desk = false; seam.network = true; seam.networkListener = null; seam.context = context(memberA);
  seam.loadMember.mockReset().mockResolvedValue([session]); seam.loadTimetable.mockResolvedValue([]); seam.loadRoster.mockResolvedValue([]); seam.search.mockResolvedValue([]);
  seam.insideHelper = false; seam.finalWait = null;
  seam.probe.mockReset().mockImplementation(async () => seam.insideHelper && seam.finalWait ? seam.finalWait : { isConnected: true, isInternetReachable: true });

});
afterEach(() => { cleanup(); vi.useRealTimers(); });


const confirmation = /^Confirm(?: booking| cancellation)?$|^Book class$|^Cancel booking$/;
function post() { return (seam.context.api as { post: ReturnType<typeof vi.fn> }).post; }
async function tryConfirm() { const node = control(confirmation); if (node && node.props.disabled !== true && typeof node.props.onPress === 'function') { await node.props.onPress(); await settle(); } }
describe('CLS approved actual native booking confirmation', () => {
  it('refreshes current caller schedule before preparing and reopening and sends exact session only', async () => {
    draw(); await settle(); const initialReads = seam.loadMember.mock.calls.length;
    await press(/^Book$/);
    expect(seam.loadMember.mock.calls.length).toBe(initialReads + 1);
    expect(seam.loadMember.mock.calls.at(-1)?.[0]).toBe(seam.context.supabase);
    expect(post()).not.toHaveBeenCalled();
    expect(visible()).toMatch(/16:00|4:00\s*[pP][mM]/);
    const sheet = nodes.find(node => node.type === 'Sheet');
    expect(sheet?.props.onClose).toBeTypeOf('function');
    if (typeof sheet?.props.onClose === 'function') sheet.props.onClose();
    await settle(); await press(/^Book$/);
    expect(seam.loadMember.mock.calls.length).toBe(initialReads + 2);
    await press(confirmation);
    expect(post()).toHaveBeenCalledTimes(1);
    expect(post()).toHaveBeenCalledWith('/api/class-bookings', { sessionId: session.sessionId });
  });

  it('does not enable commitment while the preparation schedule is pending', async () => {
    draw(); await settle(); const waiting = deferred<MemberClassSession[] | null>();
    seam.loadMember.mockReturnValueOnce(waiting.promise);
    const book = control(/^Book$/); expect(book).toBeDefined();
    const pending = typeof book?.props.onPress === 'function' ? book.props.onPress() : undefined;
    await settle(); await tryConfirm(); expect(post()).not.toHaveBeenCalled();
    waiting.resolve([session]); await pending; await settle();
    await press(confirmation); expect(post()).toHaveBeenCalledTimes(1);
  });

  it.each([
    ['failed', null],
    ['missing exact row', []],
    ['wrong session', [{ ...session, sessionId: '74000000-0000-4000-8000-000000000099' }]],
    ['missing deadline', [{ ...session, cancelBy: null }]],
    ['full', [{ ...session, availability: 'full' as const, spotsLeft: 0 }]],
    ['closed', [{ ...session, availability: 'closed' as const }]],
    ['cancelled', [{ ...session, availability: 'cancelled' as const, sessionStatus: 'cancelled' as const }]],
  ])('does not commit %s refreshed preparation facts', async (_name, rows) => {
    draw(); await settle(); seam.loadMember.mockResolvedValue(rows);
    await press(/^Book$/); await tryConfirm(); expect(post()).not.toHaveBeenCalled();
  });

  it('shows refreshed authoritative cutoff in the returned branch timezone', async () => {
    draw(); await settle();
    seam.loadMember.mockResolvedValue([{ ...session, timezone: 'UTC', cancelBy: '2026-10-03T15:00:00+05:30' }]);
    await press(/^Book$/);
    expect(visible()).toMatch(/09:30|9:30\s*[aA][mM]/);
    expect(visible()).not.toMatch(/16:00|4:00\s*[pP][mM]/);
    await press(confirmation); expect(post()).toHaveBeenCalledTimes(1);
  });

  it('suppresses a pending preparation after caller revocation', async () => {
    draw(); await settle(); const waiting = deferred<MemberClassSession[] | null>(); seam.loadMember.mockReturnValueOnce(waiting.promise);
    const book = control(/^Book$/); expect(book).toBeDefined();
    const pending = typeof book?.props.onPress === 'function' ? book.props.onPress() : undefined;
    await settle(); seam.context = { ...seam.context, ready: false, session: null }; draw(); await settle();
    waiting.resolve([session]); await pending; await settle(); await tryConfirm();
    expect(post()).not.toHaveBeenCalled();
  });
  it.each([
    ['read failure', null],
    ['missing exact row', []],
    ['lost deadline', [{ ...session, cancelBy: null }]],
    ['capacity taken', [{ ...session, availability: 'full' as const, spotsLeft: 0 }]],
  ])('cannot reuse prepared facts when confirmation sees %s', async (_name, rows) => {
    draw(); await settle(); await press(/^Book$/);
    const previousReads = seam.loadMember.mock.calls.length;
    seam.loadMember.mockResolvedValue(rows); await press(confirmation);
    expect(seam.loadMember.mock.calls.length).toBeGreaterThan(previousReads);
    expect(post()).not.toHaveBeenCalled();
  });
  it('requires renewed explicit booking confirmation when the current cutoff changes', async () => {
    draw(); await settle(); await press(/^Book$/);
    seam.loadMember.mockResolvedValue([{ ...session, cancelBy: '2026-10-03T15:00:00+05:30' }]);
    await press(confirmation);
    expect(post()).not.toHaveBeenCalled();
    expect(visible()).toMatch(/15:00|3:00\s*[pP][mM]/);
    await press(confirmation); expect(post()).toHaveBeenCalledTimes(1);
  });
});

describe('CLS actual pane plus actual cancellation helper final-send cutoff', () => {
  it.each(['exact cutoff', 'one millisecond after', 'caller revoked'] as const)('resumes final asynchronous preflight at %s', async boundary => {
    seam.loadMember.mockResolvedValue([booked]); draw(); await settle(); await press(/^Cancel(?: booking)?$/);
    const waiting = deferred<{ isConnected: boolean; isInternetReachable: boolean }>();
    seam.finalWait = waiting.promise;
    const confirm = control(/^Confirm(?: cancellation)?$|^Cancel booking$/); expect(confirm).toBeDefined();
    const pending = typeof confirm?.props.onPress === 'function' ? confirm.props.onPress() : undefined;
    await settle();
    expect(seam.insideHelper, 'actual cancellation helper reached before its final preflight resolves').toBe(true);
    expect(post()).not.toHaveBeenCalled();
    vi.setSystemTime(new Date(boundary === 'one millisecond after' ? '2026-10-03T16:00:00.001+05:30' : booked.cancelBy!));
    if (boundary === 'caller revoked') { seam.context = { ...seam.context, ready: false, session: null }; draw(); await settle(); }
    waiting.resolve({ isConnected: true, isInternetReachable: true }); await pending; await settle();
    if (boundary === 'exact cutoff') {
      expect(post()).toHaveBeenCalledTimes(1);
      expect(post()).toHaveBeenCalledWith('/api/class-bookings/cancel', { bookingId: booked.myBookingId });
    } else {
      expect(post()).not.toHaveBeenCalled();
      expect(visible()).not.toMatch(/Booking cancelled|Successfully cancelled/);
    }
  });
});
