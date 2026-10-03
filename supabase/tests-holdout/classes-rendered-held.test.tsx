import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import type { MemberClassSession, ClassTimetableSession, ClassRosterBooking } from '@gymloop/shared';
import { businessNouns, UI_TOKENS } from '@gymloop/shared';

// Independent declaration-only author. These hosts preserve callbacks and children;
// they make no geometry, dot, axe, screen-reader or real-device claim.
type Props = Record<string, unknown>;
type Node = { type: unknown; props: Props };
type Cell = { value?: unknown; deps?: unknown[] | undefined; cleanup?: (() => void) | undefined };
const seam = vi.hoisted(() => ({
  active: null as null | { cells: Cell[]; cursor: number; effects: (() => void)[] },
  mobile: {} as Props, online: true, listeners: new Set<(state: Props) => void>(),
  refresh: vi.fn(), loadMember: vi.fn(), loadDesk: vi.fn(), loadRoster: vi.fn(),
  book: vi.fn(), cancel: vi.fn(), deskBook: vi.fn(), deskCancel: vi.fn(), mark: vi.fn(), search: vi.fn(),
}));
vi.mock('react', async importOriginal => {
  const actual = await importOriginal<Props>();
  function slot() {
    const frame = seam.active;
    if (!frame) throw new Error('Held renderer has no hook frame');
    const index = frame.cursor++;
    return { frame, cell: frame.cells[index] ?? (frame.cells[index] = {}) };
  }
  function state(initial: unknown) {
    const { cell } = slot();
    if (!Object.hasOwn(cell, 'value')) cell.value = typeof initial === 'function' ? initial() : initial;
    return [cell.value, (next: unknown) => { cell.value = typeof next === 'function' ? next(cell.value) : next; }];
  }
  function memo(factory: () => unknown, deps?: unknown[]) {
    const { cell } = slot();
    if (!deps || !cell.deps || deps.some((value, index) => !Object.is(value, cell.deps?.[index]))) {
      cell.value = factory(); cell.deps = deps;
    }
    return cell.value;
  }
  function effect(callback: () => unknown, deps?: unknown[]) {
    const { frame, cell } = slot();
    if (!deps || !cell.deps || deps.some((value, index) => !Object.is(value, cell.deps?.[index]))) {
      cell.deps = deps;
      frame.effects.push(() => { cell.cleanup?.(); const result = callback(); cell.cleanup = typeof result === 'function' ? result as () => void : undefined; });
    }
  }
  return { ...actual, useState: state, useRef: (value: unknown) => memo(() => ({ current: value }), []),
    useMemo: memo, useCallback: (fn: unknown, deps: unknown[]) => memo(() => fn, deps),
    useEffect: effect, useLayoutEffect: effect,
    useId: () => memo(() => 'held-id', []),
  };
});
vi.mock('next/navigation', () => ({ useRouter: () => ({ refresh: seam.refresh }) }));
vi.mock('../../apps/web/app/preview-context', () => ({ usePreviewReadOnly: () => false }));
vi.mock('../../apps/mobile/lib/mobile-context', () => ({ useMobile: () => seam.mobile }));
vi.mock('../../apps/mobile/lib/use-business-nouns', () => ({ useBusinessNouns: () => seam.mobile.nouns }));
vi.mock('../../apps/mobile/lib/classes', () => ({
  loadMemberClasses: seam.loadMember, loadDeskTimetable: seam.loadDesk, loadDeskRoster: seam.loadRoster,
  bookClass: seam.book, cancelClassBooking: seam.cancel, deskBookClass: seam.deskBook,
  deskCancelClassBooking: seam.deskCancel, markClassAttendance: seam.mark,
}));
vi.mock('../../apps/mobile/lib/mobile-data', () => ({ loadDeskMembers: seam.search }));
vi.mock('expo-network', () => ({ getNetworkStateAsync: async () => ({ isConnected: seam.online, isInternetReachable: seam.online }),
  addNetworkStateListener: (fn: (state: Props) => void) => { seam.listeners.add(fn); return { remove: () => seam.listeners.delete(fn) }; },
}));
vi.mock('expo-router', () => ({ useRouter: () => ({ push: vi.fn(), replace: vi.fn() }), router: { push: vi.fn() } }));
vi.mock('react-native', () => ({ View: 'View', Text: 'Text', Pressable: 'Pressable', TextInput: 'TextInput',
  ScrollView: 'ScrollView', ActivityIndicator: 'ActivityIndicator', Modal: 'Modal',
  StyleSheet: { create: (styles: unknown) => styles, hairlineWidth: 1 }, Platform: { OS: 'android' },
  Linking: { openURL: vi.fn() }, useWindowDimensions: () => ({ width: 390, height: 844 }),
}));
vi.mock('lucide-react-native', () => new Proxy({}, { get: (_, key) => typeof key === 'string' ? key : undefined }));
vi.mock('../../apps/mobile/components/ui', () => {
  const host = (name: string) => (props: Props): Node | null => {
    if (name === 'Sheet' && !props.visible) return null;
    const children = name === 'Row' ? [props.title, props.meta, props.status, props.value, props.trailing]
      : name === 'SheetHeader' ? [props.eyebrow, props.title, props.detail, { type: 'button', props: { children: props.control, onPress: props.onControl, disabled: props.controlDisabled } }]
      : name === 'ErrorRetry' ? [props.message, { type: 'button', props: { children: 'Try again', onPress: props.onRetry } }]
      : [props.title, props.children];
    return { type: name, props: { ...props, children } };
  };
  return Object.fromEntries(['ActionButton', 'Body', 'EmptyState', 'ErrorRetry', 'LoadingState', 'Row', 'RowAction', 'SearchField', 'Sheet', 'SheetHeader', 'StateMessage', 'Status', 'LedgerSection', 'Display', 'Rule'].map(name => [name, host(name)]));
});

