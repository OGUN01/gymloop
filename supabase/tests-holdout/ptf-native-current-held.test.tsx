import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { ReactElement, ReactNode } from '../../apps/mobile/node_modules/@types/react/index';
import { businessNouns, UI_TOKENS } from '@gymloop/shared';
import type { MemberTraining, PtSession, PtPack } from '@gymloop/shared';

// Fresh native author. Actual TrainingSection; only provider, read, network and kit boundaries are doubled.
const seam = vi.hoisted(() => ({ value: {} as Record<string, unknown>, load: vi.fn(), post: vi.fn(), push: vi.fn(),
  network: vi.fn(), listener: undefined as ((state: { isConnected: boolean; isInternetReachable: boolean }) => void) | undefined,
  cells: [] as unknown[], index: 0, effects: [] as (() => void)[], cleanups: [] as (() => void)[] }));
vi.mock('../../apps/mobile/lib/mobile-context', () => ({ useMobile: () => seam.value }));
vi.mock('../../apps/mobile/lib/training', () => ({ loadTraining: seam.load, loadTrainingHistory: vi.fn() }));
vi.mock('expo-router', () => ({ useRouter: () => ({ push: seam.push }), router: { push: seam.push } }));
vi.mock('expo-network', () => ({ getNetworkStateAsync: seam.network,
  addNetworkStateListener: (listener: typeof seam.listener) => { seam.listener = listener; return { remove: () => { seam.listener = undefined; } }; } }));
vi.mock('react', async original => {
  const real = await original<typeof import('../../apps/mobile/node_modules/@types/react/index')>();
  return { ...real,
    useState: (initial: unknown) => { const i = seam.index++; if (!(i in seam.cells)) seam.cells[i] = typeof initial === 'function' ? (initial as () => unknown)() : initial;
      return [seam.cells[i], (next: unknown) => { seam.cells[i] = typeof next === 'function' ? (next as (old: unknown) => unknown)(seam.cells[i]) : next; }]; },
    useRef: (initial: unknown) => { const i = seam.index++; if (!(i in seam.cells)) seam.cells[i] = { current: initial }; return seam.cells[i]; },
    useEffect: (effect: () => void | (() => void), deps?: unknown[]) => {
      const i = seam.index++; const old = seam.cells[i] as { deps?: unknown[]; cleanup?: () => void } | undefined;
      if (!old || !deps || deps.some((v, j) => v !== old.deps?.[j])) {
        const slot: { deps?: unknown[]; cleanup?: () => void } = deps ? { deps } : {}; seam.cells[i] = slot;
        seam.effects.push(() => { old?.cleanup?.(); const cleanup = effect(); if (cleanup) { slot.cleanup = cleanup; seam.cleanups.push(cleanup); } });
      }
    }, useMemo: (fn: () => unknown) => fn(), useCallback: (fn: unknown) => fn,
  };
});
vi.mock('react-native', () => ({ View: 'View', Text: 'Text', Pressable: 'Pressable', Image: 'Image', ScrollView: 'ScrollView',
  StyleSheet: { create: (value: unknown) => value, hairlineWidth: 1 }, Platform: { OS: 'android', select: (value: { android: unknown }) => value.android },
  useWindowDimensions: () => ({ width: 390, height: 844, fontScale: 1 }), ActivityIndicator: 'ActivityIndicator' }));
vi.mock('../../apps/mobile/components/ui', () => ({ Status: 'Status', ActionButton: 'ActionButton', Row: 'Row', Sheet: 'Sheet',
  SheetHeader: 'SheetHeader', EmptyState: 'EmptyState', ErrorRetry: 'ErrorRetry', LoadingState: 'LoadingState',
  LedgerSection: 'LedgerSection', StateMessage: 'StateMessage', Body: 'Body' }));

