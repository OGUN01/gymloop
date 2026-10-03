// Independently authored from frozen approved PTF declarations; no source or holdouts read.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { businessNouns, ptBookingConsequence, type PtPack } from '@gymloop/shared';
import BookingScreen from '../../app/training/book/[orderId]';

type Props = Record<string, unknown>;
type Node = { type: unknown; props: Props; path?: string };
type Slot = { value?: unknown; deps?: readonly unknown[] | undefined; cleanup?: (() => void) | undefined };
const seam = vi.hoisted(() => ({
  stores: new Map<string, Slot[]>(), path: '', cursor: 0, effects: [] as Array<() => void>,
  loadMember: vi.fn(), slots: vi.fn(), policy: vi.fn(), routeOrder: '' as unknown, uuid: vi.fn(), nextUuid: 0,
  network: true, probe: vi.fn(), networkListener: null as null | ((state: { isConnected: boolean; isInternetReachable: boolean }) => void),
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
vi.mock('../../lib/training', () => ({ loadTraining: seam.loadMember, loadSlots: seam.slots, loadPtPolicy: seam.policy }));
vi.mock('expo-crypto', () => ({ randomUUID: seam.uuid }));
vi.mock('expo-network', () => ({
  getNetworkStateAsync: seam.probe,
  addNetworkStateListener: (callback: typeof seam.networkListener) => { seam.networkListener = callback; return { remove: vi.fn() }; },
}));
vi.mock('expo-router', () => ({ router: { push: vi.fn(), replace: vi.fn() }, useRouter: () => ({ push: vi.fn(), replace: vi.fn() }), useLocalSearchParams: () => ({ orderId: seam.routeOrder }) }));
vi.mock('react-native', () => ({ View: 'View', Text: 'Text', ScrollView: 'ScrollView', Pressable: 'Pressable', TextInput: 'TextInput', ActivityIndicator: 'ActivityIndicator', StyleSheet: { create: (styles: unknown) => styles }, Platform: { OS: 'android' } }));
vi.mock('../../components/ui', () => {
  const host = (name: string) => (props: Props) => ({ type: name, props });
  return {
    Screen: host('Screen'), Title: host('Title'), Eyebrow: host('Eyebrow'),
    LedgerSection: host('LedgerSection'),
    ActionButton: host('ActionButton'), Body: host('Body'), EmptyState: host('EmptyState'), ErrorRetry: host('ErrorRetry'), LoadingState: host('LoadingState'), Row: host('Row'), RowAction: host('RowAction'), SearchField: host('SearchField'),
    Sheet: (props: Props) => props.visible ? { type: 'Sheet', props } : null,
    SheetHeader: host('SheetHeader'), StateMessage: host('StateMessage'), Status: host('Status'),
  };
});
const memberA = { kind: 'member', userId: '74000000-0000-4000-8000-000000000011', tenantId: '74000000-0000-4000-8000-000000000012', memberId: '74000000-0000-4000-8000-000000000013' };
const orderId = '73000000-0000-4000-8000-000000000032';
const pack: PtPack = { orderId, programmeName: 'Saved movement programme', trainerKey: '73000000-0000-4000-8000-000000000033', trainerName: 'Coach Kavya', sessionsTotal: 10, sessionsUsed: 3, sessionsScheduled: 2, sessionsRemaining: 5, startsOn: '2026-10-01', expiresOn: '2026-10-31', state: 'live', canBook: true, timezone: 'Asia/Kolkata' };
const slot = { startsAt: '2026-10-03T06:30:00Z', endsAt: '2026-10-03T07:30:00Z', timezone: 'Asia/Kolkata' };
const training = () => ({ trainers: { data: [], error: null }, programmes: { data: [], error: null }, packs: { data: [pack], error: null }, upcoming: { data: [], error: null }, history: { data: [], error: null } });
const policy = () => ({ data: { cancelWindowHours: 0, lateCancelConsumes: false }, error: null });
const answer = (body: Record<string, unknown>, status = 'booked') => ({ sessionId: body.sessionId, orderId, startsAt: slot.startsAt, endsAt: slot.endsAt, status, inCancelWindow: false, replayed: false });

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
function draw() { nodes = []; visit({ type: BookingScreen, props: {} }, 'root'); seam.effects.splice(0).forEach(effect => effect()); }
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
  return { identity, ready: true, nouns: businessNouns('gym'), palette: {}, session: { user: { id: memberA.userId }, access_token: 'fixture-token' }, api: { post: vi.fn().mockImplementation(async (_path: unknown, body: Record<string, unknown>) => ({ ok: true, data: answer(body) })) }, supabase: {
    from: () => ({ select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: { timezone: 'Asia/Kolkata', branch_id: '73000000-0000-4000-8000-000000000038' }, error: null }) }) }) }),
    auth: { onAuthStateChange: () => ({ data: { subscription: { unsubscribe: vi.fn() } } }) },
  }, webOrigin: 'https://gymloop.test' };
}
beforeEach(() => {
  cleanup(); vi.clearAllMocks(); vi.useFakeTimers(); vi.setSystemTime(new Date('2026-10-03T00:00:00Z'));
  seam.network = true; seam.networkListener = null; seam.context = context(memberA);
  seam.routeOrder = orderId;
  seam.nextUuid = 0;
  seam.uuid.mockReset().mockImplementation(() => '73000000-0000-4000-8000-' + String(++seam.nextUuid).padStart(12, '0'));
  seam.loadMember.mockReset().mockResolvedValue(training()); seam.slots.mockReset().mockResolvedValue({ data: [slot], error: null }); seam.policy.mockReset().mockResolvedValue(policy());
  seam.probe.mockReset().mockResolvedValue({ isConnected: true, isInternetReachable: true });

});
afterEach(() => { cleanup(); vi.useRealTimers(); });