import { MemberClassesView } from '../../apps/web/app/member/classes/member-classes-view';
import { ClassesPane } from '../../apps/mobile/components/classes-pane';

function mount(component: (props: never) => unknown, props: Props = {}) {
  const frames = new Map<string, { cells: Cell[]; cursor: number; effects: (() => void)[] }>();
  let nodes: Node[] = [];
  let words: string[] = [];
  function visit(value: unknown, path: string): void {
    if (value == null || typeof value === 'boolean') return;
    if (Array.isArray(value)) { value.forEach((child, index) => visit(child, `${path}.${index}`)); return; }
    if (typeof value !== 'object') { words.push(String(value)); return; }
    const node = value as Node;
    if (typeof node.type === 'function') {
      const frame = frames.get(path) ?? { cells: [], cursor: 0, effects: [] };
      frames.set(path, frame); frame.cursor = 0; seam.active = frame;
      const child = node.type(node.props); seam.active = null; visit(child, `${path}.render`); return;
    }
    if (node.props) { nodes.push(node); visit(node.props.children, `${path}.children`); }
  }
  function render() {
    nodes = []; words = []; visit({ type: component, props }, 'root');
    for (const frame of frames.values()) for (const effect of frame.effects.splice(0)) effect();
  }
  async function settle() { for (let turn = 0; turn < 12; turn++) { await Promise.resolve(); render(); } }
  function textOf(value: unknown): string {
    if (value == null || typeof value === 'boolean') return '';
    if (Array.isArray(value)) return value.map(textOf).join(' ');
    if (typeof value === 'object') return textOf((value as Node).props?.children);
    return String(value);
  }
  function controls(pattern: RegExp) { return nodes.filter(node => typeof (node.props.onClick ?? node.props.onPress) === 'function' && pattern.test(textOf(node.props.children).trim())); }
  async function press(pattern: RegExp) {
    const button = controls(pattern).find(node => !node.props.disabled && !(node.props.accessibilityState as Props | undefined)?.disabled);
    expect(button, `Enabled held control ${pattern}`).toBeDefined();
    const callback = button?.props.onClick ?? button?.props.onPress;
    if (typeof callback === 'function') callback();
    await settle();
  }
  render();
  return { settle, press, controls, nodes: () => nodes, text: () => words.join(' '), rerender: (next: Props = props) => { props = next; render(); },
    unmount: () => { for (const frame of frames.values()) for (const cell of frame.cells) cell.cleanup?.(); frames.clear(); },
  };
}
const nouns = businessNouns('gym');
const id = (tail: string) => `74900000-0000-4000-8000-${tail.padStart(12, '0')}`;
const identityA = { kind: 'member', userId: id('1'), tenantId: id('2'), memberId: id('3') };
const identityB = { kind: 'member', userId: id('4'), tenantId: id('5'), memberId: id('6') };
function session(overrides: Partial<MemberClassSession> = {}): MemberClassSession {
  return { sessionId: id('10'), serviceId: id('11'), serviceName: 'Held yoga', serviceDescription: 'Breathing and balance',
    branchId: id('12'), branchName: 'East studio', timezone: 'Asia/Kolkata', sessionDate: '2026-10-03',
    startsAt: '2026-10-03T12:30:00Z', endsAt: '2026-10-03T13:30:00Z', trainerName: 'Teacher Mira', capacity: 17,
    bookedCount: 13, spotsLeft: 4, sessionStatus: 'scheduled', myBookingId: null, myBookingStatus: null,
    availability: 'open', canCancel: false, cancelBy: null, ...overrides };
}
function timetable(overrides: Partial<ClassTimetableSession> = {}): ClassTimetableSession {
  const row = session();
  return { sessionId: row.sessionId, serviceId: row.serviceId, serviceName: row.serviceName,
    serviceIsActive: true, branchId: row.branchId, sessionDate: row.sessionDate, startsAt: row.startsAt,
    endsAt: row.endsAt, timezone: row.timezone, trainerStaffId: id('7'), trainerName: row.trainerName,
    trainerIsActive: true, capacity: row.capacity, bookedCount: row.bookedCount, attendedCount: 0, noShowCount: 0,
    spotsLeft: row.spotsLeft, sessionStatus: 'scheduled', cancelReason: null, ruleId: null,
    isCustomised: false, onHoliday: false, trainerOverlaps: false, ...overrides };
}
function roster(overrides: Partial<ClassRosterBooking> = {}): ClassRosterBooking {
  return { bookingId: id('20'), memberId: id('21'), memberName: 'Held member Hazel', memberCode: 'G0749',
    memberPhone: '9876500749', hasApp: false, status: 'booked', bookedAt: '2026-10-02T06:00:00Z',
    cancelledAt: null, cancelReason: null, markedAt: null, membershipLive: false, checkedInAt: '2026-10-03T12:00:00Z', ...overrides };
}
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(done => { resolve = done; }); return { promise, resolve }; }
const browser = new EventTarget();
beforeEach(() => {
  vi.useFakeTimers(); vi.setSystemTime(new Date('2026-10-03T07:00:00Z')); vi.clearAllMocks();
  seam.online = true; seam.listeners.clear();
  const query = { select: vi.fn().mockReturnThis(), eq: vi.fn().mockReturnThis(), maybeSingle: vi.fn(async () => ({ data: { timezone: 'Asia/Kolkata', branch_id: id('12') }, error: null })) };
  seam.mobile = { identity: identityA, ready: true, supabase: { from: vi.fn(() => query) }, api: { post: vi.fn() },
    palette: UI_TOKENS.colors.light, nouns, businessType: 'gym', webOrigin: 'https://gymloop.test' };
  seam.loadMember.mockResolvedValue([session()]); seam.loadDesk.mockResolvedValue([timetable()]); seam.loadRoster.mockResolvedValue([roster()]);
  seam.search.mockResolvedValue([]);
  seam.book.mockResolvedValue({ ok: true, data: { bookingId: id('20'), status: 'booked', spotsLeft: 3 } });
  seam.cancel.mockResolvedValue({ ok: true, data: { bookingId: id('20'), status: 'cancelled_by_member' } });
  seam.mark.mockResolvedValue({ ok: true, data: { bookingId: id('20'), status: 'attended' } });
  vi.stubGlobal('window', browser); vi.stubGlobal('navigator', { onLine: true });
  vi.stubGlobal('fetch', vi.fn(async () => ({ ok: true, json: async () => ({ ok: true, data: { bookingId: id('20'), status: 'cancelled_by_member' } }) })));
});
afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); });