type Element = ReactElement<Record<string, unknown>>;
function nodes(node: ReactNode): Element[] {
  if (Array.isArray(node)) return node.flatMap(nodes);
  if (!node || typeof node !== 'object' || !('props' in node)) return [];
  const e = node as Element;
  if (e.type === 'Sheet' && !e.props.visible) return [];
  return [e, ...['children', 'title', 'meta', 'status', 'trailing'].flatMap(key => nodes(e.props[key] as ReactNode))];
}
function text(node: ReactNode): string {
  if (Array.isArray(node)) return node.map(text).join(' ');
  if (typeof node === 'string' || typeof node === 'number') return String(node);
  if (!node || typeof node !== 'object' || !('props' in node)) return '';
  const e = node as Element; if (e.type === 'Sheet' && !e.props.visible) return '';
  return ['children', 'title', 'meta', 'status', 'trailing', 'message', 'detail', 'value'].map(key => text(e.props[key] as ReactNode)).join(' ');
}
function action(tree: ReactNode, name: RegExp): Element {
  const found = nodes(tree).find(e => typeof e.props.onPress === 'function' && name.test(text(e) + String(e.props.accessibilityLabel ?? '')));
  expect(found, `actual native action ${name}`).toBeDefined(); return found!;
}
async function press(tree: ReactNode, name: RegExp) {
  const e = action(tree, name); expect(e.props.disabled).not.toBe(true); await (e.props.onPress as () => unknown)(); await flush();
}
async function flush() { for (let i = 0; i < 8; i++) await Promise.resolve(); }
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(done => { resolve = done; }); return { promise, resolve }; }
const row: PtSession = { sessionId: 'a7077c51-c831-46dd-a6ec-887209dd96f1', orderId: 'b7077c51-c831-46dd-a6ec-887209dd96f2',
  trainerKey: 'c7077c51-c831-46dd-a6ec-887209dd96f3', programmeName: 'Held native coaching', trainerName: 'Mira',
  startsAt: '2026-10-05T05:30:00Z', endsAt: '2026-10-05T06:30:00Z', timezone: 'Asia/Kolkata', status: 'booked',
  consumed: false, cancelledAt: null, canCancel: true, cancelCutoff: '2026-10-04T05:30:00Z', lateNow: false, consumesNow: false };
function data(session: PtSession | null = row): MemberTraining {
  return { upcoming: { data: session ? [session] : [], error: null }, history: { data: [], error: null },
    packs: { data: [], error: null }, programmes: { data: [], error: null }, trainers: { data: [], error: null } };
}
const identity = { kind: 'member', userId: 'd7077c51-c831-46dd-a6ec-887209dd96f4', tenantId: 'e7077c51-c831-46dd-a6ec-887209dd96f5', memberId: 'f7077c51-c831-46dd-a6ec-887209dd96f6' };
const client = { marker: 'original read client' };
beforeEach(() => {
  vi.clearAllMocks(); seam.cells = []; seam.effects = []; seam.cleanups = []; seam.index = 0; seam.listener = undefined;
  seam.value = { identity, supabase: client, api: { post: seam.post }, ready: true, nouns: businessNouns('gym'),
    palette: UI_TOKENS.colors.light, businessType: 'gym', session: null, appearance: 'light' };
  seam.load.mockResolvedValue(data()); seam.network.mockResolvedValue({ isConnected: true, isInternetReachable: true });
  seam.post.mockResolvedValue({ ok: true, data: { sessionId: row.sessionId, status: 'cancelled_by_member', late: false, consumed: false, sessionsRemaining: 4, replayed: false } });
});
afterEach(() => { seam.cleanups.splice(0).forEach(cleanup => cleanup()); vi.useRealTimers(); });
async function mount() {
  const { TrainingSection } = await import('../../apps/mobile/components/training-section');
  const render = () => { seam.index = 0; const tree = TrainingSection(); seam.effects.splice(0).forEach(effect => effect()); return tree; };
  render(); await flush(); return { render, unmount: () => seam.cleanups.splice(0).forEach(cleanup => cleanup()) };
}

