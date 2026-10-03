import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { businessNouns, type MemberClassSession, type ClassTimetableSession, type ClassRosterBooking } from '@gymloop/shared';
import { ClassesPane } from '../../components/classes-pane';

type Props = Record<string, unknown>;
type Node = { type: unknown; props: Props };
type Slot = { value?: unknown; deps?: readonly unknown[] | undefined; cleanup?: (() => void) | undefined };
const seam = vi.hoisted(() => ({
  stores: new Map<string, Slot[]>(), path: '', cursor: 0, effects: [] as Array<() => void>,
  loadMember: vi.fn(), loadTimetable: vi.fn(), loadRoster: vi.fn(), search: vi.fn(),
  book: vi.fn(), cancel: vi.fn(), deskBook: vi.fn(), deskCancel: vi.fn(), mark: vi.fn(),
  network: true, networkListener: null as null | ((state: { isConnected: boolean; isInternetReachable: boolean }) => void),
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
vi.mock('../../lib/classes', () => ({ loadMemberClasses: seam.loadMember, loadDeskTimetable: seam.loadTimetable, loadDeskRoster: seam.loadRoster, bookClass: seam.book, cancelClassBooking: seam.cancel, deskBookClass: seam.deskBook, deskCancelClassBooking: seam.deskCancel, markClassAttendance: seam.mark }));
vi.mock('../../lib/mobile-data', () => ({ loadDeskMembers: seam.search }));
vi.mock('expo-network', () => ({
  getNetworkStateAsync: async () => ({ isConnected: seam.network, isInternetReachable: seam.network }),
  addNetworkStateListener: (callback: typeof seam.networkListener) => { seam.networkListener = callback; return { remove: vi.fn() }; },
}));
vi.mock('expo-router', () => ({ router: { push: vi.fn(), replace: vi.fn() }, useRouter: () => ({ push: vi.fn(), replace: vi.fn() }) }));
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
const memberB = { ...memberA, userId: '74000000-0000-4000-8000-000000000014', memberId: '74000000-0000-4000-8000-000000000015' };
const session: MemberClassSession = {
  sessionId: '74000000-0000-4000-8000-000000000001', serviceId: '74000000-0000-4000-8000-000000000002', branchId: '74000000-0000-4000-8000-000000000003',
  serviceName: 'Evening mobility', serviceDescription: 'Move comfortably', branchName: 'East studio', timezone: 'Asia/Kolkata', sessionDate: '2026-10-03',
  startsAt: '2026-10-03T18:00:00+05:30', endsAt: '2026-10-03T19:00:00+05:30', trainerName: 'Coach Kavya', capacity: 13, bookedCount: 9, spotsLeft: 4,
  sessionStatus: 'scheduled', myBookingId: null, myBookingStatus: null, availability: 'open', canCancel: false, cancelBy: null,
};
const booked: MemberClassSession = { ...session, myBookingId: '74000000-0000-4000-8000-000000000016', myBookingStatus: 'booked', availability: 'booked', canCancel: true, cancelBy: '2026-10-03T16:00:00+05:30' };
const timetable: ClassTimetableSession = {
  sessionId: session.sessionId, serviceId: session.serviceId, serviceName: session.serviceName, serviceIsActive: true, branchId: session.branchId,
  sessionDate: session.sessionDate, startsAt: session.startsAt, endsAt: session.endsAt, timezone: session.timezone,
  trainerStaffId: '74000000-0000-4000-8000-000000000017', trainerName: session.trainerName, trainerIsActive: true,
  capacity: 13, bookedCount: 9, attendedCount: 0, noShowCount: 0, spotsLeft: 4, sessionStatus: 'scheduled', cancelReason: null, ruleId: null, isCustomised: false, onHoliday: false, trainerOverlaps: false,
};
const roster: ClassRosterBooking = { bookingId: booked.myBookingId!, memberId: memberA.memberId, memberName: 'Roster person', memberCode: 'GL-404', memberPhone: null, hasApp: false, status: 'booked', bookedAt: '2026-10-03T08:00:00+05:30', cancelledAt: null, cancelReason: null, markedAt: null, membershipLive: false, checkedInAt: '2026-10-03T11:00:00+05:30' };
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
  nodes.push(node);
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
function visible() { return nodes.map(node => ['children', 'title', 'meta', 'detail', 'message', 'value'].map(key => words(node.props[key])).join(' ')).join(' ').replace(/\s+/g, ' '); }
function control(label: RegExp) { return [...nodes].reverse().find(node => [words(node.props.children), words(node.props.title), words(node.props.accessibilityLabel)].some(value => label.test(value.trim())) && (typeof node.props.onPress === 'function' || typeof node.props.onRetry === 'function')); }
async function press(label: RegExp) { const node = control(label); expect(node, `rendered action ${label.source} exists`).toBeDefined(); if (!node) return; expect(node.props.disabled, `action ${label.source} enabled`).not.toBe(true); const callback = node.props.onPress ?? node.props.onRetry; if (typeof callback === 'function') await callback(); await settle(); }
function cleanup() { seam.stores.forEach(slots => slots.forEach(slot => slot.cleanup?.())); seam.stores.clear(); seam.effects = []; }
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(yes => { resolve = yes; }); return { promise, resolve }; }
function context(identity: unknown) {
  return { identity, ready: true, nouns: businessNouns('gym'), palette: {}, session: { user: { id: memberA.userId }, access_token: 'fixture-token' }, api: { post: vi.fn() }, supabase: {
    from: () => ({ select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: { timezone: 'Asia/Kolkata', branch_id: session.branchId }, error: null }) }) }) }),
    auth: { onAuthStateChange: () => ({ data: { subscription: { unsubscribe: vi.fn() } } }) },
  }, webOrigin: 'https://gymloop.test' };
}
beforeEach(() => {
  cleanup(); vi.clearAllMocks(); vi.useFakeTimers(); vi.setSystemTime(new Date('2026-10-03T10:00:00+05:30'));
  desk = false; seam.network = true; seam.networkListener = null; seam.context = context(memberA);
  seam.loadMember.mockResolvedValue([session]); seam.loadTimetable.mockResolvedValue([timetable]); seam.loadRoster.mockResolvedValue([roster]); seam.search.mockResolvedValue([]);
  seam.cancel.mockResolvedValue({ ok: true, data: { bookingId: booked.myBookingId, status: 'cancelled_by_member' } });
});
afterEach(() => { cleanup(); vi.useRealTimers(); });

