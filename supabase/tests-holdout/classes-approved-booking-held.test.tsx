import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import type { MemberClassSession } from '@gymloop/shared';
import { businessNouns, UI_TOKENS } from '@gymloop/shared';

// Independent declaration-only author. These hosts preserve callbacks and children;
// they make no geometry, dot, axe, screen-reader or real-device claim.
type Props = Record<string, unknown>;
type Node = { type: unknown; props: Props };
type Cell = { value?: unknown; deps?: unknown[] | undefined; cleanup?: (() => void) | undefined };
const seam = vi.hoisted(() => ({
  active: null as null | { cells: Cell[]; cursor: number; effects: (() => void)[] },
  mobile: {} as Props, online: true, listeners: new Set<(state: Props) => void>(), appStateListeners: new Set<(state: string) => void>(),
  refresh: vi.fn(), audience: vi.fn(), webSchedule: vi.fn(), network: vi.fn(), loadMember: vi.fn(), loadBookings: vi.fn(), loadDesk: vi.fn(), loadRoster: vi.fn(),
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
vi.mock('../../apps/web/lib/identity-session', () => ({ requireAudience: seam.audience }));
vi.mock('../../apps/web/lib/classes', () => ({ loadMemberClassSchedule: seam.webSchedule }));
vi.mock('../../apps/web/lib/business-type', () => ({
  loadBusinessOrganization: async () => ({ data: { name: 'Held Gym', business_type: 'gym', timezone: 'Asia/Kolkata' }, error: null }),
  loadBusinessNouns: async () => businessNouns('gym'),
}));
vi.mock('../../apps/web/app/preview-context', () => ({ usePreviewReadOnly: () => false }));
vi.mock('../../apps/mobile/lib/mobile-context', () => ({ useMobile: () => seam.mobile }));
vi.mock('../../apps/mobile/lib/use-business-nouns', () => ({ useBusinessNouns: () => seam.mobile.nouns }));
vi.mock('../../apps/mobile/lib/classes', async importOriginal => {
  const actual = await importOriginal<Record<string, (...args: unknown[]) => Promise<unknown>>>();
  return { ...actual, loadMemberClasses: seam.loadMember, loadMemberUpcomingClassBookings: seam.loadBookings, loadDeskTimetable: seam.loadDesk, loadDeskRoster: seam.loadRoster,
    cancelClassBooking: (...args: unknown[]) => { seam.cancel(...args); return actual.cancelClassBooking!(...args); },
  };
});
vi.mock('../../apps/mobile/lib/mobile-data', () => ({ loadDeskMembers: seam.search }));
vi.mock('expo-network', () => ({ getNetworkStateAsync: () => seam.network(),
  addNetworkStateListener: (fn: (state: Props) => void) => { seam.listeners.add(fn); return { remove: () => seam.listeners.delete(fn) }; },
}));
vi.mock('expo-router', async () => {
  const { useEffect } = await import('react');
  return { useRouter: () => ({ push: vi.fn(), replace: vi.fn() }), router: { push: vi.fn() },
    useFocusEffect: (callback: () => void | (() => void)) => useEffect(callback, [callback]),
  };
});
vi.mock('react-native', () => ({ View: 'View', Text: 'Text', Pressable: 'Pressable', TextInput: 'TextInput',
  ScrollView: 'ScrollView', ActivityIndicator: 'ActivityIndicator', Modal: 'Modal',
  StyleSheet: { create: (styles: unknown) => styles, hairlineWidth: 1 }, Platform: { OS: 'android' },
  Linking: { openURL: vi.fn() }, useWindowDimensions: () => ({ width: 390, height: 844 }),
  AppState: { currentState: 'active', addEventListener: (_event: string, callback: (state: string) => void) => { seam.appStateListeners.add(callback); return { remove: () => seam.appStateListeners.delete(callback) }; } },
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
import { cancelClassBooking } from '../../apps/mobile/lib/classes';

const hostCleanups = new Set<() => void>();
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
  const unmount = () => { for (const frame of frames.values()) for (const cell of frame.cells) cell.cleanup?.(); frames.clear(); hostCleanups.delete(unmount); };
  hostCleanups.add(unmount);
  render();
  return { settle, press, controls, nodes: () => nodes, text: () => words.join(' '), rerender: (next: Props = props) => { props = next; render(); },
    unmount,
  };
}

const nouns = businessNouns('gym');
const id = (tail: string) => `77920000-0000-4000-8000-${tail.padStart(12, '0')}`;
const identityA = { kind: 'member', userId: id('1'), tenantId: id('2'), memberId: id('3') };
const identityB = { kind: 'member', userId: id('4'), tenantId: id('5'), memberId: id('6') };
const cutoff = '2026-10-03T10:30:00Z';
const deadline = new Date(cutoff).getTime();
function session(overrides: Partial<MemberClassSession> = {}): MemberClassSession {
  return { sessionId: id('10'), serviceId: id('11'), serviceName: 'Held policy yoga', serviceDescription: 'Breathing',
    branchId: id('12'), branchName: 'East studio', timezone: 'Asia/Kolkata', sessionDate: '2026-10-03',
    startsAt: '2026-10-03T12:30:00Z', endsAt: '2026-10-03T13:30:00Z', trainerName: 'Teacher Mira', capacity: 17,
    bookedCount: 13, spotsLeft: 4, sessionStatus: 'scheduled', myBookingId: null, myBookingStatus: null,
    availability: 'open', canCancel: false, cancelBy: cutoff, ...overrides };
}
function cancellable() { return session({ availability: 'booked', myBookingId: id('20'), myBookingStatus: 'booked', canCancel: true }); }
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(done => { resolve = done; }); return { promise, resolve }; }
const browser = new EventTarget();
beforeEach(() => {
  vi.useFakeTimers(); vi.setSystemTime(new Date('2026-10-03T07:00:00Z')); vi.resetAllMocks();
  seam.online = true; seam.listeners.clear(); seam.appStateListeners.clear();
  seam.network.mockImplementation(async () => ({ isConnected: seam.online, isInternetReachable: seam.online }));
  const query = { select: vi.fn().mockReturnThis(), eq: vi.fn().mockReturnThis(), maybeSingle: vi.fn(async () => ({ data: { timezone: 'Asia/Kolkata', branch_id: id('12') }, error: null })) };
  const post = vi.fn(async (path: string) => ({ ok: true, data: { bookingId: id('20'), status: path.endsWith('/cancel') ? 'cancelled_by_member' : 'booked', spotsLeft: 3 } }));
  seam.mobile = { identity: identityA, ready: true, supabase: { from: vi.fn(() => query) }, api: { post }, palette: UI_TOKENS.colors.light, nouns, businessType: 'gym', webOrigin: 'https://gymloop.test' };
  seam.loadMember.mockResolvedValue([session()]); seam.loadBookings.mockResolvedValue([]); seam.webSchedule.mockResolvedValue([session()]);
  seam.search.mockResolvedValue([]);
  vi.stubGlobal('window', browser); vi.stubGlobal('navigator', { onLine: true });
  vi.stubGlobal('fetch', vi.fn(async (path: string) => ({ ok: true, json: async () => ({ ok: true, data: { bookingId: id('20'), status: path.endsWith('/cancel') ? 'cancelled_by_member' : 'booked', spotsLeft: 3 } }) })));
});
afterEach(() => { for (const cleanup of hostCleanups) cleanup(); vi.useRealTimers(); vi.unstubAllGlobals(); });

function setup(platform: 'web' | 'native', initial = session()) {
  const refresh = vi.fn<() => Promise<MemberClassSession[] | null>>().mockResolvedValue([initial]);
  if (platform === 'native') { seam.loadMember.mockResolvedValue([initial]); seam.loadBookings.mockResolvedValue(initial.myBookingId === null ? [] : [initial]); }
  const props = { sessions: [initial], today: '2026-10-03', nouns, scopeKey: 'held-A', refreshSessions: refresh };
  const view = platform === 'web' ? mount(MemberClassesView, props) : mount(ClassesPane);
  const replaceRead = (result: MemberClassSession[] | null | Promise<MemberClassSession[] | null>) => {
    if (platform === 'web') refresh.mockImplementation(() => Promise.resolve(result));
    else {
      seam.loadMember.mockImplementation(() => Promise.resolve(result));
      seam.loadBookings.mockImplementation(() => Promise.resolve(result).then(rows => rows?.filter(row => row.myBookingId !== null) ?? null));
    }
  };
  const enabled = (pattern: RegExp) => view.controls(pattern).filter(node => !node.props.disabled && !(node.props.accessibilityState as Props | undefined)?.disabled);
  const post = (seam.mobile.api as { post: ReturnType<typeof vi.fn> }).post;
  return { view, refresh, props, replaceRead, enabled, post,
    assertNoSend: () => { expect(fetch).not.toHaveBeenCalled(); expect(post).not.toHaveBeenCalled(); },
    switchCaller: async () => {
      if (platform === 'web') { view.rerender({ ...props, scopeKey: 'held-B' }); await view.settle(); view.rerender(props); }
      else { seam.mobile = { ...seam.mobile, identity: identityB }; view.rerender(); await view.settle(); seam.mobile = { ...seam.mobile, identity: identityA }; view.rerender(); }
      await view.settle();
    },
  };
}

describe.each(['web', 'native'] as const)('CLS approved %s prebooking current projection', platform => {
  it('refreshes before commitment and displays the exact current branch-local deadline', async () => {
    const h = setup(platform, session({ cancelBy: null })); await h.view.settle();
    h.replaceRead([session({ branchName: 'Current annex', timezone: 'Asia/Kathmandu', cancelBy: '2026-10-03T09:30:00Z' })]);
    await h.view.press(/^Book$/); h.assertNoSend();
    if (platform === 'web') expect(h.refresh).toHaveBeenCalledWith();
    else expect(seam.loadMember.mock.calls.length).toBeGreaterThan(1);
    expect(h.view.text()).toContain('Current annex'); expect(h.view.text()).toMatch(/3[:.]15|15:15/);
    expect(h.enabled(/^Confirm(?: booking)?$/i)).toHaveLength(1);
    await h.view.press(/^Confirm(?: booking)?$/i);
    if (platform === 'web') expect(fetch).toHaveBeenCalledWith('/api/class-bookings', expect.objectContaining({ body: JSON.stringify({ sessionId: id('10') }) }));
    else expect(h.post).toHaveBeenCalledWith('/api/class-bookings', { sessionId: id('10') });
    h.view.unmount();
  });

  it('has no enabled confirm or send while its current schedule refresh is unresolved', async () => {
    const h = setup(platform); await h.view.settle(); const current = deferred<MemberClassSession[] | null>(); h.replaceRead(current.promise);
    await h.view.press(/^Book$/); expect(h.enabled(/^Confirm(?: booking)?$/i)).toHaveLength(0); h.assertNoSend();
    current.resolve([session()]); await h.view.settle(); expect(h.enabled(/^Confirm(?: booking)?$/i)).toHaveLength(1); h.view.unmount();
  });

  it.each([
    ['failed read', null], ['missing exact row', []], ['other session only', [session({ sessionId: id('98') })]],
    ['missing deadline', [session({ cancelBy: null })]], ['full', [session({ availability: 'full', spotsLeft: 0 })]],
    ['cancelled', [session({ availability: 'cancelled', sessionStatus: 'cancelled' })]],
    ['closed', [session({ availability: 'closed' })]], ['membership not live', [session({ availability: 'membership_not_live' })]],
  ] as Array<[string, MemberClassSession[] | null]>)('refuses %s rather than the stale open row', async (_label, fresh) => {
    const h = setup(platform); await h.view.settle(); h.replaceRead(fresh); await h.view.press(/^Book$/);
    expect(h.enabled(/^Confirm(?: booking)?$/i)).toHaveLength(0); h.assertNoSend(); h.view.unmount();
  });

  it.each(['unmount', 'A to B to A'])('obsolete preparation stays dead after %s', async revoke => {
    const h = setup(platform); await h.view.settle(); const read = deferred<MemberClassSession[] | null>(); h.replaceRead(read.promise);
    await h.view.press(/^Book$/); if (revoke === 'unmount') h.view.unmount(); else { h.replaceRead([session()]); await h.switchCaller(); }
    read.resolve([session({ serviceName: 'Obsolete caller prepared class' })]);
    if (revoke === 'unmount') { await Promise.resolve(); await Promise.resolve(); } else { await h.view.settle(); expect(h.view.text()).not.toContain('Obsolete caller prepared class'); h.view.unmount(); }
    h.assertNoSend();
  });

  it.each(['unmount', 'A to B to A'])('retained ready confirmation cannot dispatch after %s', async revoke => {
    const h = setup(platform); await h.view.settle(); await h.view.press(/^Book$/);
    const button = h.enabled(/^Confirm(?: booking)?$/i)[0]; expect(button).toBeDefined();
    const callback = button?.props.onClick ?? button?.props.onPress;
    if (revoke === 'unmount') h.view.unmount(); else await h.switchCaller();
    if (typeof callback === 'function') callback();
    await Promise.resolve(); await Promise.resolve(); h.assertNoSend(); if (revoke !== 'unmount') h.view.unmount();
  });
});

describe('CLS approved actual native helper and pane final cancellation guard', () => {
  it.each(['inclusive cutoff', 'one millisecond late', 'revoked', 'throwing'] as const)('actual helper after paused preflight: %s', async scenario => {
    const preflight = deferred<{ isConnected: boolean; isInternetReachable: boolean }>(); seam.network.mockReturnValue(preflight.promise);
    const post = vi.fn(async () => ({ ok: true, data: { bookingId: id('20'), status: 'cancelled_by_member' } })); let current = true; let throws = false;
    const guard = () => { if (throws) throw new Error('Revoked presentation'); return current && Date.now() <= deadline; };
    const pending = cancelClassBooking({ post } as never, id('20'), guard);
    expect(post).not.toHaveBeenCalled(); vi.setSystemTime(new Date(deadline + (scenario === 'one millisecond late' ? 1 : 0)));
    if (scenario === 'revoked') current = false; if (scenario === 'throwing') throws = true;
    preflight.resolve({ isConnected: true, isInternetReachable: true }); const result = await pending;
    if (scenario === 'inclusive cutoff') { expect(post).toHaveBeenCalledExactlyOnceWith('/api/class-bookings/cancel', { bookingId: id('20') }); expect(result.ok).toBe(true); }
    else { expect(post).not.toHaveBeenCalled(); expect(result.ok).toBe(false); }
  });

  it.each(['inclusive cutoff', 'one millisecond late', 'caller revoked', 'unmounted'] as const)('actual pane supplies final eligibility after helper-only paused preflight: %s', async scenario => {
    const h = setup('native', cancellable()); await h.view.settle(); await h.view.press(/^Cancel(?: booking)?$/i);
    const preflight = deferred<{ isConnected: boolean; isInternetReachable: boolean }>();
    // Observe entry, then pause only the real helper's own network await; pane preflights remain real and online.
    seam.cancel.mockImplementation(() => { seam.network.mockReturnValue(preflight.promise); });
    await h.view.press(/^Confirm(?: cancellation)?$/i); expect(seam.cancel).toHaveBeenCalledTimes(1); h.assertNoSend();
    vi.setSystemTime(new Date(deadline + (scenario === 'one millisecond late' ? 1 : 0)));
    if (scenario === 'caller revoked') await h.switchCaller(); if (scenario === 'unmounted') h.view.unmount();
    preflight.resolve({ isConnected: true, isInternetReachable: true });
    if (scenario === 'unmounted') { for (let turn = 0; turn < 12; turn++) await Promise.resolve(); } else await h.view.settle();
    if (scenario === 'inclusive cutoff') expect(h.post).toHaveBeenCalledExactlyOnceWith('/api/class-bookings/cancel', { bookingId: id('20') });
    else { expect(h.post).not.toHaveBeenCalled(); expect(h.view.text()).not.toMatch(/booking cancelled|cancellation successful/i); }
    if (scenario !== 'unmounted') h.view.unmount();
  });
});