const confirmation = /^Confirm(?: booking)?$|^Book(?: session)?$/;
const slotControl = /12:00/;
function post() { return (seam.context.api as { post: ReturnType<typeof vi.fn> }).post; }
async function tryConfirm() { const node = control(confirmation); if (node && node.props.disabled !== true && typeof node.props.onPress === 'function') { await node.props.onPress(); await settle(); } }
describe('PTF actual native booking route', () => {
  it('loads the own caller and fourteen gym-local dates without a booking command', async () => {
    draw(); await settle();
    expect(seam.loadMember.mock.calls[0]?.[0]).toBe(seam.context.supabase);
    expect(seam.slots).toHaveBeenCalledWith(seam.context.supabase, orderId, '2026-10-03', '2026-10-16');
    expect(seam.policy).toHaveBeenCalledWith(seam.context.supabase);
    expect(post()).not.toHaveBeenCalled();
  });

  it.each(['invalid route', 'foreign order', 'wrong audience'] as const)('does not present a booking for %s', async failure => {
    if (failure === 'invalid route') seam.routeOrder = 'invalid';
    if (failure === 'foreign order') seam.routeOrder = '73000000-0000-4000-8000-000000000099';
    if (failure === 'wrong audience') seam.context = context({ kind: 'unlinked' });
    draw(); await settle(); await tryConfirm();
    expect(post()).not.toHaveBeenCalled(); expect(control(slotControl)).toBeUndefined();
    if (failure !== 'foreign order') expect(seam.slots).not.toHaveBeenCalled();
  });

  it.each([[0, false], [0, true], [168, false], [168, true]] as const)('shows current consequence for %s hours / consumes %s before exact commit', async (hours, consumes) => {
    seam.policy.mockResolvedValue({ data: { cancelWindowHours: hours, lateCancelConsumes: consumes }, error: null });
    draw(); await settle(); const reads = seam.policy.mock.calls.length;
    await press(slotControl);
    expect(seam.policy.mock.calls.length).toBeGreaterThan(reads);
    expect(visible()).toContain(pack.programmeName); expect(visible()).toContain(pack.trainerName);
    expect(visible()).toMatch(/12:00/); expect(visible()).toMatch(/1:00|13:00/); expect(visible()).toContain(slot.timezone);
    expect(visible()).toContain(ptBookingConsequence({ startsAt: slot.startsAt, now: new Date().toISOString(), windowHours: hours, lateConsumes: consumes, timezone: slot.timezone }));
    expect(post()).not.toHaveBeenCalled();
    await press(confirmation); expect(seam.policy.mock.calls.length).toBeGreaterThan(reads + 1);
    expect(post()).toHaveBeenCalledTimes(1);
    expect(post()).toHaveBeenCalledWith('/api/member/pt-bookings', { orderId, startsAt: slot.startsAt, sessionId: expect.stringMatching(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i) });
  });

  it('refreshes policy on reopening the selection and uses current consequence', async () => {
    draw(); await settle(); await press(slotControl); const reads = seam.policy.mock.calls.length;
    const sheet = nodes.find(node => node.type === 'Sheet'); expect(sheet?.props.onClose).toBeTypeOf('function');
    if (typeof sheet?.props.onClose === 'function') sheet.props.onClose(); await settle();
    seam.policy.mockResolvedValue({ data: { cancelWindowHours: 168, lateCancelConsumes: true }, error: null });
    await press(slotControl);
    expect(seam.policy.mock.calls.length).toBeGreaterThan(reads);
    expect(visible()).toContain("Cancelling will use 1 session from your pack.");
    expect(post()).not.toHaveBeenCalled();
  });

  it.each(['missing policy', 'policy error', 'closed pack', 'missing slot', 'failed slots'] as const)('fails closed for %s at confirmation', async failure => {
    draw(); await settle(); await press(slotControl);
    if (failure === 'missing policy') seam.policy.mockResolvedValue({ data: null, error: null });
    if (failure === 'policy error') seam.policy.mockResolvedValue({ data: null, error: 'Please try again.' });
    if (failure === 'closed pack') seam.loadMember.mockResolvedValue({ ...training(), packs: { data: [{ ...pack, canBook: false, state: 'closed' }], error: null } });
    if (failure === 'missing slot') seam.slots.mockResolvedValue({ data: [], error: null });
    if (failure === 'failed slots') seam.slots.mockResolvedValue({ data: null, error: 'Please try again.' });
    await press(confirmation); expect(post()).not.toHaveBeenCalled();
  });

  it('keeps loading policy uncommitted and discards it when the caller is revoked', async () => {
    draw(); await settle(); const waiting = deferred<ReturnType<typeof policy>>(); seam.policy.mockReturnValueOnce(waiting.promise);
    const select = control(slotControl); expect(select).toBeDefined();
    const pending = typeof select?.props.onPress === 'function' ? select.props.onPress() : undefined;
    await settle(); await tryConfirm(); expect(post()).not.toHaveBeenCalled();
    seam.context = { ...seam.context, ready: false, session: null }; draw(); await settle();
    waiting.resolve(policy()); await pending; await settle(); await tryConfirm();
    expect(post()).not.toHaveBeenCalled();
  });
  it('stops later reads when the caller changes during an awaited pack refresh', async () => {
    draw(); await settle(); const waiting = deferred<ReturnType<typeof training>>();
    seam.loadMember.mockReturnValueOnce(waiting.promise);
    const select = control(slotControl); expect(select).toBeDefined();
    const pending = typeof select?.props.onPress === 'function' ? select.props.onPress() : undefined;
    await settle();
    seam.context = { ...seam.context, ready: false, session: null }; draw(); await settle();
    const slotReads = seam.slots.mock.calls.length; const policyReads = seam.policy.mock.calls.length;
    waiting.resolve(training()); await pending; await settle();
    expect(seam.slots.mock.calls.length).toBe(slotReads);
    expect(seam.policy.mock.calls.length).toBe(policyReads);
    expect(post()).not.toHaveBeenCalled();
  });

  it('requires explicit reconfirmation after a current policy change before a new command', async () => {
    draw(); await settle(); await press(slotControl);
    seam.policy.mockResolvedValue({ data: { cancelWindowHours: 168, lateCancelConsumes: true }, error: null });
    await press(confirmation); expect(post()).not.toHaveBeenCalled();
    expect(visible()).toContain("Cancelling will use 1 session from your pack.");
    await press(confirmation); expect(post()).toHaveBeenCalledTimes(1);
  });

  it('groups and displays the server-returned slot using that slot timezone', async () => {
    seam.slots.mockResolvedValue({ data: [{ ...slot, timezone: 'UTC' }], error: null });
    draw(); await settle(); await press(/6:30|06:30/);
    expect(visible()).toContain('UTC'); expect(visible()).toMatch(/7:30|07:30/);
    expect(post()).not.toHaveBeenCalled();
  });

  it('retries unknown submission only explicitly with the exact original body despite closed pack and absent slot', async () => {
    post().mockRejectedValueOnce(new Error('Private unknown transport outcome'));
    draw(); await settle(); await press(slotControl); await press(confirmation);
    expect(post()).toHaveBeenCalledTimes(1);
    const body = post().mock.calls[0]?.[1] as Record<string, unknown>;
    expect(visible()).not.toMatch(/Session booked|Successfully booked/);
    await settle(); expect(post()).toHaveBeenCalledTimes(1);
    seam.loadMember.mockResolvedValue({ ...training(), packs: { data: [{ ...pack, canBook: false, state: 'closed' }], error: null } });
    seam.slots.mockResolvedValue({ data: [], error: null });
    post().mockResolvedValueOnce({ ok: true, data: { ...answer(body, 'attended'), replayed: true } });
    await press(/^Retry(?: booking)?$|^Try again$/);
    expect(post()).toHaveBeenCalledTimes(2); expect(post().mock.calls[1]?.[1]).toEqual(body);
    expect(visible()).toContain('Attended'); expect(visible()).not.toMatch(/Session booked|Successfully booked/);
  });

  it('cannot transfer a prior unknown command to a reopened sheet', async () => {
    post().mockRejectedValueOnce(new Error('Unknown outcome'));
    draw(); await settle(); await press(slotControl); await press(confirmation);
    const original = post().mock.calls[0]?.[1] as Record<string, unknown>;
    const sheet = nodes.find(node => node.type === 'Sheet'); expect(sheet?.props.onClose).toBeTypeOf('function');
    if (typeof sheet?.props.onClose === 'function') sheet.props.onClose(); await settle(); await press(slotControl);
    expect(post()).toHaveBeenCalledTimes(1);
    await press(confirmation); expect(post()).toHaveBeenCalledTimes(2);
    const next = post().mock.calls[1]?.[1] as Record<string, unknown>;
    expect(next.sessionId).not.toBe(original.sessionId);
    expect(next).toEqual({ orderId, startsAt: slot.startsAt, sessionId: expect.any(String) });
  });

  it.each(['malformed', 'wrong session', 'wrong order'] as const)('does not announce booking for %s reply', async failure => {
    post().mockImplementationOnce(async (_path: unknown, body: Record<string, unknown>) => ({ ok: true,
      data: failure === 'malformed' ? {} : { ...answer(body), ...(failure === 'wrong session' ? { sessionId: '73000000-0000-4000-8000-000000000099' } : { orderId: '73000000-0000-4000-8000-000000000099' }) },
    }));
    draw(); await settle(); await press(slotControl); await press(confirmation);
    expect(post()).toHaveBeenCalledTimes(1); expect(visible()).not.toMatch(/Session booked|Successfully booked/);
  });

  it.each(['unmount', 'API client changed', 'caller away and back', 'offline'] as const)('revokes retained confirmation after %s without queueing', async transition => {
    draw(); await settle(); await press(slotControl);
    const retained = control(confirmation)?.props.onPress; expect(retained).toBeTypeOf('function');
    const originalPost = post();
    if (transition === 'unmount') cleanup();
    if (transition === 'API client changed') { seam.context = { ...seam.context, api: { post: vi.fn() } }; draw(); await settle(); }
    if (transition === 'caller away and back') { seam.context = context({ kind: 'unlinked' }); draw(); await settle(); seam.context = context(memberA); draw(); await settle(); }
    if (transition === 'offline') { seam.network = false; seam.probe.mockResolvedValue({ isConnected: false, isInternetReachable: false }); seam.networkListener?.({ isConnected: false, isInternetReachable: false }); await settle(); }
    if (typeof retained === 'function') await retained(); await settle();
    expect(originalPost).not.toHaveBeenCalled(); expect(post()).not.toHaveBeenCalled();
    if (transition === 'offline') { seam.network = true; seam.probe.mockResolvedValue({ isConnected: true, isInternetReachable: true }); seam.networkListener?.({ isConnected: true, isInternetReachable: true }); await settle(); expect(post()).not.toHaveBeenCalled(); }
  });
});