describe('CLS rendered native contract', () => {
  it('revokes retained confirmation during an authentication transition before identity resolves', async () => {
    seam.loadMember.mockResolvedValue([booked]); draw(); await settle(); await press(/^Cancel(?: booking)?$/);
    const retained = control(/^Confirm(?: cancellation)?$|^Cancel booking$/)?.props.onPress;
    expect(retained, 'authenticated confirmation exists').toBeTypeOf('function');
    seam.context = { ...seam.context, ready: false, session: null }; draw(); await settle();
    if (typeof retained === 'function') await retained(); await settle();
    expect(seam.cancel, 'authentication transition revokes old command authority').not.toHaveBeenCalled();
  });
  it('revokes an existing confirmation callback on unmount', async () => {
    seam.loadMember.mockResolvedValue([booked]); draw(); await settle(); await press(/^Cancel(?: booking)?$/);
    const retained = control(/^Confirm(?: cancellation)?$|^Cancel booking$/)?.props.onPress;
    expect(retained, 'mounted confirmation callback exists').toBeTypeOf('function');
    cleanup();
    if (typeof retained === 'function') await retained();
    expect(seam.cancel, 'unmounted confirmation cannot mutate').not.toHaveBeenCalled();
  });
  it('renders the exact refusal after an existing booking cancellation without claiming success', async () => {
    seam.loadMember.mockResolvedValue([booked]);
    seam.cancel.mockResolvedValue({ ok: false, error: { code: 'cancel_window_closed', message: 'Untrusted diagnostic sentinel' } });
    draw(); await settle(); await press(/^Cancel(?: booking)?$/); await press(/^Confirm(?: cancellation)?$|^Cancel booking$/);
    expect(seam.cancel, 'explicit confirmation sent one command').toHaveBeenCalledTimes(1);
    expect(visible(), 'frozen refusal and next action').toContain("It's too close to the start time to cancel online. Speak to the front desk if you can't make it.");
    expect(visible(), 'raw diagnostics never shown').not.toContain('Untrusted diagnostic sentinel');
    expect(visible(), 'refusal never claims cancellation').not.toMatch(/Booking cancelled|Successfully cancelled/);
  });
  it('searches the caller-bound member seam and books the chosen result within three taps', async () => {
    desk = true; seam.context = context({ kind: 'staff', userId: memberA.userId, tenantId: memberA.tenantId, staffId: timetable.trainerStaffId, role: 'front_desk' });
    seam.search.mockResolvedValue([{ id: memberB.memberId, fullName: 'Search matching member', phone: '9876500011', status: 'active', memberCode: 'GL-405' }]);
    seam.deskBook.mockResolvedValue({ ok: true, data: { bookingId: roster.bookingId, status: 'booked', spotsLeft: 3 } });
    draw(); await settle(); await press(/Evening mobility/); await press(/^Add member$/);
    const search = nodes.find(node => node.type === 'SearchField');
    expect(search, 'real search control is present').toBeDefined();
    if (typeof search?.props.onChangeText === 'function') search.props.onChangeText('matching');
    await vi.advanceTimersByTimeAsync(500); await settle();
    expect(seam.search, 'search forwarded to supplied caller client').toHaveBeenCalledWith(seam.context.supabase, 'matching');
    await press(/Search matching member/);
    if (!seam.deskBook.mock.calls.length) await press(/^Confirm(?: booking)?$|^Book$/);
    expect(seam.deskBook, 'chosen member rather than caller ID').toHaveBeenCalledWith(seam.context.api, session.sessionId, memberB.memberId);
    expect(seam.mark, 'adding a booking never marks attendance').not.toHaveBeenCalled();
  });
  it('loads local today, shows session facts and ignores surplus member fields', async () => {
    seam.loadMember.mockResolvedValue([Object.assign({}, session, { memberName: 'Privacy sentinel', memberPhone: 'Phone sentinel' }), { ...session, sessionDate: '2026-10-04', serviceName: 'Tomorrow sentinel' }]);
    draw(); await settle();
    expect(seam.loadMember, 'caller read was requested').toHaveBeenCalled();
    expect(seam.loadMember.mock.calls[0]?.[1], 'window begins on gym local today').toMatchObject({ from: '2026-10-03' });
    for (const fact of ['Evening mobility', 'Coach Kavya', '4 spots left']) expect(visible(), `visible fact ${fact}`).toContain(fact);
    expect(visible(), 'tomorrow is not the initial day').not.toContain('Tomorrow sentinel');
    expect(visible(), 'counts-only output').not.toMatch(/Privacy sentinel|Phone sentinel/);
    expect(visible(), 'local class time').toMatch(/18:00|6:00\s*[pP][mM]/);
  });
  it('offers loading, exact empty copy, and retry after a failed schedule', async () => {
    const waiting = deferred<MemberClassSession[] | null>(); seam.loadMember.mockReturnValueOnce(waiting.promise);
    draw(); await settle(); expect(nodes.some(node => node.type === 'LoadingState'), 'loading state rendered').toBe(true);
    waiting.resolve([]); await settle(); expect(visible(), 'empty successful schedule').toContain('No classes are scheduled yet. Ask the front desk when the timetable goes up.');
    cleanup(); seam.loadMember.mockResolvedValue(null); draw(); await settle();
    expect(nodes.some(node => node.type === 'ErrorRetry'), 'failed read has retry').toBe(true);
  });
  it('does not authorize booking when the read lacks a cancellation deadline', async () => {
    draw(); await settle();
    const bookAction = control(/^Book$/);
    if (bookAction && bookAction.props.disabled !== true) { const callback = bookAction.props.onPress; if (typeof callback === 'function') await callback(); await settle(); }
    const confirm = control(/^Confirm(?: booking)?$/);
    expect(confirm === undefined || confirm.props.disabled === true, 'missing deadline fail closed before commitment').toBe(true);
    expect(seam.book, 'no command without authoritative deadline').not.toHaveBeenCalled();
    expect(visible(), 'no invented default deadline').not.toMatch(/16:00|4:00\s*[pP][mM]/);
  });
  it('refreshes an existing cancellation and respects the newly closed window', async () => {
    seam.loadMember.mockResolvedValueOnce([booked]).mockResolvedValue([{ ...booked, canCancel: false, cancelBy: '2026-10-03T09:00:00+05:30' }]);
    draw(); await settle(); await press(/^Cancel(?: booking)?$/);
    expect(seam.loadMember.mock.calls.length, 'cancel preparation refreshes read facts').toBeGreaterThan(1);
    expect(visible(), 'closed window explains next action').toContain("It's too close to the start time to cancel online. Speak to the front desk if you can't make it.");
    expect(seam.cancel, 'closed window never mutates').not.toHaveBeenCalled();
  });
  it('shows local authoritative deadline and prevents duplicate pending cancellation', async () => {
    seam.loadMember.mockResolvedValue([booked]); const pending = deferred<unknown>(); seam.cancel.mockReturnValue(pending.promise);
    draw(); await settle(); await press(/^Cancel(?: booking)?$/);
    expect(visible(), 'confirmation names class').toContain('Evening mobility');
    expect(visible(), 'confirmation names supplied local deadline').toMatch(/16:00|4:00\s*[pP][mM]/);
    const confirm = control(/^Confirm(?: cancellation)?$|^Cancel booking$/);
    expect(confirm, 'confirmation action rendered').toBeDefined();
    const retained = confirm?.props.onPress;
    if (typeof retained === 'function') { void retained(); await settle(); void retained(); await settle(); }
    expect(seam.cancel, 'one in-flight cancellation only').toHaveBeenCalledTimes(1);
    pending.resolve({ ok: true, data: { bookingId: booked.myBookingId, status: 'cancelled_by_member' } }); await settle();
  });
  it('keeps loaded facts offline and refuses cancellation without queueing', async () => {
    seam.loadMember.mockResolvedValue([booked]); draw(); await settle();
    seam.network = false; seam.networkListener?.({ isConnected: false, isInternetReachable: false }); await settle();
    expect(visible(), 'loaded schedule remains available').toContain('Evening mobility');
    expect(visible(), 'offline next action').toContain("You're offline. Connect and try again — bookings can't be saved offline.");
    const cancel = control(/^Cancel(?: booking)?$/);
    expect(cancel === undefined || cancel.props.disabled === true, 'offline mutation unavailable').toBe(true);
    expect(seam.cancel, 'offline command not queued').not.toHaveBeenCalled();
  });
  it('revokes retained callbacks after caller A to B to A instead of restoring old authority', async () => {
    seam.loadMember.mockResolvedValue([booked]); draw(); await settle(); await press(/^Cancel(?: booking)?$/);
    const retained = control(/^Confirm(?: cancellation)?$|^Cancel booking$/)?.props.onPress;
    expect(retained, 'a cancellation callback can be retained').toBeTypeOf('function');
    seam.context = context(memberB); draw(); await settle(); seam.context = context(memberA); draw(); await settle();
    if (typeof retained === 'function') await retained(); await settle();
    expect(seam.cancel, 'expired A callback cannot mutate after ABA').not.toHaveBeenCalled();
  });
  it('does not publish late results after caller replacement or unmount', async () => {
    const oldRead = deferred<MemberClassSession[] | null>(); seam.loadMember.mockReturnValueOnce(oldRead.promise).mockResolvedValue([]);
    draw(); await settle(); seam.context = context(memberB); draw(); await settle();
    oldRead.resolve([{ ...session, serviceName: 'Old caller sentinel' }]); await settle();
    expect(visible(), 'late former caller results excluded').not.toContain('Old caller sentinel');
    const late = deferred<MemberClassSession[] | null>(); cleanup(); seam.loadMember.mockReturnValueOnce(late.promise); draw(); await settle(); cleanup();
    late.resolve([{ ...session, serviceName: 'Unmount sentinel' }]); await Promise.resolve();
    expect(seam.cancel, 'unmount does not trigger command').not.toHaveBeenCalled();
  });
  it('renders roster flags and provides a one-tap explicit attendance command at the desk', async () => {
    desk = true; seam.context = context({ kind: 'staff', userId: memberA.userId, tenantId: memberA.tenantId, staffId: timetable.trainerStaffId, role: 'front_desk' });
    draw(); await settle(); await press(/Evening mobility/);
    for (const fact of ['Roster person', 'GL-404', 'Checked in', 'No live membership', 'No app']) expect(visible(), `desk roster fact ${fact}`).toContain(fact);
    seam.mark.mockResolvedValue({ ok: true, data: { bookingId: roster.bookingId, status: 'attended' } });
    await press(/Mark attended/);
    expect(seam.mark, 'explicit attendance is one tap').toHaveBeenCalledWith(seam.context.api, roster.bookingId, 'attended');
    expect(seam.deskBook, 'booking is not attendance').not.toHaveBeenCalled();
  });
  it('makes a cancelled desk roster read only', async () => {
    desk = true; seam.context = context({ kind: 'staff', userId: memberA.userId, tenantId: memberA.tenantId, staffId: timetable.trainerStaffId, role: 'front_desk' });
    seam.loadTimetable.mockResolvedValue([{ ...timetable, sessionStatus: 'cancelled', cancelReason: 'Trainer unavailable' }]);
    draw(); await settle(); await press(/Evening mobility/);
    expect(visible(), 'cancelled state explicit').toContain('Cancelled');
    expect(control(/Mark attended|Mark no-show|Add member|Cancel booking/), 'cancelled roster has no mutation controls').toBeUndefined();
  });
  it('does not offer desk booking or attendance authority to support preview', async () => {
    desk = true; seam.context = context({ kind: 'impersonation', userId: memberA.userId, tenantId: memberA.tenantId, impersonationSessionId: '74000000-0000-4000-8000-000000000018' });
    draw(); await settle();
    const open = control(/Evening mobility/); if (open && typeof open.props.onPress === 'function') { await open.props.onPress(); await settle(); }
    expect(control(/Mark attended|Mark no-show|Add member|Cancel booking/), 'preview cannot mutate').toBeUndefined();
  });
});