describe('CLS independent held web rendered member boundary', () => {
  it('opens today and renders supplied counts, teacher, branch and local time without member roster', async () => {
    const poisoned = { ...session(), memberName: 'DO NOT DISPLAY OTHER MEMBER', memberPhone: 'DO NOT DISPLAY PHONE', memberId: id('99') };
    const view = mount(MemberClassesView, { sessions: [poisoned, session({ sessionId: id('30'), serviceName: 'Tomorrow only', sessionDate: '2026-10-04' })], today: '2026-10-03', nouns });
    await view.settle();
    for (const fact of ['Held yoga', 'Teacher Mira', 'East studio', '4 spots left']) expect(view.text()).toContain(fact);
    expect(view.text()).toMatch(/6[:.]00|18:00/); expect(view.text()).not.toContain('Tomorrow only');
    for (const secret of ['DO NOT DISPLAY', id('99')]) expect(view.text()).not.toContain(secret);
    view.unmount();
  });
  it.each([['full', 'Full'], ['cancelled', 'Cancelled'], ['closed', 'Closed'], ['membership_not_live', 'Membership needed']] as const)('shows %s as a word and no enabled booking', async (availability, word) => {
    const view = mount(MemberClassesView, { sessions: [session({ availability, spotsLeft: availability === 'full' ? 0 : 4 })], today: '2026-10-03', nouns });
    await view.settle(); expect(view.text()).toContain(word);
    expect(view.controls(/^Book$/).filter(node => !node.props.disabled)).toHaveLength(0); view.unmount();
  });
  it('does not invent a prebooking cutoff from a default policy', async () => {
    const view = mount(MemberClassesView, { sessions: [session()], today: '2026-10-03', nouns });
    await view.settle();
    const book = view.controls(/^Book$/).find(node => !node.props.disabled);
    if (book) await view.press(/^Book$/);
    expect(view.controls(/^Confirm(?: booking)?$/i).filter(node => !node.props.disabled)).toHaveLength(0);
    expect(fetch).not.toHaveBeenCalled(); view.unmount();
  });
  it('confirms an existing cancellation with the authoritative absolute local deadline then refreshes', async () => {
    const row = session({ availability: 'booked', myBookingId: id('20'), myBookingStatus: 'booked', canCancel: true, cancelBy: '2026-10-03T10:30:00Z' });
    const view = mount(MemberClassesView, { sessions: [row], today: '2026-10-03', nouns });
    await view.settle(); await view.press(/^Cancel(?: booking)?$/i); expect(view.text()).toMatch(/4[:.]00|16:00/);
    await view.press(/^Confirm(?: cancellation)?$/i);
    expect(fetch).toHaveBeenCalledWith('/api/class-bookings/cancel', expect.objectContaining({ method: 'POST', body: JSON.stringify({ bookingId: id('20') }) }));
    expect(seam.refresh).toHaveBeenCalled(); view.unmount();
  });
  it('states the passed cancellation window instead of an enabled Cancel', async () => {
    const view = mount(MemberClassesView, { sessions: [session({ availability: 'booked', myBookingId: id('20'), myBookingStatus: 'booked', canCancel: false, cancelBy: '2026-10-03T06:00:00Z' })], today: '2026-10-03', nouns });
    await view.settle(); expect(view.text()).toMatch(/too close|deadline.*passed|cancel.*closed|front desk/i);
    expect(view.controls(/^Cancel$/).filter(node => !node.props.disabled)).toHaveLength(0); view.unmount();
  });
  it.each([['attended', 'Attended'], ['no_show', 'Missed'], ['booked', 'Ended']] as const)('labels past own %s without fabricating attendance', async (myBookingStatus, expected) => {
    const view = mount(MemberClassesView, { sessions: [session({ startsAt: '2026-10-03T04:00:00Z', endsAt: '2026-10-03T05:00:00Z', availability: 'closed', myBookingId: id('20'), myBookingStatus })], today: '2026-10-03', nouns });
    await view.settle(); expect(view.text()).toContain(expected); view.unmount();
  });
  it('distinguishes successful empty horizon from failure with a real retry', async () => {
    const empty = mount(MemberClassesView, { sessions: [], today: '2026-10-03', nouns });
    await empty.settle(); expect(empty.text()).toContain('Ask the front desk'); empty.unmount();
    const failed = mount(MemberClassesView, { sessions: null, today: '2026-10-03', nouns });
    await failed.settle(); expect(failed.text()).not.toContain('No classes are scheduled yet'); await failed.press(/try again|retry/i); expect(seam.refresh).toHaveBeenCalled(); failed.unmount();
  });
  it('keeps existing cancellation pending and prevents a second submitted command', async () => {
    const request = deferred<{ ok: boolean; json: () => Promise<unknown> }>(); vi.mocked(fetch).mockReturnValue(request.promise as Promise<Response>);
    const view = mount(MemberClassesView, { sessions: [session({ availability: 'booked', myBookingId: id('20'), myBookingStatus: 'booked', canCancel: true, cancelBy: '2026-10-03T10:30:00Z' })], today: '2026-10-03', nouns });
    await view.settle(); await view.press(/^Cancel(?: booking)?$/i); await view.press(/^Confirm(?: cancellation)?$/i);
    expect(fetch).toHaveBeenCalledTimes(1); expect(seam.refresh).not.toHaveBeenCalled();
    expect(view.controls(/^Confirm(?: cancellation)?$/i).filter(node => !node.props.disabled)).toHaveLength(0);
    request.resolve({ ok: true, json: async () => ({ ok: true, data: { bookingId: id('20'), status: 'cancelled_by_member' } }) }); await view.settle(); view.unmount();
  });
});