describe('independent actual native Training current cancellation', () => {
  it.each([
    ['2026-10-05T05:29:59.999Z', true],
    ['2026-10-05T05:30:00.000Z', false],
    ['2026-10-05T05:30:00.001Z', false],
  ] as const)('paused confirming read at %s permits command=%s using stable authoritative late facts', async (resumeAt, allowed) => {
    vi.useFakeTimers(); vi.setSystemTime(new Date('2026-10-05T05:29:58Z'));
    const current = { ...row, lateNow: true, consumesNow: true };
    seam.load.mockResolvedValue(data(current));
    const screen = await mount(); await press(screen.render(), /^Cancel/i);
    expect(text(screen.render())).toContain('This is inside your cancellation window. Cancelling will use 1 session from your pack.');
    const confirming = deferred<MemberTraining>(); seam.load.mockReturnValueOnce(confirming.promise);
    const before = seam.load.mock.calls.length;
    const pending = (action(screen.render(), /Confirm|Cancel session/i).props.onPress as () => Promise<void>)(); await flush();
    expect(seam.load.mock.calls.length).toBeGreaterThan(before); expect(seam.post).not.toHaveBeenCalled();
    vi.setSystemTime(new Date(resumeAt)); confirming.resolve(data(current)); await pending; await flush();
    if (allowed) expect(seam.post).toHaveBeenCalledWith('/api/member/pt-bookings/cancel', { sessionId: row.sessionId });
    else {
      expect(seam.post).not.toHaveBeenCalled();
      expect(text(screen.render())).toContain("This session has already started, so it can't be cancelled here. Ask your trainer or the front desk.");
    }
  });
  it.each([null, { ...row, sessionId: '07077c51-c831-46dd-a6ec-887209dd96f7' }, { ...row, canCancel: false },
    { ...row, cancelCutoff: null }, { ...row, status: 'attended' as const }])('fresh confirming session invalidation %# sends nothing', async current => {
    const screen = await mount(); await press(screen.render(), /^Cancel/i); seam.load.mockResolvedValue(data(current));
    await press(screen.render(), /Confirm|Cancel session/i); expect(seam.post).not.toHaveBeenCalled();
    expect(text(screen.render())).not.toMatch(/successfully|session cancelled/i);
  });
  it('fresh confirming section refusal cannot fall back to retained session', async () => {
    const screen = await mount(); await press(screen.render(), /^Cancel/i);
    seam.load.mockResolvedValue({ ...data(), upcoming: { data: null, error: 'Please try again.' } });
    await press(screen.render(), /Confirm|Cancel session/i); expect(seam.post).not.toHaveBeenCalled();
  });
  it('thrown fresh confirming read is sanitized and cannot submit retained facts', async () => {
    const screen = await mount(); await press(screen.render(), /^Cancel/i);
    seam.load.mockRejectedValue(new Error('PRIVATE read failure'));
    await press(screen.render(), /Confirm|Cancel session/i); expect(seam.post).not.toHaveBeenCalled();
    expect(text(screen.render())).not.toContain('PRIVATE read failure');
  });
  it('fresh confirming changed consequence requires another explicit confirmation', async () => {
    const screen = await mount(); await press(screen.render(), /^Cancel/i);
    seam.load.mockResolvedValue(data({ ...row, lateNow: true, consumesNow: true }));
    await press(screen.render(), /Confirm|Cancel session/i); expect(seam.post).not.toHaveBeenCalled();
    expect(text(screen.render())).toContain('This is inside your cancellation window. Cancelling will use 1 session from your pack.');
    await press(screen.render(), /Confirm|Cancel session/i); expect(seam.post).toHaveBeenCalledWith('/api/member/pt-bookings/cancel', { sessionId: row.sessionId });
  });
  it.each([true, false])('late consumption=%s still displays absolute gym-local cutoff', async consumesNow => {
    seam.load.mockResolvedValue(data({ ...row, lateNow: true, consumesNow }));
    const screen = await mount(); await press(screen.render(), /^Cancel/i); const visible = text(screen.render());
    expect(visible).toContain(consumesNow ? 'Cancelling will use 1 session from your pack.' : "Cancelling won't use a session from your pack.");
    expect(visible).toMatch(/4 Oct|Oct 4|04 Oct|4 October/); expect(visible).toMatch(/11:00|11\.00/);
  });
  it('network wait crossing free cutoff requires renewed review before any send', async () => {
    vi.useFakeTimers(); vi.setSystemTime(new Date('2026-10-04T05:29:59Z'));
    const screen = await mount(); await press(screen.render(), /^Cancel/i);
    const waited = deferred<{ isConnected: boolean; isInternetReachable: boolean }>(); seam.network.mockReturnValue(waited.promise);
    const pending = (action(screen.render(), /Confirm|Cancel session/i).props.onPress as () => Promise<void>)(); await flush();
    vi.setSystemTime(new Date('2026-10-04T05:30:01Z')); waited.resolve({ isConnected: true, isInternetReachable: true }); await pending; await flush();
    expect(seam.post).not.toHaveBeenCalled();
  });
  it('confirm rereads using current exact supplied caller client', async () => {
    vi.useFakeTimers(); vi.setSystemTime(new Date('2026-10-04T05:00:00Z'));
    const screen = await mount(); await press(screen.render(), /^Cancel/i); const before = seam.load.mock.calls.length;
    await press(screen.render(), /Confirm|Cancel session/i); expect(seam.load.mock.calls.length).toBeGreaterThan(before);
    expect(seam.load.mock.calls.at(-1)?.[0]).toBe(client); expect(seam.post).toHaveBeenCalledOnce();
  });
  it('API refusal keeps pinned sentence without fake success', async () => {
    vi.useFakeTimers(); vi.setSystemTime(new Date('2026-10-04T05:00:00Z'));
    seam.post.mockResolvedValue({ ok: false, error: { code: 'too_late_to_cancel', message: 'PRIVATE server transport' } });
    const screen = await mount(); await press(screen.render(), /^Cancel/i); await press(screen.render(), /Confirm|Cancel session/i);
    expect(text(screen.render())).toContain("This session has already started, so it can't be cancelled here. Ask your trainer or the front desk.");
    expect(text(screen.render())).not.toContain('PRIVATE server transport'); expect(text(screen.render())).not.toMatch(/successfully|session cancelled/i);
  });
});

