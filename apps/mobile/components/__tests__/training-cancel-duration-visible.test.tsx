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
vi.mock('../../lib/mobile-context', () => ({ useMobile: () => ({ identity: h.identity, ready: h.ready, session: {},
  supabase: h.client, api: h.api, palette: UI_TOKENS.colors.light,
  nouns: { place: 'gym', session: 'session', sessions: 'sessions', member: 'member', members: 'members', trainer: 'trainer', class: 'class', classes: 'classes' }, businessType: 'gym',
}) }));
vi.mock('../../lib/training', () => ({ loadTraining: h.load, loadTrainingHistory: h.history }));
vi.mock('expo-network', () => ({ getNetworkStateAsync: h.network,
  addNetworkStateListener: (listener: (state: unknown) => void) => { h.listeners.push(listener); return { remove: () => { h.listeners = h.listeners.filter(item => item !== listener); } }; },
}));
vi.mock('expo-router', () => ({ useRouter: () => ({ push: h.navigate, replace: h.navigate }), router: { push: h.navigate, replace: h.navigate }, Link: 'Link', Redirect: 'Redirect' }));
vi.mock('expo-secure-store', () => ({ setItemAsync: h.store, getItemAsync: async () => null, deleteItemAsync: vi.fn() }));
vi.mock('../../lib/offline-check-in', () => ({ saveOfflineCheckIn: h.queue }));
vi.mock('react-native', () => ({ View: 'View', Text: 'Text', Pressable: 'Pressable', ScrollView: 'ScrollView', Image: 'Image', Modal: 'Modal', ActivityIndicator: 'ActivityIndicator',
  StyleSheet: { create: (value: unknown) => value }, useWindowDimensions: () => ({ width: 390, height: 844, fontScale: 2 }),
  AppState: { addEventListener: () => ({ remove: vi.fn() }) },
}));
vi.mock('lucide-react-native', () => new Proxy({}, { get: (_target, key) => key === 'then' ? undefined : 'Icon', has: () => true }));
vi.mock('../ui', () => ({ ...Object.fromEntries(['Row', 'Status', 'StateMessage', 'EmptyState', 'ErrorRetry', 'ActionButton', 'RowAction', 'Body', 'Title', 'Eyebrow', 'LedgerSection', 'LoadingState', 'SheetHeader', 'Surface', 'Rule', 'Screen'].map(type => [type, (props: Record<string, unknown>) => ({ type, props })])),
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
  const target = '../training-section';
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
function descendants(node: Node) { const original = tree; tree = []; collect(node); const result = tree; tree = original; return result; }
function action(pattern: RegExp, scope = tree) { const node = scope.find(item => typeof item.props.onPress === 'function' && pattern.test(label(item))); expect(node).toBeDefined(); return node!; }
async function press(node: Node) { await (node.props.onPress as () => unknown)(); await render(); }
function unmount() { h.cleanups.splice(0).forEach(cleanup => cleanup()); }
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


const intervals = [
  { name: 'recorded sixty minutes', startsAt: '2026-10-07T06:30:00Z', endsAt: '2026-10-07T07:30:00Z', start: /12:00/, end: /1:00|13:00/, duration: /60\s*(?:min|minute)|1\s*(?:hr|hour)/i },
  { name: 'recorded ninety minutes independent of defaults', startsAt: '2026-10-07T06:30:00Z', endsAt: '2026-10-07T08:00:00Z', start: /12:00/, end: /1:30|13:30/, duration: /90\s*(?:min|minute)|1\s*(?:hr|hour).*30\s*(?:min|minute)/i },
  { name: 'unrounded legacy ninety and a half minutes', startsAt: '2026-10-07T06:30:00Z', endsAt: '2026-10-07T08:00:30Z', start: /12:00/, end: /1:30|13:30/, duration: /90\.5\s*(?:min|minute)|90\s*(?:min|minute).*30\s*(?:s|sec)|1\s*(?:hr|hour).*30\s*(?:min|minute).*30\s*(?:s|sec)/i },
  { name: 'local midnight and date transition', startsAt: '2026-10-07T18:00:00Z', endsAt: '2026-10-07T19:30:00Z', start: /11:30|23:30/, end: /1:00|01:00/, duration: /90\s*(?:min|minute)|1\s*(?:hr|hour).*30\s*(?:min|minute)/i },
];
const invalidIntervals = [
  { name: 'unavailable start', startsAt: '', endsAt: session.endsAt },
  { name: 'unavailable end', startsAt: session.startsAt, endsAt: '' },
  { name: 'malformed start', startsAt: 'invalid', endsAt: session.endsAt },
  { name: 'malformed end', startsAt: session.startsAt, endsAt: 'invalid' },
  { name: 'equal interval', startsAt: session.startsAt, endsAt: session.startsAt },
  { name: 'reversed interval', startsAt: session.endsAt, endsAt: session.startsAt },
];

function confirmationText() { const sheet = tree.find(node => node.type === 'Sheet'); expect(sheet).toBeDefined(); return descendants(sheet!).map(label).join(' '); }
function confirmationAction() { const sheet = tree.find(node => node.type === 'Sheet'); expect(sheet).toBeDefined(); return action(/Confirm|Cancel session/, descendants(sheet!)); }
function setCurrent(row: typeof session) { const fixture = data(); fixture.upcoming.data = [row]; h.load.mockResolvedValue(fixture); }
describe('PTF-Q2 native recorded cancellation interval', () => {
  it.each([
    { consumesNow: true, sentence: 'This is inside your cancellation window. Cancelling will use 1 session from your pack.' },
    { consumesNow: false, sentence: "This is inside your cancellation window. Cancelling won't use a session from your pack." },
  ])('preserves exact late consequence and absolute cutoff: $consumesNow', async facts => {
    await mount(); setCurrent({ ...session, lateNow: true, ...facts }); await press(action(/^Cancel(?: session)?$/)); const copy = confirmationText();
    expect(copy).toContain(facts.sentence); expect(copy).toMatch(/6.*Oct.*2026|Oct.*6.*2026/); expect(copy).toMatch(/12:00/); expect(h.post).not.toHaveBeenCalled();
  });
  it.each(intervals)('shows $name and both current local instants before send', async interval => {
    await mount(); setCurrent({ ...session, ...interval }); await press(action(/^Cancel(?: session)?$/)); const copy = confirmationText();
    expect(copy).toMatch(interval.start); expect(copy).toMatch(interval.end); expect(copy).toMatch(interval.duration);
    expect(copy).toContain('Free to cancel until'); expect(copy).toMatch(/6.*Oct.*2026|Oct.*6.*2026/);
    if (interval.name.includes('midnight')) expect(copy).toMatch(/8.*Oct|Oct.*8/);
    expect(h.post).not.toHaveBeenCalled();
  });
  it.each(invalidIntervals)('refuses preparation for $name', async facts => {
    await mount(); setCurrent({ ...session, ...facts }); await press(action(/^Cancel(?: session)?$/));
    expect(tree.filter(node => node.type === 'Sheet')).toHaveLength(0); expect(h.post).not.toHaveBeenCalled();
  });
  it.each(invalidIntervals)('refuses dispatch when confirmation refresh has $name', async facts => {
    await mount(); await press(action(/^Cancel(?: session)?$/)); setCurrent({ ...session, ...facts }); await press(confirmationAction()); expect(h.post).not.toHaveBeenCalled();
  });
  it.each([
    { startsAt: session.startsAt, endsAt: '2026-10-07T08:00:00Z', duration: /90\s*(?:min|minute)|1\s*(?:hr|hour).*30\s*(?:min|minute)/i, start: /12:00/, end: /1:30|13:30/ },
    { startsAt: '2026-10-07T07:30:00Z', endsAt: '2026-10-07T08:30:00Z', duration: /60\s*(?:min|minute)|1\s*(?:hr|hour)/i, start: /1:00|13:00/, end: /2:00|14:00/ },
  ])('requires a new explicit confirmation for changed interval $endsAt', async facts => {
    await mount(); await press(action(/^Cancel(?: session)?$/)); setCurrent({ ...session, ...facts }); await press(confirmationAction()); expect(h.post).not.toHaveBeenCalled();
    const copy = confirmationText(); expect(copy).toMatch(facts.duration); expect(copy).toMatch(facts.start); expect(copy).toMatch(facts.end);
    await press(confirmationAction()); expect(h.post).toHaveBeenCalledExactlyOnceWith('/api/member/pt-bookings/cancel', { sessionId });
  });
});
