import { isValidElement, type ReactNode } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { UI_TOKENS } from '@gymloop/shared';

// Public declarations only. These tests execute the real no-props surface.
const h = vi.hoisted(() => ({ cursor: 0, slots: [] as unknown[], effects: [] as Array<() => unknown>,
  cleanups: [] as Array<() => unknown>, changed: false, online: true,
  identity: { kind: 'member', tenantId: '73000000-0000-4000-8000-000000000001', userId: '73000000-0000-4000-8000-000000000002', memberId: '73000000-0000-4000-8000-000000000003' } as Record<string, string>,
  listeners: [] as Array<(state: unknown) => void>, load: vi.fn(), history: vi.fn(), post: vi.fn(), queue: vi.fn(), store: vi.fn(), navigate: vi.fn(), network: vi.fn(),
  ready: true, client: {} as Record<string, unknown>, api: null as { post: (...args: unknown[]) => unknown } | null,
}));
function hooks(actual: Record<string, unknown>) {
  const memo = (make: () => unknown, deps?: unknown[]) => {
    const index = h.cursor++; const prior = h.slots[index] as { deps?: unknown[]; value: unknown } | undefined;
    if (!prior || !deps || deps.some((value, offset) => !Object.is(value, prior.deps?.[offset]))) h.slots[index] = { deps, value: make() };
    return (h.slots[index] as { value: unknown }).value;
  };
  const overrides = {
    useState: (initial: unknown) => { const index = h.cursor++; if (!(index in h.slots)) h.slots[index] = typeof initial === 'function' ? (initial as () => unknown)() : initial;
      return [h.slots[index], (next: unknown) => { const result = typeof next === 'function' ? (next as (old: unknown) => unknown)(h.slots[index]) : next; if (!Object.is(result, h.slots[index])) { h.slots[index] = result; h.changed = true; } }]; },
    useRef: (initial: unknown) => memo(() => ({ current: initial }), []), useMemo: memo,
    useCallback: (callback: unknown, deps?: unknown[]) => memo(() => callback, deps),
    useEffect: (effect: () => unknown, deps?: unknown[]) => {
      const index = h.cursor++; const prior = h.slots[index] as { deps?: unknown[]; cleanup?: () => unknown } | undefined;
      if (!prior || !deps || deps.some((value, offset) => !Object.is(value, prior.deps?.[offset]))) {
        prior?.cleanup?.(); const cell = { deps, cleanup: undefined as (() => unknown) | undefined }; h.slots[index] = cell;
        h.effects.push(() => { const cleanup = effect(); if (typeof cleanup === 'function') { cell.cleanup = cleanup as () => unknown; h.cleanups.push(cell.cleanup); } });
      }
    },
  };
  return { ...actual, ...overrides, default: { ...(actual.default as Record<string, unknown>), ...overrides } };
}
vi.mock('react', async original => hooks(await original<Record<string, unknown>>()));
vi.mock('../mobile-context', () => ({ useMobile: () => ({ identity: h.identity, ready: h.ready, session: {},
  supabase: h.client, api: h.api, palette: UI_TOKENS.colors.light,
  nouns: { place: 'gym', session: 'session', sessions: 'sessions', member: 'member', members: 'members', trainer: 'trainer', class: 'class', classes: 'classes' }, businessType: 'gym',
}) }));
vi.mock('../training', () => ({ loadTraining: h.load, loadTrainingHistory: h.history }));
vi.mock('expo-network', () => ({ getNetworkStateAsync: h.network,
  addNetworkStateListener: (listener: (state: unknown) => void) => { h.listeners.push(listener); return { remove: () => { h.listeners = h.listeners.filter(item => item !== listener); } }; },
}));
vi.mock('expo-router', () => ({ useRouter: () => ({ push: h.navigate, replace: h.navigate }), router: { push: h.navigate, replace: h.navigate }, Link: 'Link', Redirect: 'Redirect' }));
vi.mock('expo-secure-store', () => ({ setItemAsync: h.store, getItemAsync: async () => null, deleteItemAsync: vi.fn() }));
vi.mock('../offline-check-in', () => ({ saveOfflineCheckIn: h.queue }));
vi.mock('react-native', () => ({ View: 'View', Text: 'Text', Pressable: 'Pressable', ScrollView: 'ScrollView', Image: 'Image', Modal: 'Modal', ActivityIndicator: 'ActivityIndicator',
  StyleSheet: { create: (value: unknown) => value }, useWindowDimensions: () => ({ width: 390, height: 844, fontScale: 2 }),
  AppState: { addEventListener: () => ({ remove: vi.fn() }) },
}));
vi.mock('lucide-react-native', () => new Proxy({}, { get: (_target, key) => key === 'then' ? undefined : 'Icon', has: () => true }));
vi.mock('../../components/ui', () => ({ ...Object.fromEntries(['Row', 'Status', 'StateMessage', 'EmptyState', 'ErrorRetry', 'ActionButton', 'RowAction', 'Body', 'Title', 'Eyebrow', 'LedgerSection', 'LoadingState', 'SheetHeader', 'Surface', 'Rule', 'Screen'].map(type => [type, (props: Record<string, unknown>) => ({ type, props })])),
  Sheet: (props: Record<string, unknown>) => props.visible ? { type: 'Sheet', props } : null,
}));