describe('independent native permanent supplied-capability lease', () => {
  it.each(['api', 'supabase', 'ready'] as const)('same verified identity %s replacement revokes retained confirm permanently', async capability => {
    const screen = await mount(); await press(screen.render(), /^Cancel/i);
    const old = action(screen.render(), /Confirm|Cancel session/i).props.onPress as () => Promise<void>;
    const original = seam.value[capability]; const replacementPost = vi.fn();
    seam.value = { ...seam.value, [capability]: capability === 'ready' ? false : capability === 'api' ? { post: replacementPost } : { marker: 'new read client' } };
    screen.render(); await flush(); seam.value = { ...seam.value, [capability]: original }; screen.render(); await flush();
    seam.load.mockClear(); await old(); await flush(); expect(seam.post).not.toHaveBeenCalled();
    expect(replacementPost).not.toHaveBeenCalled(); expect(seam.load).not.toHaveBeenCalled(); expect(seam.push).not.toHaveBeenCalled();
  });
  it('caller A B A cannot revive old retained confirm', async () => {
    const screen = await mount(); await press(screen.render(), /^Cancel/i); const old = action(screen.render(), /Confirm|Cancel session/i).props.onPress as () => Promise<void>;
    seam.value = { ...seam.value, identity: { ...identity, memberId: '17077c51-c831-46dd-a6ec-887209dd96f8' } }; screen.render(); await flush();
    seam.value = { ...seam.value, identity }; screen.render(); await flush(); seam.load.mockClear(); await old();
    expect(seam.post).not.toHaveBeenCalled(); expect(seam.load).not.toHaveBeenCalled();
  });
  it('unmount invalidates late command feedback and prevents post-command reads', async () => {
    vi.useFakeTimers(); vi.setSystemTime(new Date('2026-10-04T05:00:00Z'));
    const result = deferred<unknown>(); seam.post.mockReturnValue(result.promise);
    const screen = await mount(); await press(screen.render(), /^Cancel/i);
    const pending = (action(screen.render(), /Confirm|Cancel session/i).props.onPress as () => Promise<void>)(); await flush();
    expect(seam.post).toHaveBeenCalledOnce(); screen.unmount(); seam.load.mockClear();
    result.resolve({ ok: true, data: { sessionId: row.sessionId, status: 'cancelled_by_member', late: false, consumed: false, sessionsRemaining: 4, replayed: false } });
    await pending; await flush(); expect(seam.load).not.toHaveBeenCalled(); expect(seam.push).not.toHaveBeenCalled();
    expect(text(screen.render())).not.toMatch(/successfully|session cancelled/i);
  });
  it('same-identity API replacement discards awaited old confirming read before send', async () => {
    const screen = await mount(); await press(screen.render(), /^Cancel/i); const facts = deferred<MemberTraining>(); seam.load.mockReturnValue(facts.promise);
    const pending = (action(screen.render(), /Confirm|Cancel session/i).props.onPress as () => Promise<void>)(); await flush();
    const replacement = vi.fn(); seam.value = { ...seam.value, api: { post: replacement } }; screen.render();
    facts.resolve(data()); await pending; await flush(); expect(seam.post).not.toHaveBeenCalled(); expect(replacement).not.toHaveBeenCalled();
  });
  it('API A B A cannot publish old accepted command feedback or post-command reads', async () => {
    vi.useFakeTimers(); vi.setSystemTime(new Date('2026-10-04T05:00:00Z'));
    const result = deferred<unknown>(); seam.post.mockReturnValue(result.promise);
    const screen = await mount(); await press(screen.render(), /^Cancel/i);
    const pending = (action(screen.render(), /Confirm|Cancel session/i).props.onPress as () => Promise<void>)(); await flush();
    expect(seam.post).toHaveBeenCalledOnce(); const originalApi = seam.value.api;
    seam.value = { ...seam.value, api: { post: vi.fn() } }; screen.render(); await flush();
    seam.value = { ...seam.value, api: originalApi }; screen.render(); await flush(); seam.load.mockClear();
    result.resolve({ ok: true, data: { sessionId: row.sessionId, status: 'cancelled_by_member', late: false, consumed: false, sessionsRemaining: 4, replayed: false } });
    await pending; await flush(); expect(seam.load).not.toHaveBeenCalled(); expect(seam.push).not.toHaveBeenCalled();
    expect(text(screen.render())).not.toMatch(/successfully|session cancelled/i);
  });
});

