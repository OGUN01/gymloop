import type React from 'react';
import type { ReactNode } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { UI_TOKENS, businessNouns, type GymloopIdentity } from '@gymloop/shared';
import type { MemberTraining as PublicTraining, PtSession as PublicSession } from '@gymloop/shared';
// Nullable read failures and cancellation provenance are frozen packet facts.
type PtSession = Omit<PublicSession, 'cancelledAt' | 'cancelCutoff'> & { cancelledAt: string | null; cancelCutoff: string | null };
type MemberTraining = { [K in keyof PublicTraining]: { data: K extends 'upcoming' | 'history' ? PtSession[] | null : PublicTraining[K]['data'] | null; error: string | null } };

// A deterministic hook runner preserves state, effect lifetime and callbacks;
// it provides no evidence about real native geometry, dots or accessibility.
type Props = Record<string, unknown> & { children?: ReactNode };
const mocks = vi.hoisted(() => ({ context: {} as Record<string, unknown>, load: vi.fn(), post: vi.fn(), listeners: new Set<(state: { isConnected: boolean; isInternetReachable: boolean }) => void>(), online: true }));
const hooks = vi.hoisted(() => ({ slots: [] as unknown[], cursor: 0, effects: [] as Array<() => void>, cleanups: [] as Array<(() => void) | undefined>, dirty: false }));
function equal(a: unknown[] | undefined, b: unknown[] | undefined) { return a !== undefined && b !== undefined && a.length === b.length && a.every((value, index) => Object.is(value, b[index])); }
vi.mock('react', () => {
  const memo = (factory: () => unknown, deps?: unknown[]) => { const index = hooks.cursor++; const old = hooks.slots[index] as { value: unknown; deps?: unknown[] } | undefined; if (!old || !equal(old.deps, deps)) hooks.slots[index] = { value: factory(), deps }; return (hooks.slots[index] as { value: unknown }).value; };
  return { default: {}, useState: (initial: unknown) => { const index = hooks.cursor++; if (!(index in hooks.slots)) hooks.slots[index] = typeof initial === 'function' ? initial() : initial; return [hooks.slots[index], (next: unknown) => { hooks.slots[index] = typeof next === 'function' ? next(hooks.slots[index]) : next; hooks.dirty = true; }]; }, useRef: (value: unknown) => memo(() => ({ current: value }), []), useMemo: memo, useCallback: (fn: unknown, deps: unknown[]) => memo(() => fn, deps), useEffect: (fn: () => (() => void) | undefined, deps?: unknown[]) => { const index = hooks.cursor++; const old = hooks.slots[index] as unknown[] | undefined; if (!equal(old, deps)) { hooks.slots[index] = deps; hooks.effects.push(() => { hooks.cleanups[index]?.(); hooks.cleanups[index] = fn(); }); } } };
});
type HostNode = { type: unknown; props: Props; textContent: string; children: HostNode[] };
function host(name: string) { return function Host(props: Props) { return { type: name, props }; }; }
vi.mock('../../apps/mobile/lib/mobile-context', () => ({ useMobile: () => mocks.context }));
vi.mock('../../apps/mobile/lib/training', () => ({ loadTraining: mocks.load, loadTrainingHistory: vi.fn(async () => ({ data: [], error: null })) }));
vi.mock('../../apps/mobile/components/ui', () => Object.fromEntries(['Status', 'ActionButton', 'Row', 'Sheet', 'SheetHeader', 'EmptyState', 'ErrorRetry', 'LoadingState', 'StateMessage', 'Section', 'Card', 'Heading', 'Body'].map(name => [name, host(name)])));
vi.mock('react-native', () => ({ View: host('View'), Text: host('Text'), Pressable: host('Pressable'), ScrollView: host('ScrollView'), Image: host('Image'), ActivityIndicator: host('ActivityIndicator'), StyleSheet: { create: (styles: unknown) => styles }, Platform: { OS: 'android' }, useWindowDimensions: () => ({ width: 390, height: 844, fontScale: 1 }) }));
vi.mock('expo-network', () => ({ getNetworkStateAsync: async () => ({ isConnected: mocks.online, isInternetReachable: mocks.online }), addNetworkStateListener: (fn: (state: { isConnected: boolean; isInternetReachable: boolean }) => void) => { mocks.listeners.add(fn); return { remove: () => mocks.listeners.delete(fn) }; } }));
vi.mock('expo-router', () => ({ router: { push: vi.fn(), replace: vi.fn() }, useRouter: () => ({ push: vi.fn(), replace: vi.fn() }), Link: host('Link') }));
const id = (n: number) => `73900000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const member = (n = 1): GymloopIdentity => ({ kind: 'member', userId: id(n), tenantId: id(8), memberId: id(n + 20) });
const session = (changes: Partial<PtSession> = {}): PtSession => ({ sessionId: id(50), orderId: id(40), programmeName: 'Strength plan', trainerKey: id(30), trainerName: 'Mira', startsAt: '2026-10-05T10:00:00+05:30', endsAt: '2026-10-05T11:00:00+05:30', timezone: 'Asia/Kolkata', status: 'booked', consumed: false, cancelledAt: null, cancelCutoff: '2026-10-04T10:00:00+05:30', lateNow: false, consumesNow: false, canCancel: true, ...changes });
const data = (): MemberTraining => ({
  trainers: { data: [{ trainerKey: id(30), displayName: 'Mira', qualification: 'Certified coach', bio: 'Strength and mobility coach', specialities: ['Strength'], imageUrl: null, branchName: 'North branch', isProfileListed: true }], error: null },
  programmes: { data: [{ programmeId: id(35), trainerKey: id(30), trainerName: 'Mira', trainerQualification: 'Certified coach', name: 'Desk programme', description: 'Progressive strength coaching', pricePaise: '1234567', currency: 'INR', gstRateBp: 1800, sessionCount: 10, validityDays: 90, cancellationTerms: 'Desk terms remain binding' }], error: null },
  packs: { data: [{ orderId: id(40), programmeName: 'Strength plan', trainerKey: id(30), trainerName: 'Mira', sessionsTotal: 10, sessionsUsed: 3, sessionsScheduled: 2, sessionsRemaining: 5, startsOn: '2026-09-01', expiresOn: '2026-12-01', state: 'live', canBook: true, timezone: 'Asia/Kolkata' }, { orderId: id(41), programmeName: 'Expired plan', trainerKey: id(30), trainerName: 'Mira', sessionsTotal: 10, sessionsUsed: 3, sessionsScheduled: 2, sessionsRemaining: 7, startsOn: '2026-01-01', expiresOn: '2026-02-01', state: 'expired', canBook: false, timezone: 'Asia/Kolkata' }], error: null }, upcoming: { data: [session()], error: null }, history: { data: [], error: null },
});
let tree: HostNode; let Component: () => React.JSX.Element;
function renderNode(value: unknown): HostNode {
  if (value === null || value === undefined || typeof value === 'boolean') return { type: 'empty', props: {}, children: [], textContent: '' };
  if (Array.isArray(value)) { const children = value.map(renderNode); return { type: 'array', props: {}, children, textContent: children.map(child => child.textContent).join(' ') }; }
  if (typeof value !== 'object') return { type: 'text', props: {}, children: [], textContent: String(value) };
  const element = value as { type: unknown; props: Props };
  if (typeof element.type === 'function') return renderNode(element.type(element.props));
  if (element.type === 'Sheet' && !element.props.visible) return renderNode(null);
  const children = [element.props.title, element.props.meta, element.props.status, element.props.value, element.props.trailing, element.props.detail, element.props.message, element.props.children].filter(value => value !== undefined).map(renderNode);
  return { ...element, children, textContent: children.map(child => child.textContent).join(' ') };
}
function render() { hooks.cursor = 0; hooks.dirty = false; tree = renderNode(Component()); for (const effect of hooks.effects.splice(0)) effect(); }
async function flush() { for (let pass = 0; pass < 12; pass++) { await Promise.resolve(); if (hooks.dirty) render(); } }
function nodes(node = tree): HostNode[] { return [node, ...node.children.flatMap(child => nodes(child))]; }
function text() { return tree.textContent; }
function button(label: RegExp): HostNode { const result = nodes().find(n => typeof n.props.onPress === 'function' && label.test(n.textContent || String(n.props.accessibilityLabel ?? ''))); expect(result, `action ${label}`).toBeDefined(); return result!; }
async function act(fn: () => void | Promise<void>) { await fn(); await flush(); }
async function press(node: HostNode) { await act(async () => { (node.props.onPress as () => void)(); }); }
async function mount() { const targetModule = '../../apps/mobile/components/training-section'; const target = await import(targetModule); Component = target.TrainingSection; render(); await flush(); }
async function change(identity: GymloopIdentity) { mocks.context = { ...mocks.context, identity }; render(); await flush(); }
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(yes => { resolve = yes; }); return { promise, resolve }; }
beforeEach(() => {
  hooks.slots = []; hooks.cursor = 0; hooks.effects = []; hooks.cleanups = []; hooks.dirty = false;
  mocks.load.mockReset().mockResolvedValue(data()); mocks.post.mockReset().mockResolvedValue({ ok: true, data: { sessionId: id(50), status: 'cancelled_by_member', late: false, consumed: false, sessionsRemaining: 6, replayed: false } }); mocks.online = true; mocks.listeners.clear();
  mocks.context = { identity: member(), ready: true, session: { user: { id: id(1) }, access_token: 'caller-a' }, supabase: { rpc: vi.fn() }, api: { post: mocks.post }, businessType: 'gym', nouns: businessNouns('gym'), palette: UI_TOKENS.colors.light, appearance: 'light', webOrigin: 'https://example.invalid', signOut: vi.fn(), setAppearance: vi.fn() };
});
afterEach(() => { for (const cleanup of hooks.cleanups) cleanup?.(); });

describe('independent native Training reads and existing-session cancellation', () => {
  it.each(['trainers', 'programmes', 'packs', 'upcoming', 'history'] as const)('keeps successful sections when %s fails with null', async failed => {
    const fixture = data(); fixture[failed] = { data: null, error: 'Please try again.' }; mocks.load.mockResolvedValue(fixture); await mount();
    expect(text()).toContain('Please try again.');
    if (failed !== 'packs') expect(text()).toContain('Strength plan');
    if (failed !== 'programmes') expect(text()).toContain('Desk programme');
    if (failed !== 'trainers') expect(text()).toContain('Certified coach');
  });
  it('shows bought used reserved available and original expired balance separately', async () => { await mount(); expect(text()).toMatch(/3 of 10 used/); expect(text()).toContain('2 booked'); expect(text()).toContain('5 left to book'); expect(text()).toMatch(/7.*(?:unspent|left)|(?:unspent|left).*7/); expect(text()).toMatch(/1 (?:Sep|September) 2026/); expect(text()).toMatch(/1 (?:Feb|February) 2026/); const expired = nodes().find(n => n.props.title === 'Expired plan'); if (expired) expect(expired.textContent).not.toContain('Book a session'); });
  it('offers exact paise price GST terms and desk sale only', async () => { await mount(); expect(text()).toMatch(/12,?345\.67/); expect(text()).toContain('INR'); expect(text()).toMatch(/18\s*%/); expect(text()).toContain('Desk terms remain binding'); expect(text()).toContain('Show at the desk'); expect(text()).not.toMatch(/Buy now|Pay now|Purchase/); expect(mocks.post).not.toHaveBeenCalled(); });
  it('uses the six pinned words and explains past unmarked booked rows', async () => { const fixture = data(); fixture.history.data = [session({ endsAt: '2026-01-01T11:00:00+05:30' }), session({ status: 'attended' }), session({ status: 'no_show' }), session({ status: 'cancelled_by_member' }), session({ status: 'cancelled_by_gym' }), session({ status: 'cancelled_by_member', consumed: true })].map((row, i) => ({ ...row, sessionId: id(60 + i) })); await mountWith(fixture); for (const word of ['Booked', 'Attended', 'No-show', 'Cancelled by you', 'Cancelled by your gym', 'Cancelled late - session used', 'Waiting for your trainer to record it.']) expect(text()).toContain(word); expect(text()).not.toContain('Not marked'); });
  it.each< GymloopIdentity >([{ kind: 'unlinked' }, { kind: 'platform', userId: id(1), role: 'super_admin' }, { kind: 'impersonation', userId: id(1), tenantId: id(8), impersonationSessionId: id(9) }, { kind: 'staff', userId: id(1), tenantId: id(8), staffId: id(3), role: 'trainer' }])('wrong audience makes no read or command: $kind', async identity => { mocks.context.identity = identity; await mount(); expect(mocks.load).not.toHaveBeenCalled(); expect(mocks.post).not.toHaveBeenCalled(); });
  it('discards A to B to A late read rather than reviving revoked A', async () => { const old = deferred<MemberTraining>(); mocks.load.mockReturnValueOnce(old.promise); await mount(); await change(member(2)); await change(member()); const fixture = data(); fixture.trainers.data![0]!.displayName = 'Revoked response'; old.resolve(fixture); await flush(); expect(text()).not.toContain('Revoked response'); });
  it('a captured cancellation callback cannot act after caller revocation', async () => { await mount(); const cancel = button(/^Cancel(?: session)?$/i); await change({ kind: 'unlinked' }); await press(cancel); expect(mocks.post).not.toHaveBeenCalled(); });
  it('offline blocks writes and reconnect never replays a queued command', async () => { await mount(); const cancel = button(/^Cancel(?: session)?$/i); mocks.online = false; await act(async () => { for (const listener of mocks.listeners) listener({ isConnected: false, isInternetReachable: false }); }); await press(cancel); expect(mocks.post).not.toHaveBeenCalled(); expect(text()).toContain("You're offline. Showing what was last loaded."); mocks.online = true; await act(async () => { for (const listener of mocks.listeners) listener({ isConnected: true, isInternetReachable: true }); }); expect(mocks.post).not.toHaveBeenCalled(); });
  it('refreshes authoritative current session facts before opening late confirmation', async () => { await mount(); const refreshed = data(); refreshed.upcoming.data = [session({ lateNow: true, consumesNow: true })]; mocks.load.mockResolvedValue(refreshed); await press(button(/^Cancel(?: session)?$/i)); expect(mocks.load.mock.calls.length).toBeGreaterThan(1); expect(text()).toContain('This is inside your cancellation window. Cancelling will use 1 session from your pack.'); expect(mocks.post).not.toHaveBeenCalled(); });
  it('missing current session facts fail closed rather than trusting initial facts', async () => { await mount(); mocks.load.mockResolvedValue({ ...data(), upcoming: { data: null, error: 'Please try again.' } }); await press(button(/^Cancel(?: session)?$/i)); expect(mocks.post).not.toHaveBeenCalled(); expect(text()).not.toContain('Free to cancel until'); });
  it('free confirmation states an absolute gym-local cutoff before a command', async () => {
    await mount(); await press(button(/^Cancel(?: session)?$/i));
    expect(text()).toMatch(/Free to cancel until .*4 (?:Oct|October) 2026.*10:00/i);
    expect(mocks.post).not.toHaveBeenCalled();
  });
  it('caller change while cancellation refresh is pending cannot open stale confirmation', async () => {
    await mount(); const refresh = deferred<MemberTraining>(); mocks.load.mockReturnValueOnce(refresh.promise);
    await press(button(/^Cancel(?: session)?$/i)); await change(member(2)); await change(member());
    const old = data(); old.upcoming.data = [session({ lateNow: true, consumesNow: true })]; refresh.resolve(old); await flush();
    expect(text()).not.toContain('This is inside your cancellation window. Cancelling will use 1 session from your pack.');
    expect(mocks.post).not.toHaveBeenCalled();
  });
  it('reopening refreshes changed policy rather than retaining the first preview', async () => {
    await mount(); await press(button(/^Cancel(?: session)?$/i));
    const sheet = nodes().find(node => node.type === 'Sheet'); expect(sheet).toBeDefined();
    await act(() => { (sheet!.props.onClose as () => void)(); });
    const current = data(); current.upcoming.data = [session({ lateNow: true, consumesNow: false })]; mocks.load.mockResolvedValue(current);
    await press(button(/^Cancel(?: session)?$/i));
    expect(text()).toContain("This is inside your cancellation window. Cancelling won't use a session from your pack.");
    expect(text()).not.toContain('Cancelling will use 1 session from your pack.');
  });
  it('positively unreachable connection suppresses cancellation even when connected', async () => {
    await mount(); const cancel = button(/^Cancel(?: session)?$/i);
    await act(() => { for (const listener of mocks.listeners) listener({ isConnected: true, isInternetReachable: false }); });
    await press(cancel); expect(mocks.post).not.toHaveBeenCalled();
  });
  it('a retained callback after unmount cannot prepare or send a cancellation', async () => {
    await mount(); const cancel = button(/^Cancel(?: session)?$/i); const calls = mocks.load.mock.calls.length;
    for (const cleanup of hooks.cleanups) cleanup?.(); hooks.cleanups = [];
    await press(cancel); expect(mocks.post).not.toHaveBeenCalled(); expect(mocks.load.mock.calls.length).toBe(calls);
  });
  it('double activation sends one command and retry keeps the same existing session', async () => { await mount(); await press(button(/^Cancel(?: session)?$/i)); const confirm = button(/Confirm|Cancel session/i); const pending = deferred<unknown>(); mocks.post.mockReturnValueOnce(pending.promise); await act(async () => { (confirm.props.onPress as () => void)(); (confirm.props.onPress as () => void)(); }); expect(mocks.post).toHaveBeenCalledTimes(1); pending.resolve({ ok: false, error: { code: 'retryable', message: 'Please try again.' } }); await flush(); expect(text()).toContain('Please try again.'); await press(button(/Try again|Retry|Confirm|Cancel session/i)); expect(mocks.post).toHaveBeenLastCalledWith('/api/member/pt-bookings/cancel', { sessionId: id(50) }); });
  it('thrown uncertain cancellation remains failure and keeps same session on retry', async () => { await mount(); await press(button(/^Cancel(?: session)?$/i)); mocks.post.mockRejectedValueOnce(new Error('network interrupted')); await press(button(/Confirm|Cancel session/i)); expect(text()).toContain('Please try again.'); expect(text()).not.toMatch(/Successfully cancelled|Session cancelled successfully/); await press(button(/Try again|Retry|Confirm|Cancel session/i)); expect(mocks.post).toHaveBeenLastCalledWith('/api/member/pt-bookings/cancel', { sessionId: id(50) }); });
  it('ignores late command success after A to B to A', async () => { await mount(); await press(button(/^Cancel(?: session)?$/i)); const old = deferred<unknown>(); mocks.post.mockReturnValueOnce(old.promise); await press(button(/Confirm|Cancel session/i)); await change(member(2)); await change(member()); old.resolve({ ok: true, data: { sessionId: id(50), status: 'cancelled_by_member', consumed: true, late: true, sessionsRemaining: 4, replayed: false } }); await flush(); expect(text()).not.toContain('Cancelled late - session used'); });
});
async function mountWith(fixture: MemberTraining) { mocks.load.mockResolvedValue(fixture); await mount(); }