const orderId = '73000000-0000-4000-8000-000000000010';
const sessionId = '73000000-0000-4000-8000-000000000011';
const trainerKey = '73000000-0000-4000-8000-000000000012';
const session = { sessionId, orderId, programmeName: 'Exact sold strength', trainerKey, trainerName: 'Visible Rohit', startsAt: '2026-10-07T06:30:00Z', endsAt: '2026-10-07T07:30:00Z', timezone: 'Asia/Kolkata', status: 'booked', consumed: false, cancelledAt: null, cancelCutoff: '2026-10-06T06:30:00Z', lateNow: false, consumesNow: false, canCancel: true };
const pack = { orderId, programmeName: 'Visible live pack', trainerKey, trainerName: 'Visible Rohit', sessionsTotal: 10, sessionsUsed: 3, sessionsScheduled: 2, sessionsRemaining: 5, startsOn: '2026-10-01', expiresOn: '2026-10-31', state: 'live', canBook: true, timezone: 'Asia/Kolkata' };
const programme = { programmeId: '73000000-0000-4000-8000-000000000013', trainerKey, trainerName: 'Visible Rohit', trainerQualification: 'Certified coach', name: 'Visible disclosed offer', description: 'Individual strength coaching', pricePaise: '150000', currency: 'INR', gstRateBp: 1800, sessionCount: 10, validityDays: 30, cancellationTerms: 'Ask the front desk about unused sessions.' };
function data() { return {
  trainers: { data: [{ trainerKey, displayName: 'Visible Rohit', qualification: 'Certified coach', bio: 'Visible trainer biography', specialities: ['Strength'], imageUrl: null, branchName: 'Main', isProfileListed: true }], error: null },
  programmes: { data: [programme], error: null }, packs: { data: [pack], error: null },
  upcoming: { data: [session], error: null }, history: { data: [] as Array<typeof session>, error: null },
}; }
type Node = { type: unknown; props: Record<string, unknown> };
let component: () => ReactNode;
let tree: Node[];
function collect(value: unknown): void {
  if (Array.isArray(value)) { value.forEach(collect); return; }
  if (!value || typeof value !== 'object' || !('props' in value)) return;
  const node = value as Node;
  if (typeof node.type === 'function') { collect(node.type(node.props)); return; }
  tree.push(node); collect(node.props.children); collect(node.props.footer); collect(node.props.trailing); collect(node.props.meta); collect(node.props.status); collect(node.props.title);
}
async function mount() {
  const target = '../../components/training-section';
  const module = await import(target) as { TrainingSection: () => ReactNode };
  component = module.TrainingSection; expect(typeof component).toBe('function'); await render();
}
async function render() {
  for (let pass = 0; pass < 10; pass++) {
    h.cursor = 0; h.changed = false; tree = []; collect(component());
    h.effects.splice(0).forEach(effect => effect());
    await new Promise(resolve => setTimeout(resolve, 0));
    if (!h.changed && h.effects.length === 0) return;
  }
  throw new Error('Visible native surface did not settle');
}
function words(value: unknown): string {
  if (Array.isArray(value)) return value.map(words).join(' ');
  if (typeof value === 'string' || typeof value === 'number') return String(value);
  if (!value || typeof value !== 'object') return '';
  const node = value as Node;
  if (isValidElement(value) || 'props' in value) return words(node.props.children);
  return '';
}
function label(node: Node) { return [node.props.label, node.props.message, node.props.value, node.props.control, words(node.props.title), words(node.props.meta), words(node.props.children)].filter((value): value is string => typeof value === 'string' && value.trim().length > 0).map(value => value.trim()).join(' ').trim(); }
function visible() { return tree.map(label).join(' '); }
function descendants(node: Node) { const original = tree; tree = []; collect(node); const result = tree; tree = original; return result; }
function action(pattern: RegExp, scope = tree) { const node = scope.find(item => typeof item.props.onPress === 'function' && pattern.test(label(item))); expect(node).toBeDefined(); return node!; }
async function press(node: Node) { await (node.props.onPress as () => unknown)(); await render(); }
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(done => { resolve = done; }); return { promise, resolve }; }
function unmount() { h.cleanups.splice(0).forEach(cleanup => cleanup()); }
function revoke(kind: 'api' | 'client' | 'readiness') {
  if (kind === 'api') h.api = { post: h.post };
  else if (kind === 'client') h.client = { caller: 'replacement same-identity client' };
  else h.ready = false;
}
beforeEach(() => {
  unmount(); h.cursor = 0; h.slots = []; h.effects = []; h.changed = false; h.online = true; h.listeners = [];
  vi.useFakeTimers({ toFake: ['Date'] }); vi.setSystemTime(new Date(session.cancelCutoff));
  h.ready = true; h.client = { caller: 'public-fixture' }; h.api = { post: h.post };
  h.network.mockReset().mockImplementation(async () => ({ isConnected: h.online, isInternetReachable: h.online }));
  h.identity = { kind: 'member', tenantId: '73000000-0000-4000-8000-000000000001', userId: '73000000-0000-4000-8000-000000000002', memberId: '73000000-0000-4000-8000-000000000003' };
  h.load.mockReset().mockResolvedValue(data()); h.history.mockReset().mockResolvedValue({ data: [], error: null });
  h.post.mockReset().mockResolvedValue({ ok: true, data: { sessionId, status: 'cancelled_by_member', late: false, consumed: false, sessionsRemaining: 6, replayed: false } });
  h.queue.mockClear(); h.store.mockClear(); h.navigate.mockClear();
});
afterEach(() => { unmount(); vi.useRealTimers(); });