describe('independent native training navigation and offline facts', () => {
  it('positive listener offline immediately shows stale and pinned retry before any disabled action press', async () => {
    const screen = await mount(); expect(seam.listener).toBeTypeOf('function');
    seam.listener!({ isConnected: false, isInternetReachable: false }); const visible = text(screen.render());
    expect(visible).toContain("You're offline. Showing what was last loaded."); expect(visible).toMatch(/stale/i);
    expect(visible).toContain('Please try again.'); expect(seam.post).not.toHaveBeenCalled();
    seam.listener!({ isConnected: true, isInternetReachable: true }); screen.render(); await flush();
    expect(seam.post).not.toHaveBeenCalled(); expect(seam.push).not.toHaveBeenCalled();
  });
  function pack(state: PtPack['state'], canBook: boolean): PtPack { return { orderId: row.orderId, programmeName: 'Owned training pack', trainerKey: row.trainerKey,
    trainerName: 'Mira', sessionsTotal: 8, sessionsUsed: 1, sessionsScheduled: 1, sessionsRemaining: 6, startsOn: '2026-10-01', expiresOn: '2026-11-30', state, canBook, timezone: row.timezone }; }
  it('live eligible pack has actual Book action to frozen proposed route only', async () => {
    seam.load.mockResolvedValue({ ...data(), packs: { data: [pack('live', true)], error: null } });
    const screen = await mount(); await press(screen.render(), /Book a session/i);
    expect(seam.push).toHaveBeenCalledOnce(); const target = seam.push.mock.calls[0]?.[0];
    if (typeof target === 'string') expect(target).toBe(`/training/book/${row.orderId}`);
    else expect(target).toEqual({ pathname: '/training/book/[orderId]', params: { orderId: row.orderId } });
    expect(seam.post).not.toHaveBeenCalled();
  });
  it.each(['fully_booked', 'spent', 'expired', 'closed'] as const)('unavailable pack %s has no enabled booking action', async state => {
    seam.load.mockResolvedValue({ ...data(), packs: { data: [pack(state, false)], error: null } });
    const screen = await mount(); expect(nodes(screen.render()).filter(e => /Book a session/i.test(text(e)) && typeof e.props.onPress === 'function').every(e => e.props.disabled === true)).toBe(true);
    expect(seam.push).not.toHaveBeenCalled();
  });
  it('retained booking navigation revoked after same-identity read capability replacement', async () => {
    seam.load.mockResolvedValue({ ...data(), packs: { data: [pack('live', true)], error: null } });
    const screen = await mount(); const old = action(screen.render(), /Book a session/i).props.onPress as () => unknown;
    seam.value = { ...seam.value, supabase: { marker: 'replaced read capability' } }; screen.render(); await flush(); await old();
    expect(seam.push).not.toHaveBeenCalled(); expect(seam.post).not.toHaveBeenCalled();
  });
  it('offline has explicit stale facts and reconnect sends no cancellation', async () => {
    const screen = await mount(); seam.listener?.({ isConnected: false, isInternetReachable: false }); const tree = screen.render();
    expect(text(tree)).toContain("You're offline. Showing what was last loaded."); expect(text(tree)).toMatch(/stale/i);
    seam.network.mockResolvedValue({ isConnected: false, isInternetReachable: false });
    const cancel = nodes(tree).find(e => /^Cancel/i.test(text(e).trim()) && typeof e.props.onPress === 'function');
    if (cancel && !cancel.props.disabled) await (cancel.props.onPress as () => unknown)();
    seam.listener?.({ isConnected: true, isInternetReachable: true }); screen.render(); await flush(); expect(seam.post).not.toHaveBeenCalled();
  });
});
