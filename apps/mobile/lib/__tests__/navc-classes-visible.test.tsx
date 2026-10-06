import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { businessNouns, type MemberClassSession } from '@gymloop/shared';
import { ClassesPane } from '../../components/classes-pane';

type Props = Record<string, unknown>;
type Node = { type: unknown; props: Props; path?: string };
type Slot = { value?: unknown; deps?: readonly unknown[] | undefined; cleanup?: (() => void) | undefined };
const seam = vi.hoisted(() => ({
  stores: new Map<string, Slot[]>(), path: '', cursor: 0, effects: [] as Array<() => void>,
  loadMember: vi.fn(), loadUpcoming: vi.fn(), loadTimetable: vi.fn(), loadRoster: vi.fn(), search: vi.fn(),
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
vi.mock('../../lib/classes', () => ({ loadMemberClasses: seam.loadMember, loadMemberUpcomingClassBookings: seam.loadUpcoming, loadDeskTimetable: seam.loadTimetable, loadDeskRoster: seam.loadRoster, bookClass: seam.book, cancelClassBooking: seam.cancel, deskBookClass: seam.deskBook, deskCancelClassBooking: seam.deskCancel, markClassAttendance: seam.mark }));
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
const member = { kind: 'member', userId: '74000000-0000-4000-8000-000000000711', tenantId: '74000000-0000-4000-8000-000000000712', memberId: '74000000-0000-4000-8000-000000000713' };
const yoga: MemberClassSession = {
  sessionId: '74000000-0000-4000-8000-000000000701', serviceId: '74000000-0000-4000-8000-000000000702', branchId: '74000000-0000-4000-8000-000000000703',
  serviceName: 'Hatha Yoga', serviceDescription: 'Actual owner service name', branchName: 'East studio', timezone: 'Asia/Kolkata', sessionDate: '2026-10-06',
  startsAt: '2026-10-06T18:00:00+05:30', endsAt: '2026-10-06T19:00:00+05:30', trainerName: 'Yoga lead sentinel', capacity: 13, bookedCount: 9, spotsLeft: 4,
  sessionStatus: 'scheduled', myBookingId: null, myBookingStatus: null, availability: 'open', canCancel: false, cancelBy: null,
};
const dance: MemberClassSession = { ...yoga, sessionId: '74000000-0000-4000-8000-000000000704', serviceId: '74000000-0000-4000-8000-000000000705', serviceName: 'Contemporary beginners', trainerName: 'Dance lead sentinel', startsAt: '2026-10-06T16:00:00+05:30', endsAt: '2026-10-06T17:00:00+05:30' };
const commitment: MemberClassSession = { ...yoga, sessionId: '74000000-0000-4000-8000-000000000706', serviceName: 'Booked distant branch Yoga', trainerName: 'Commitment-only lead', branchName: 'Commitment-only branch', timezone: 'America/Los_Angeles', sessionDate: '2026-10-05', startsAt: '2026-10-05T23:45:00-07:00', endsAt: '2026-10-06T00:45:00-07:00', myBookingId: '74000000-0000-4000-8000-000000000707', myBookingStatus: 'booked', availability: 'booked', canCancel: true, cancelBy: '2026-10-05T22:00:00-07:00' };
let bookingsOnly = false;
let nodes: Node[] = [];
function visit(value: unknown, path: string): void {
  if (Array.isArray(value)) { value.forEach((child, index) => visit(child, `${path}/${index}`)); return; }
  if (!value || typeof value !== 'object' || !('type' in value) || !('props' in value)) return;
  const node = value as Node;
  if (typeof node.type === 'function') {
    const prior = seam.path; const cursor = seam.cursor; seam.path = path; seam.cursor = 0;
    const output: unknown = node.type(node.props); seam.path = prior; seam.cursor = cursor; visit(output, `${path}/render`); return;
  }
  nodes.push({ ...node, path });
  for (const key of ['children', 'title', 'meta', 'status', 'trailing', 'icon']) visit(node.props[key], `${path}/${key}`);
}
function draw() { nodes = []; visit({ type: ClassesPane, props: { bookingsOnly } }, 'root'); seam.effects.splice(0).forEach(effect => effect()); }
async function settle() { for (let tick = 0; tick < 16; tick++) { await Promise.resolve(); draw(); } }
function words(value: unknown): string {
  if (typeof value === 'string' || typeof value === 'number') return String(value);
  if (Array.isArray(value)) return value.map(words).join(' ');
  if (value && typeof value === 'object' && 'props' in value) return words((value as Node).props.children);
  return '';
}
function visible() { return nodes.map(node => ['children', 'title', 'meta', 'detail', 'message', 'value'].map(key => words(node.props[key])).join(' ')).join(' ').replace(/\s+/g, ' '); }
function controls(label: RegExp) { return nodes.filter(node => typeof (node.props.onPress ?? node.props.onRetry) === 'function' && ['children', 'title', 'accessibilityLabel'].some(key => label.test(words(node.props[key]).trim()))); }
async function press(label: RegExp) { const node = controls(label).at(-1); expect(node, `rendered ${label} action`).toBeDefined(); await ((node?.props.onPress ?? node?.props.onRetry) as () => unknown)(); await settle(); }
function cleanup() { seam.stores.forEach(slots => slots.forEach(slot => slot.cleanup?.())); seam.stores.clear(); seam.effects = []; }
beforeEach(() => {
  cleanup(); vi.clearAllMocks(); vi.useFakeTimers(); vi.setSystemTime(new Date('2026-10-06T10:00:00+05:30')); bookingsOnly = false; seam.network = true; seam.networkListener = null;
  seam.context = { identity: member, ready: true, session: { user: { id: member.userId }, access_token: 'fixture-token' }, businessType: 'gym', nouns: businessNouns('gym'), palette: {}, api: { post: vi.fn() }, supabase: {
    from: () => ({ select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: { timezone: 'Asia/Kolkata', branch_id: yoga.branchId }, error: null }) }) }) }),
    auth: { onAuthStateChange: () => ({ data: { subscription: { unsubscribe: vi.fn() } } }) },
  }, webOrigin: 'https://gymloop.test' };
  seam.loadMember.mockResolvedValue([yoga, dance]); seam.loadUpcoming.mockResolvedValue([commitment]);
  seam.book.mockResolvedValue({ ok: true, data: { bookingId: commitment.myBookingId, status: 'booked', spotsLeft: 3 } }); seam.cancel.mockResolvedValue({ ok: true, data: { bookingId: commitment.myBookingId, status: 'cancelled_by_member' } });
});
afterEach(() => { cleanup(); vi.useRealTimers(); });
describe('NAVC-011 stable activities and independent My bookings', () => {
  it('offers All activities and actual authorised service names with chronological occurrences', async () => {
    draw(); await settle(); expect(controls(/^All activities$/i)).not.toHaveLength(0);
    expect(controls(/^Hatha Yoga$/)).not.toHaveLength(0); expect(controls(/^Contemporary beginners$/)).not.toHaveLength(0);
    expect(visible().indexOf('Dance lead sentinel')).toBeLessThan(visible().indexOf('Yoga lead sentinel'));
    expect(seam.context.businessType).toBe('gym');
  });
  it('selecting Dance removes Yoga timetable rows but keeps caller-owned commitments and their cancellation', async () => {
    draw(); await settle(); await press(/^Contemporary beginners$/);
    expect(visible()).toContain('Dance lead sentinel'); expect(visible()).not.toContain('Yoga lead sentinel');
    expect(visible()).toContain('Booked distant branch Yoga'); expect(visible()).toContain('Commitment-only branch'); expect(controls(/^Cancel(?: booking)?$/i)).not.toHaveLength(0);
    expect(seam.loadUpcoming).toHaveBeenCalledWith(seam.context.supabase); expect(seam.book).not.toHaveBeenCalled(); expect(seam.cancel).not.toHaveBeenCalled();
  });
  it('different service identities with the same name retain separate selectable filters', async () => {
    seam.loadMember.mockResolvedValue([{ ...yoga, serviceName: 'Movement', trainerName: 'First service sentinel' }, { ...dance, serviceName: 'Movement', trainerName: 'Second service sentinel' }]);
    draw(); await settle(); const filters = controls(/^Movement$/).filter(node => node.type !== 'Row'); expect(filters).toHaveLength(2);
    await (filters[1]!.props.onPress as () => unknown)(); await settle();
    expect(visible()).toContain('Second service sentinel'); expect(visible()).not.toContain('First service sentinel');
  });
  it('activity present on another date produces a truthful filtered empty day while keeping controls and bookings', async () => {
    seam.loadMember.mockResolvedValue([yoga, { ...dance, sessionDate: '2026-10-07', startsAt: '2026-10-07T16:00:00+05:30', endsAt: '2026-10-07T17:00:00+05:30' }]);
    draw(); await settle(); await press(/^Contemporary beginners$/);
    expect(visible()).not.toContain('Dance lead sentinel'); expect(visible()).toMatch(/no .*scheduled|no .*on .*day|no .*for .*day|none .*today/i);
    expect(controls(/^All activities$/i)).not.toHaveLength(0); expect(visible()).toContain(commitment.serviceName);
  });
  it('separate own-bookings reader retains a booked branch absent from an empty authorised catalogue', async () => {
    seam.loadMember.mockResolvedValue([]); draw(); await settle();
    expect(seam.loadUpcoming).toHaveBeenCalledWith(seam.context.supabase); expect(visible()).toContain(commitment.serviceName); expect(visible()).toContain(commitment.branchName);
    expect(controls(/^Cancel(?: booking)?$/i)).not.toHaveLength(0); expect(visible()).toMatch(/23:45|11:45\s*pm/i);
  });
  it('bookingsOnly renders own commitments independently without opening timetable purchase opportunities', async () => {
    bookingsOnly = true; draw(); await settle(); expect(seam.loadUpcoming).toHaveBeenCalledWith(seam.context.supabase);
    expect(visible()).toContain(commitment.serviceName); expect(visible()).not.toContain('Dance lead sentinel'); expect(visible()).not.toContain('Yoga lead sentinel'); expect(controls(/^Book$/i)).toHaveLength(0);
  });
  it('a cancelled own commitment remains truthful and never becomes a new Book action', async () => {
    bookingsOnly = true; seam.loadUpcoming.mockResolvedValue([{ ...commitment, myBookingStatus: 'cancelled_by_member', availability: 'closed', canCancel: false }]);
    draw(); await settle(); expect(visible()).toContain(commitment.serviceName); expect(visible()).toMatch(/Cancelled/i); expect(controls(/^Book$/i)).toHaveLength(0); expect(controls(/^Cancel(?: booking)?$/i)).toHaveLength(0);
  });
  it('own-bookings failure is a recoverable failure rather than no bookings', async () => {
    bookingsOnly = true; seam.loadUpcoming.mockResolvedValue(null); draw(); await settle();
    expect(visible()).toMatch(/could not|couldn't|try again|unable|didn't load/i); expect(controls(/try again|retry|refresh/i)).not.toHaveLength(0); expect(visible()).not.toMatch(/no (upcoming )?bookings|no booked/i);
  });
  it('a removed selected service resets to All activities after authorized refresh', async () => {
    draw(); await settle(); await press(/^Hatha Yoga$/); expect(visible()).not.toContain('Dance lead sentinel');
    seam.loadMember.mockResolvedValue([dance]); await press(/^Refresh timetable$/i);
    expect(visible()).toContain('Dance lead sentinel'); expect(controls(/^All activities$/i)).not.toHaveLength(0); expect(visible()).toContain(commitment.serviceName);
  });
  it('date selection uses branch-local start day while My bookings stays independent', async () => {
    seam.loadMember.mockResolvedValue([yoga, { ...dance, sessionDate: '2026-10-07', startsAt: '2026-10-07T00:30:00+05:30', endsAt: '2026-10-07T01:30:00+05:30' }]);
    draw(); await settle(); await press(/^7 Oct 2026$/);
    expect(visible()).toContain('Dance lead sentinel'); expect(visible()).not.toContain('Yoga lead sentinel'); expect(visible()).toContain(commitment.serviceName);
  });
  it.each([['dance', 'instructor'], ['yoga', 'teacher'], ['gym', 'trainer'], ['martial_arts', 'instructor'], ['studio', 'trainer']] as const)('%s retains actual service names and its %s noun', async (type, trainer) => {
    seam.context = { ...seam.context, businessType: type, nouns: businessNouns(type) }; draw(); await settle();
    expect(visible()).toContain(yoga.serviceName); expect(visible()).toContain(dance.serviceName); expect(visible()).toMatch(new RegExp(trainer, 'i'));
  });
});