describe('PTF visible TrainingSection reads and existing-session cancellation', () => {
  it.each(['trainers', 'programmes', 'packs', 'upcoming', 'history'] as const)('keeps successful sections when %s fails independently', async section => {
    const fixture = data(); fixture[section] = { data: null, error: 'Please try again.' } as never; h.load.mockResolvedValue(fixture);
    await mount(); expect(visible()).toContain('Please try again.');
    if (section !== 'trainers') expect(visible()).toContain('Visible trainer biography');
    if (section !== 'programmes') expect(visible()).toContain('Visible disclosed offer');
    if (section !== 'packs') expect(visible()).toContain('Visible live pack');
    expect(h.post).not.toHaveBeenCalled();
  });
  it('keeps purchased, used, booked and remaining distinct; expired count is seven and unbookable', async () => {
    const fixture = data(); fixture.packs.data.push({ ...pack, orderId: '73000000-0000-4000-8000-000000000014', programmeName: 'Visible expired 10-3-2', sessionsRemaining: 7, state: 'expired', canBook: false, startsOn: '2026-09-01', expiresOn: '2026-09-30' });
    h.load.mockResolvedValue(fixture); await mount();
    const live = tree.find(node => node.type === 'Row' && /Visible live pack/.test(label(node)))!; expect(live).toBeDefined();
    const text = descendants(live).map(label).join(' '); expect(text).toMatch(/3\s*(?:of\s*10\s*)?used/i); expect(text).toContain('10'); expect(text).toMatch(/2\s*booked/i); expect(text).toMatch(/5\s*(?:left to book|remaining)/i);
    const expired = tree.find(node => node.type === 'Row' && /Visible expired 10-3-2/.test(label(node)))!; expect(expired).toBeDefined();
    const expiredNodes = descendants(expired); const expiredText = expiredNodes.map(label).join(' ');
    expect(expiredText).toMatch(/Expired/); expect(expiredText).toMatch(/7\s*(?:unused|remaining|left)/i); expect(expiredText).toMatch(/2\s*booked/i); expect(expiredText).toMatch(/Sep|September|2026-09/); expect(expiredText).toMatch(/30/);
    for (const button of expiredNodes.filter(node => /Book a session/.test(label(node)))) expect(button.props.disabled ?? typeof button.props.onPress !== 'function').toBe(true);
    expect(expired.props.onPress).toBeUndefined();
    expect(h.post).not.toHaveBeenCalled();
  });
  it('renders exact sold programme disclosures and offers only Show at the desk', async () => {
    await mount(); const text = visible(); expect(text).toContain('₹1,500'); expect(text).toMatch(/18\s*%/); expect(text).toContain(programme.description); expect(text).toContain(programme.trainerQualification); expect(text).toContain(programme.cancellationTerms);
    expect(text).toMatch(/10\s*session/); expect(text).toMatch(/30\s*day/); expect(text).toContain('Show at the desk');
    const desk = tree.find(node => typeof node.props.onPress === 'function' && /Show at the desk/.test(label(node))); if (desk) await press(desk);
    expect(h.post).not.toHaveBeenCalled(); expect(h.queue).not.toHaveBeenCalled();
  });
  it('uses the six pinned Status words and explains an unmarked past booking', async () => {
    const fixture = data(); fixture.upcoming.data = [{ ...session, startsAt: '2026-01-01T06:30:00Z', endsAt: '2026-01-01T07:30:00Z', canCancel: false }];
    fixture.history.data = [
      { ...session, status: 'attended' }, { ...session, status: 'no_show' },
      { ...session, status: 'cancelled_by_member' }, { ...session, status: 'cancelled_by_member', consumed: true }, { ...session, status: 'cancelled_by_gym' },
    ]; h.load.mockResolvedValue(fixture); await mount();
    const statuses = tree.filter(node => node.type === 'Status').map(label).join(' ');
    for (const word of ['Booked', 'Attended', 'No-show', 'Cancelled by you', 'Cancelled by your gym', 'Cancelled late - session used']) expect(statuses).toContain(word);
    expect(visible()).toContain('Waiting for your trainer to record it.');
  });
  it.each(['staff', 'platform', 'impersonation', 'unlinked'])('does not fetch member data or mutate for %s', async kind => {
    h.identity = { ...h.identity, kind }; await mount(); expect(h.load).not.toHaveBeenCalled(); expect(h.history).not.toHaveBeenCalled(); expect(h.post).not.toHaveBeenCalled();
  });
  it('discards late A results after A → B → A and results after unmount', async () => {
    const old = deferred<ReturnType<typeof data>>(); h.load.mockReturnValueOnce(old.promise); await mount();
    h.identity = { ...h.identity, memberId: '73000000-0000-4000-8000-000000000020' }; await render();
    h.identity = { ...h.identity, memberId: '73000000-0000-4000-8000-000000000003' }; await render();
    const poison = data(); poison.trainers.data[0]!.bio = 'Forbidden stale A generation'; old.resolve(poison); await render(); expect(visible()).not.toContain('Forbidden stale A generation');
    const later = deferred<ReturnType<typeof data>>(); h.load.mockReturnValueOnce(later.promise); h.identity = { ...h.identity, memberId: '73000000-0000-4000-8000-000000000021' }; await render(); unmount(); h.changed = false; later.resolve(poison); await new Promise(resolve => setTimeout(resolve, 0)); expect(h.changed).toBe(false);
  });
  it('refreshes current cancellation facts before each confirmation and keeps the command explicit', async () => {
    await mount(); const fresh = data(); fresh.upcoming.data[0] = { ...session, lateNow: true, consumesNow: true }; h.load.mockResolvedValue(fresh);
    await press(action(/^Cancel(?: session)?$/)); expect(h.load.mock.calls.length).toBeGreaterThan(1);
    expect(visible()).toContain('This is inside your cancellation window. Cancelling will use 1 session from your pack.'); expect(h.post).not.toHaveBeenCalled();
    const sheet = tree.find(node => node.type === 'Sheet')!; expect(sheet).toBeDefined(); (sheet.props.onClose as () => void)(); await render();
    fresh.upcoming.data[0] = { ...session, lateNow: false, consumesNow: false }; await press(action(/^Cancel(?: session)?$/));
    expect(visible()).toMatch(/Free to cancel until.*6.*Oct.*2026|Free to cancel until.*Oct.*6.*2026/); expect(visible()).toMatch(/12:00/); expect(h.post).not.toHaveBeenCalled();
  });
  it('preflights connectivity, never queues and never submits automatically after reconnect', async () => {
    await mount(); await press(action(/^Cancel(?: session)?$/)); h.online = false;
    await press(action(/Confirm|Cancel session/)); expect(h.post).not.toHaveBeenCalled(); expect(visible()).toContain('Please try again.'); expect(h.queue).not.toHaveBeenCalled(); expect(h.store).not.toHaveBeenCalled();
    h.online = true; h.listeners.forEach(listener => listener({ isConnected: true, isInternetReachable: true })); await render(); expect(h.post).not.toHaveBeenCalled();
  });
  it('marks last-loaded reads stale and disables cancellation while positively offline', async () => {
    await mount(); h.online = false; h.listeners.forEach(listener => listener({ isConnected: false, isInternetReachable: false })); await render();
    expect(visible()).toContain("You're offline. Showing what was last loaded."); expect(visible()).toContain('Visible live pack');
    expect(visible()).toMatch(/stale/i);
    for (const button of tree.filter(node => /^Cancel(?: session)?$/.test(label(node)))) expect(button.props.disabled).toBe(true);
    expect(h.post).not.toHaveBeenCalled(); expect(h.queue).not.toHaveBeenCalled();
  });
  it('suppresses pending double taps and posts only the existing session id', async () => {
    await mount(); await press(action(/^Cancel(?: session)?$/)); const pending = deferred<unknown>(); h.post.mockReturnValue(pending.promise);
    const confirm = action(/Confirm|Cancel session/); const first = (confirm.props.onPress as () => unknown)(); const second = (confirm.props.onPress as () => unknown)();
    await new Promise(resolve => setTimeout(resolve, 0)); expect(h.post).toHaveBeenCalledExactlyOnceWith('/api/member/pt-bookings/cancel', { sessionId });
    pending.resolve({ ok: true, data: { sessionId, status: 'cancelled_by_member', late: false, consumed: false, sessionsRemaining: 6, replayed: true } }); await Promise.all([first, second]); await render(); expect(h.post).toHaveBeenCalledTimes(1);
  });
  it.each(['thrown', 'unknown'])('shows honest retry after %s failure and reuses the session id', async failure => {
    await mount(); await press(action(/^Cancel(?: session)?$/));
    if (failure === 'thrown') h.post.mockRejectedValueOnce(new Error('private disconnected diagnostic'));
    else h.post.mockResolvedValueOnce({ ok: false, error: { code: 'unknown_private_code', message: 'PRIVATE SQL message' } });
    await press(action(/Confirm|Cancel session/)); expect(visible()).toMatch(/Please try again\.|That isn't available\./); expect(visible()).not.toMatch(/PRIVATE|private disconnected|Cancelled by you/);
    h.post.mockImplementationOnce(async () => {
      const accepted = data(); accepted.upcoming.data = []; accepted.history.data = [{ ...session, status: 'cancelled_by_member', canCancel: false }]; h.load.mockResolvedValue(accepted);
      return { ok: true, data: { sessionId, status: 'cancelled_by_member', late: false, consumed: false, sessionsRemaining: 6, replayed: true } };
    });
    await press(action(/Retry|Try again|Confirm|Cancel session/));
    expect(h.post).toHaveBeenCalledTimes(2); expect(h.post.mock.calls[0]).toEqual(h.post.mock.calls[1]); expect(h.post.mock.calls[1]).toEqual(['/api/member/pt-bookings/cancel', { sessionId }]);
    expect(visible()).toContain('Cancelled by you');
  });
  it('a retained confirmation from the previous caller cannot issue a request', async () => {
    await mount(); await press(action(/^Cancel(?: session)?$/)); const oldConfirm = action(/Confirm|Cancel session/);
    h.identity = { ...h.identity, memberId: '73000000-0000-4000-8000-000000000022' }; await render(); await (oldConfirm.props.onPress as () => unknown)(); await render(); expect(h.post).not.toHaveBeenCalled();
  });
  it.each([true, false])('fresh free-to-late consequence (%s consumption) requires renewed explicit confirmation with its absolute cutoff', async consumesNow => {
    vi.useFakeTimers({ toFake: ['Date'] }); vi.setSystemTime(new Date('2026-10-06T06:30:00.001Z'));
    await mount(); await press(action(/^Cancel(?: session)?$/)); const before = h.load.mock.calls.length;
    const fresh = data(); fresh.upcoming.data[0] = { ...session, lateNow: true, consumesNow }; h.load.mockResolvedValue(fresh);
    await press(action(/Confirm|Cancel session/)); expect(h.load.mock.calls.length).toBeGreaterThan(before); expect(h.post).not.toHaveBeenCalled();
    expect(visible()).toContain(consumesNow ? 'This is inside your cancellation window. Cancelling will use 1 session from your pack.' : "This is inside your cancellation window. Cancelling won't use a session from your pack.");
    expect(visible()).toMatch(/6.*Oct.*2026|Oct.*6.*2026/); expect(visible()).toContain('12:00');
    await press(action(/Confirm|Cancel session/)); expect(h.post).toHaveBeenCalledExactlyOnceWith('/api/member/pt-bookings/cancel', { sessionId });
  });
  it.each(['missing', 'null-cutoff', 'wrong-row', 'cancelled', 'uncancellable', 'read-error'] as const)('fresh %s before confirmation refuses without falling back to old facts', async failure => {
    await mount(); await press(action(/^Cancel(?: session)?$/)); const before = h.load.mock.calls.length; const fresh = data();
    if (failure === 'missing') fresh.upcoming.data = [];
    else if (failure === 'read-error') fresh.upcoming = { data: null, error: 'Please try again.' } as never;
    else fresh.upcoming.data[0] = { ...session, ...(failure === 'null-cutoff' ? { cancelCutoff: null } : failure === 'wrong-row' ? { sessionId: '73000000-0000-4000-8000-000000000081' } : failure === 'cancelled' ? { status: 'cancelled_by_member' } : { canCancel: false }) } as typeof session;
    h.load.mockResolvedValue(fresh); await press(action(/Confirm|Cancel session/)); expect(h.load.mock.calls.length).toBeGreaterThan(before); expect(h.post).not.toHaveBeenCalled();
  });
  it('preserves free cancellation at the exact inclusive cutoff through fresh prepare and confirm reads', async () => {
    vi.useFakeTimers({ toFake: ['Date'] }); vi.setSystemTime(new Date(session.cancelCutoff));
    await mount(); await press(action(/^Cancel(?: session)?$/)); expect(visible()).toMatch(/Free to cancel until/); expect(visible()).toContain('12:00');
    const before = h.load.mock.calls.length; await press(action(/Confirm|Cancel session/)); expect(h.load.mock.calls.length).toBeGreaterThan(before); expect(h.post).toHaveBeenCalledExactlyOnceWith('/api/member/pt-bookings/cancel', { sessionId });
  });
  it('a clock crossing while the exact-session read is paused cannot immediately send stale free facts', async () => {
    vi.useFakeTimers({ toFake: ['Date'] }); vi.setSystemTime(new Date('2026-10-06T06:29:59.999Z'));
    await mount(); await press(action(/^Cancel(?: session)?$/)); const pending = deferred<ReturnType<typeof data>>(); h.load.mockReturnValueOnce(pending.promise);
    const before = h.load.mock.calls.length; const oldConfirm = action(/Confirm|Cancel session/); const operation = (oldConfirm.props.onPress as () => unknown)();
    await new Promise(resolve => setTimeout(resolve, 0)); expect(h.load.mock.calls.length).toBeGreaterThan(before); expect(h.post).not.toHaveBeenCalled();
    vi.setSystemTime(new Date('2026-10-06T06:30:00.001Z')); pending.resolve(data()); await operation; await render(); expect(h.post).not.toHaveBeenCalled();
    const fresh = data(); fresh.upcoming.data[0] = { ...session, lateNow: true, consumesNow: true }; h.load.mockResolvedValue(fresh);
    await press(action(/Confirm|Cancel session/)); expect(h.post).not.toHaveBeenCalled(); expect(visible()).toContain('Cancelling will use 1 session from your pack.');
    await press(action(/Confirm|Cancel session/)); expect(h.post).toHaveBeenCalledTimes(1);
  });
  it.each(['api', 'client', 'readiness'] as const)('same-identity %s change permanently revokes retained cancellation handlers', async capability => {
    await mount(); await press(action(/^Cancel(?: session)?$/)); const oldConfirm = action(/Confirm|Cancel session/);
    const originalApi = h.api; const originalClient = h.client; revoke(capability); await render();
    h.api = originalApi; h.client = originalClient; h.ready = true; await render();
    await (oldConfirm.props.onPress as () => unknown)(); await render(); expect(h.post).not.toHaveBeenCalled(); expect(h.navigate).not.toHaveBeenCalled();
  });
  it.each(['api', 'client', 'readiness'] as const)('same-identity %s change discards preceding pending read data', async capability => {
    const pending = deferred<ReturnType<typeof data>>(); h.load.mockReturnValueOnce(pending.promise); await mount(); revoke(capability); await render();
    const poison = data(); poison.trainers.data[0]!.bio = 'Forbidden obsolete capability biography'; pending.resolve(poison); await render(); expect(visible()).not.toContain('Forbidden obsolete capability biography'); expect(h.post).not.toHaveBeenCalled();
  });
  it.each(['api', 'client', 'readiness'] as const)('late cancellation feedback is discarded after %s replacement', async capability => {
    await mount(); await press(action(/^Cancel(?: session)?$/)); const pending = deferred<unknown>(); h.post.mockReturnValueOnce(pending.promise);
    const operation = (action(/Confirm|Cancel session/).props.onPress as () => unknown)(); await new Promise(resolve => setTimeout(resolve, 0)); expect(h.post).toHaveBeenCalledTimes(1);
    revoke(capability); await render(); h.changed = false; pending.resolve({ ok: true, data: { sessionId, status: 'cancelled_by_member', late: false, consumed: false, sessionsRemaining: 6, replayed: false } }); await operation;
    expect(h.changed).toBe(false); expect(h.navigate).not.toHaveBeenCalled();
  });
  it('live pack Book action only navigates online to its exact order route and makes no command', async () => {
    await mount(); await press(action(/Book a session/)); expect(h.navigate).toHaveBeenCalledTimes(1);
    const destination = h.navigate.mock.calls[0]![0] as string | { pathname: string; params?: { orderId?: string } };
    if (typeof destination === 'string') expect(destination).toBe(`/training/book/${orderId}`);
    else { expect(destination.pathname).toBe('/training/book/[orderId]'); expect(destination.params?.orderId).toBe(orderId); }
    expect(h.post).not.toHaveBeenCalled(); expect(h.queue).not.toHaveBeenCalled();
  });
  it.each(['api', 'client', 'readiness'] as const)('same-identity %s change permanently revokes retained Book navigation', async capability => {
    await mount(); const oldBook = action(/Book a session/); const originalApi = h.api; const originalClient = h.client;
    revoke(capability); await render(); h.api = originalApi; h.client = originalClient; h.ready = true; await render();
    await (oldBook.props.onPress as () => unknown)(); await render(); expect(h.navigate).not.toHaveBeenCalled(); expect(h.post).not.toHaveBeenCalled();
  });
  it('unavailable and offline packs have no enabled Book action, explicit stale marker and no reconnect navigation', async () => {
    const fixture = data(); fixture.packs.data[0] = { ...pack, state: 'fully_booked', canBook: false, sessionsRemaining: 0 }; h.load.mockResolvedValue(fixture); await mount();
    for (const button of tree.filter(node => /Book a session/.test(label(node)))) expect(button.props.disabled ?? typeof button.props.onPress !== 'function').toBe(true);
    h.load.mockResolvedValue(data()); h.identity = { ...h.identity, memberId: '73000000-0000-4000-8000-000000000082' }; await render(); const book = action(/Book a session/);
    h.online = false; h.listeners.forEach(listener => listener({ isConnected: false, isInternetReachable: false })); await render();
    expect(visible()).toContain("You're offline. Showing what was last loaded."); expect(visible()).toMatch(/stale/i);
    for (const button of tree.filter(node => /Book a session/.test(label(node)))) expect(button.props.disabled).toBe(true);
    await (book.props.onPress as () => unknown)(); await render(); expect(h.navigate).not.toHaveBeenCalled();
    h.online = true; h.listeners.forEach(listener => listener({ isConnected: true, isInternetReachable: true })); await render(); expect(h.navigate).not.toHaveBeenCalled(); expect(h.post).not.toHaveBeenCalled(); expect(h.queue).not.toHaveBeenCalled();
  });
});