describe('CLS independent held actual native rendered boundaries', () => {
  it('uses caller member schedule and counts only; no roster or staff dataset', async () => {
    const view = mount(ClassesPane); await view.settle();
    expect(seam.loadMember).toHaveBeenCalledWith(seam.mobile.supabase, expect.objectContaining({ from: '2026-10-03' }));
    for (const fact of ['Held yoga', 'Teacher Mira', '4 spots left']) expect(view.text()).toContain(fact);
    expect(seam.loadDesk).not.toHaveBeenCalled(); expect(seam.loadRoster).not.toHaveBeenCalled(); expect(view.text()).not.toContain('Held member Hazel'); view.unmount();
  });
  it.each([{ kind: 'unlinked' }, { kind: 'platform', userId: id('1'), role: 'platform_support' }, { kind: 'impersonation', userId: id('1'), tenantId: id('2'), impersonationSessionId: id('8') }])('does not fetch or mutate member classes for %j', async identity => {
    seam.mobile.identity = identity; const view = mount(ClassesPane); await view.settle();
    expect(seam.loadMember).not.toHaveBeenCalled(); expect(seam.book).not.toHaveBeenCalled(); expect(seam.cancel).not.toHaveBeenCalled(); view.unmount();
  });
  it('distinguishes no timetable from failed member read with functional retry', async () => {
    seam.loadMember.mockResolvedValue([]); const empty = mount(ClassesPane); await empty.settle(); expect(empty.text()).toContain('Ask the front desk'); empty.unmount();
    seam.loadMember.mockResolvedValue(null); const fail = mount(ClassesPane); await fail.settle(); expect(fail.text()).not.toContain('No classes are scheduled yet');
    seam.loadMember.mockResolvedValue([session()]); await fail.press(/try again/i); expect(fail.text()).toContain('Held yoga'); fail.unmount();
  });
  it('fails closed without an authoritative new booking deadline', async () => {
    const view = mount(ClassesPane); await view.settle();
    if (view.controls(/^Book$/).some(node => !node.props.disabled)) await view.press(/^Book$/);
    expect(view.controls(/^Confirm(?: booking)?$/i).filter(node => !node.props.disabled)).toHaveLength(0); expect(seam.book).not.toHaveBeenCalled(); view.unmount();
  });
  it('retains the loaded schedule offline with disabled mutations and pinned copy', async () => {
    const view = mount(ClassesPane); await view.settle(); seam.online = false;
    for (const listener of seam.listeners) listener({ isConnected: false, isInternetReachable: false }); await view.settle();
    expect(view.text()).toContain('Held yoga'); expect(view.text()).toContain("You're offline. Connect and try again — bookings can't be saved offline.");
    expect(view.controls(/^Book$|^Cancel$/).filter(node => !node.props.disabled)).toHaveLength(0); expect(seam.book).not.toHaveBeenCalled(); view.unmount();
  });
  it('opens a desk roster and renders actual flags; does not create check-in by reading', async () => {
    seam.mobile.identity = { kind: 'staff', userId: id('1'), tenantId: id('2'), staffId: id('7'), role: 'front_desk' };
    const view = mount(ClassesPane, { desk: true }); await view.settle(); await view.press(/Held yoga/);
    expect(seam.loadRoster).toHaveBeenCalledWith(seam.mobile.supabase, id('10'));
    for (const fact of ['Held member Hazel', 'G0749', 'No app']) expect(view.text()).toContain(fact);
    expect(view.text()).toMatch(/Checked in|Check-in/i); expect(view.text()).toMatch(/No live membership|Membership needed/i);
    expect(seam.mark).not.toHaveBeenCalled(); expect(seam.loadMember).not.toHaveBeenCalled(); view.unmount();
  });
  it('marks one roster booking attended with one action and the exact caller command', async () => {
    seam.mobile.identity = { kind: 'staff', userId: id('1'), tenantId: id('2'), staffId: id('7'), role: 'front_desk' };
    seam.loadDesk.mockResolvedValue([timetable({ startsAt: '2026-10-03T07:30:00Z', endsAt: '2026-10-03T08:30:00Z' })]);
    const view = mount(ClassesPane, { desk: true }); await view.settle(); await view.press(/Held yoga/); await view.press(/^(?:Mark attended|Attended)$/i);
    expect(seam.mark).toHaveBeenCalledWith(seam.mobile.api, id('20'), 'attended'); expect(seam.book).not.toHaveBeenCalled(); view.unmount();
  });
  it('cancelled desk session keeps roster readable and mutation controls absent', async () => {
    seam.mobile.identity = { kind: 'staff', userId: id('1'), tenantId: id('2'), staffId: id('7'), role: 'front_desk' }; seam.loadDesk.mockResolvedValue([timetable({ sessionStatus: 'cancelled' })]);
    const view = mount(ClassesPane, { desk: true }); await view.settle(); await view.press(/Held yoga/);
    expect(view.text()).toContain('Held member Hazel'); expect(view.controls(/Mark attended|Mark no.show|Undo|Cancel booking|Add member/i)).toHaveLength(0); view.unmount();
  });
  it('trainer cannot add/cancel and cannot mark another trainer session', async () => {
    seam.mobile.identity = { kind: 'staff', userId: id('1'), tenantId: id('2'), staffId: id('8'), role: 'trainer' };
    const view = mount(ClassesPane, { desk: true }); await view.settle(); await view.press(/Held yoga/);
    expect(view.controls(/Mark attended|Mark no.show|Undo|Cancel booking|Add member/i)).toHaveLength(0); view.unmount();
  });
  it('suppresses delayed schedule data after A to B to A caller turnover permanently', async () => {
    const old = deferred<MemberClassSession[] | null>(); seam.loadMember.mockReturnValueOnce(old.promise);
    const view = mount(ClassesPane); await view.settle();
    seam.mobile = { ...seam.mobile, identity: identityB, supabase: { ...seam.mobile.supabase as Props } }; view.rerender(); await view.settle();
    seam.mobile = { ...seam.mobile, identity: identityA, supabase: { ...seam.mobile.supabase as Props } }; view.rerender(); await view.settle();
    old.resolve([session({ serviceName: 'Obsolete A lifetime' })]); await view.settle(); expect(view.text()).not.toContain('Obsolete A lifetime'); view.unmount();
  });
  it('late unmounted read never starts commands or second caller reads', async () => {
    const old = deferred<MemberClassSession[] | null>(); seam.loadMember.mockReturnValueOnce(old.promise);
    const view = mount(ClassesPane); await view.settle(); view.unmount(); const calls = seam.loadMember.mock.calls.length;
    old.resolve([session()]); await Promise.resolve(); await Promise.resolve(); expect(seam.loadMember).toHaveBeenCalledTimes(calls); expect(seam.book).not.toHaveBeenCalled(); expect(seam.cancel).not.toHaveBeenCalled();
  });
  it('existing member cancellation states the local deadline and sends only its booking id', async () => {
    seam.loadMember.mockResolvedValue([session({ availability: 'booked', myBookingId: id('20'), myBookingStatus: 'booked', canCancel: true, cancelBy: '2026-10-03T10:30:00Z' })]);
    const view = mount(ClassesPane); await view.settle(); await view.press(/^Cancel(?: booking)?$/i);
    expect(view.text()).toMatch(/4[:.]00|16:00/); await view.press(/^Confirm(?: cancellation)?$/i);
    expect(seam.cancel).toHaveBeenCalledWith(seam.mobile.api, id('20')); expect(seam.loadMember.mock.calls.length).toBeGreaterThan(1); view.unmount();
  });
  it.each([
    ['cancel_window_closed', "It's too close to the start time to cancel online. Speak to the front desk if you can't make it."],
    ['booking_not_cancellable', "This booking can't be cancelled any more."],
    ['booking_not_found', "That booking isn't available."],
    ['unknown_database_failure', 'Something went wrong and nothing was changed. Try again.'],
  ])('existing member cancellation refusal %s is pinned and never claims success', async (code, copy) => {
    seam.loadMember.mockResolvedValue([session({ availability: 'booked', myBookingId: id('20'), myBookingStatus: 'booked', canCancel: true, cancelBy: '2026-10-03T10:30:00Z' })]);
    seam.cancel.mockResolvedValue({ ok: false, error: { code, message: 'PRIVATE DATABASE DIAGNOSTIC' } });
    const view = mount(ClassesPane); await view.settle(); await view.press(/^Cancel(?: booking)?$/i); await view.press(/^Confirm(?: cancellation)?$/i);
    expect(view.text()).toContain(copy); expect(view.text()).not.toContain('PRIVATE DATABASE DIAGNOSTIC'); view.unmount();
  });
  it('an old member confirmation callback stays dead after A to B to A even when ids recur', async () => {
    seam.loadMember.mockResolvedValue([session({ availability: 'booked', myBookingId: id('20'), myBookingStatus: 'booked', canCancel: true, cancelBy: '2026-10-03T10:30:00Z' })]);
    const view = mount(ClassesPane); await view.settle(); await view.press(/^Cancel(?: booking)?$/i);
    const old = view.controls(/^Confirm(?: cancellation)?$/i)[0]; expect(old).toBeDefined();
    seam.mobile = { ...seam.mobile, identity: identityB }; view.rerender(); await view.settle();
    seam.mobile = { ...seam.mobile, identity: identityA }; view.rerender(); await view.settle();
    const callback = old?.props.onPress ?? old?.props.onClick; if (typeof callback === 'function') callback(); await view.settle();
    expect(seam.cancel).not.toHaveBeenCalled(); view.unmount();
  });
  it('an unmounted confirmation callback never sends its cancellation', async () => {
    seam.loadMember.mockResolvedValue([session({ availability: 'booked', myBookingId: id('20'), myBookingStatus: 'booked', canCancel: true, cancelBy: '2026-10-03T10:30:00Z' })]);
    const view = mount(ClassesPane); await view.settle(); await view.press(/^Cancel(?: booking)?$/i);
    const old = view.controls(/^Confirm(?: cancellation)?$/i)[0]; expect(old).toBeDefined(); view.unmount();
    const callback = old?.props.onPress ?? old?.props.onClick; if (typeof callback === 'function') callback();
    await Promise.resolve(); expect(seam.cancel).not.toHaveBeenCalled();
  });
  it('desk add-member search passes the current query to the caller-bound registered search', async () => {
    seam.mobile.identity = { kind: 'staff', userId: id('1'), tenantId: id('2'), staffId: id('7'), role: 'front_desk' };
    seam.search.mockResolvedValue([{ id: id('21'), fullName: 'Searched Hazel', phone: '9876500749', status: 'active', memberCode: 'G0749' }]);
    const view = mount(ClassesPane, { desk: true }); await view.settle(); await view.press(/Held yoga/); await view.press(/^Add member$/i);
    const field = view.nodes().find(node => typeof node.props.onChangeText === 'function'); expect(field).toBeDefined();
    const change = field?.props.onChangeText; if (typeof change === 'function') change('Hazel'); await view.settle(); await vi.advanceTimersByTimeAsync(1000); await view.settle();
    expect(seam.search).toHaveBeenCalledWith(seam.mobile.supabase, 'Hazel'); expect(view.text()).toContain('Searched Hazel'); view.unmount();
  });
  it('pending native member cancellation sends once and never presents an optimistic final result', async () => {
    seam.loadMember.mockResolvedValue([session({ availability: 'booked', myBookingId: id('20'), myBookingStatus: 'booked', canCancel: true, cancelBy: '2026-10-03T10:30:00Z' })]);
    const response = deferred<unknown>(); seam.cancel.mockReturnValue(response.promise);
    const view = mount(ClassesPane); await view.settle(); await view.press(/^Cancel(?: booking)?$/i); await view.press(/^Confirm(?: cancellation)?$/i);
    expect(seam.cancel).toHaveBeenCalledTimes(1); expect(view.controls(/^Confirm(?: cancellation)?$/i).filter(node => !node.props.disabled)).toHaveLength(0);
    expect(view.text()).not.toMatch(/booking cancelled|cancelled successfully/i);
    response.resolve({ ok: true, data: { bookingId: id('20'), status: 'cancelled_by_member' } }); await view.settle(); view.unmount();
  });
  it('desk cancellation requires a reason before submitting its exact booking command', async () => {
    seam.mobile.identity = { kind: 'staff', userId: id('1'), tenantId: id('2'), staffId: id('7'), role: 'front_desk' };
    seam.deskCancel.mockResolvedValue({ ok: true, data: { bookingId: id('20'), status: 'cancelled_by_gym' } });
    const view = mount(ClassesPane, { desk: true }); await view.settle(); await view.press(/Held yoga/); await view.press(/^Cancel booking$/i);
    expect(seam.deskCancel).not.toHaveBeenCalled(); expect(view.controls(/^Confirm(?: cancellation)?$/i).filter(node => !node.props.disabled)).toHaveLength(0);
    const input = view.nodes().find(node => typeof node.props.onChangeText === 'function' && /reason/i.test(String(node.props.placeholder ?? node.props.accessibilityLabel ?? ''))); expect(input).toBeDefined();
    const change = input?.props.onChangeText; if (typeof change === 'function') change('Member asked at desk'); await view.settle(); await view.press(/^Confirm(?: cancellation)?$/i);
    expect(seam.deskCancel).toHaveBeenCalledWith(seam.mobile.api, id('20'), 'Member asked at desk'); view.unmount();
  });
});
