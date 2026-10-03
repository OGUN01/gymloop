import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import type { PtPack, MemberTraining, PtPolicyRead } from '@gymloop/shared';
import { businessNouns, UI_TOKENS } from '@gymloop/shared';

// Independent declaration-only author. These hosts preserve callbacks and children;
// they make no geometry, dot, axe, screen-reader or real-device claim.
type Props = Record<string, unknown>;
type Node = { type: unknown; props: Props };
type Cell = { value?: unknown; deps?: unknown[] | undefined; cleanup?: (() => void) | undefined };
const seam = vi.hoisted(() => ({
  active: null as null | { cells: Cell[]; cursor: number; effects: (() => void)[] },
  mobile: {} as Props, online: true, listeners: new Set<(state: Props) => void>(),
  refresh: vi.fn(), audience: vi.fn(), webSchedule: vi.fn(), network: vi.fn(), loadMember: vi.fn(), loadDesk: vi.fn(), loadRoster: vi.fn(),
  book: vi.fn(), cancel: vi.fn(), deskBook: vi.fn(), deskCancel: vi.fn(), mark: vi.fn(), search: vi.fn(), training: vi.fn(), slots: vi.fn(), policy: vi.fn(), nativeTraining: vi.fn(), nativeSlots: vi.fn(), nativePolicy: vi.fn(), params: {} as Props, uuid: vi.fn(),
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
vi.mock('next/navigation', () => ({ useRouter: () => ({ refresh: seam.refresh }), notFound: () => { throw new Error('held-not-found'); } }));
vi.mock('../../apps/web/lib/identity-session', () => ({ requireAudience: seam.audience }));
vi.mock('../../apps/web/lib/training', () => ({ loadMemberTraining: seam.training, loadMemberSlots: seam.slots, loadMemberPtPolicy: seam.policy }));
vi.mock('../../apps/web/lib/business-type', () => ({
  loadBusinessOrganization: async () => ({ data: { name: 'Held Gym', business_type: 'gym', timezone: 'Asia/Kolkata' }, error: null }),
  loadBusinessNouns: async () => businessNouns('gym'),
}));
vi.mock('../../apps/web/app/preview-context', () => ({ usePreviewReadOnly: () => false }));
vi.mock('../../apps/mobile/lib/mobile-context', () => ({ useMobile: () => seam.mobile }));
vi.mock('../../apps/mobile/lib/use-business-nouns', () => ({ useBusinessNouns: () => seam.mobile.nouns }));
vi.mock('../../apps/mobile/lib/training', () => ({ loadTraining: seam.nativeTraining, loadSlots: seam.nativeSlots, loadPtPolicy: seam.nativePolicy }));
vi.mock('../../apps/mobile/lib/mobile-data', () => ({ loadDeskMembers: seam.search }));
vi.mock('expo-network', () => ({ getNetworkStateAsync: () => seam.network(),
  addNetworkStateListener: (fn: (state: Props) => void) => { seam.listeners.add(fn); return { remove: () => seam.listeners.delete(fn) }; },
}));
vi.mock('expo-router', () => ({ useLocalSearchParams: () => seam.params, useRouter: () => ({ push: vi.fn(), replace: vi.fn() }), router: { push: vi.fn() } }));
vi.mock('expo-crypto', () => ({ randomUUID: () => seam.uuid() }));
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

import * as ptActions from '../../apps/web/app/member/classes/training/pt-actions';

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
  function controls(pattern: RegExp) { return nodes.filter(node => typeof (node.props.onClick ?? node.props.onPress) === 'function' && (pattern.test(textOf(node.props.children).trim()) || pattern.test(String(node.props.accessibilityLabel ?? node.props['aria-label'] ?? '').trim()))); }
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

type Slot = { startsAt: string; endsAt: string; timezone: string };
type Facts = { pack: PtPack | null; slots: { data: Slot[] | null; error: string | null }; policy: PtPolicyRead };
type BookingBody = { orderId: string; sessionId: string; startsAt: string };
const id = (n: number) => `77930000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const memberA = { kind: 'member', userId: id(1), tenantId: id(2), memberId: id(3) };
const memberB = { kind: 'member', userId: id(4), tenantId: id(5), memberId: id(6) };
const nouns = businessNouns('gym');
const slot: Slot = { startsAt: '2026-10-03T04:30:00Z', endsAt: '2026-10-03T05:30:00Z', timezone: 'Asia/Kathmandu' };
const pack: PtPack = { orderId: id(40), programmeName: 'Held own strength', trainerKey: id(30), trainerName: 'Mira held trainer', sessionsTotal: 10, sessionsUsed: 3, sessionsScheduled: 2, sessionsRemaining: 5, startsOn: '2026-09-01', expiresOn: '2026-12-01', state: 'live', canBook: true, timezone: 'Asia/Kolkata' };
function facts(): Facts { return { pack: { ...pack }, slots: { data: [{ ...slot }], error: null }, policy: { data: { cancelWindowHours: 12, lateCancelConsumes: true }, error: null } }; }
function training(current: Facts): MemberTraining { return { trainers: { data: [], error: null }, programmes: { data: [], error: null }, packs: { data: current.pack ? [current.pack] : [], error: null }, upcoming: { data: [], error: null }, history: { data: [], error: null } }; }
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(done => { resolve = done; }); return { promise, resolve }; }
const confirm = /^Confirm(?: booking)?$/i;
const retry = /^(?:Retry(?:.*booking)?|Try again|Confirm(?: booking)?)$/i;
let currentFacts: Facts;
let post: ReturnType<typeof vi.fn<(path: string, body: BookingBody) => Promise<Record<string, unknown>>>>;
let fetchMock: ReturnType<typeof vi.fn>;
beforeEach(() => {
  vi.resetAllMocks(); vi.useFakeTimers(); vi.setSystemTime(new Date('2026-10-02T20:00:00Z')); currentFacts = facts();
  seam.online = true; seam.listeners.clear(); seam.params = { orderId: id(40) };
  seam.uuid.mockReturnValueOnce(id(90)).mockReturnValueOnce(id(91)).mockReturnValue(id(92));
  seam.network.mockImplementation(async () => ({ isConnected: seam.online, isInternetReachable: seam.online }));
  const query = { select: vi.fn().mockReturnThis(), eq: vi.fn().mockReturnThis(), maybeSingle: vi.fn(async () => ({ data: { timezone: 'Asia/Kolkata' }, error: null })) };
  post = vi.fn(async (_path: string, body: { sessionId: string; orderId: string; startsAt: string }) => ({ ok: true, data: { ...body, endsAt: slot.endsAt, status: 'booked', inCancelWindow: true, replayed: false } }));
  seam.mobile = { identity: memberA, ready: true, session: { user: { id: id(1) } }, supabase: { from: vi.fn(() => query) }, api: { post }, palette: UI_TOKENS.colors.light, nouns, businessType: 'gym', webOrigin: 'https://gymloop.test' };
  seam.audience.mockResolvedValue({ identity: memberA, supabase: seam.mobile.supabase });
  seam.training.mockImplementation(async () => training(currentFacts)); seam.slots.mockImplementation(async () => currentFacts.slots); seam.policy.mockImplementation(async () => currentFacts.policy);
  seam.nativeTraining.mockImplementation(async () => training(currentFacts)); seam.nativeSlots.mockImplementation(async () => currentFacts.slots); seam.nativePolicy.mockImplementation(async () => currentFacts.policy);
  fetchMock = vi.fn(async (_path: string, options: { body: string }) => ({ ok: true, json: async () => post('/api/member/pt-bookings', JSON.parse(options.body) as never) }));
  vi.stubGlobal('fetch', fetchMock); vi.stubGlobal('window', new EventTarget()); vi.stubGlobal('navigator', { onLine: true });
  vi.stubGlobal('crypto', { randomUUID: () => seam.uuid() });
});
afterEach(() => { for (const cleanup of hostCleanups) cleanup(); vi.useRealTimers(); vi.unstubAllGlobals(); });

async function setup(platform: 'web' | 'native') {
  const refreshFacts = vi.fn(async () => currentFacts);
  const props = { orderId: id(40), scopeKey: 'held-complete-A', nouns, initial: structuredClone(currentFacts), refreshFacts };
  let component: (props: never) => unknown;
  if (platform === 'web') component = (ptActions as unknown as Record<string, (props: never) => unknown>).PtBookingForm!;
  else { const path = '../../apps/mobile/app/training/book/[orderId]'; component = (await import(path) as { default: (props: never) => unknown }).default; }
  expect(component, 'frozen actual booking export').toBeTypeOf('function');
  const view = mount(component, platform === 'web' ? props : {}); await view.settle();
  const enabled = (pattern: RegExp) => view.controls(pattern).filter(node => !node.props.disabled && !(node.props.accessibilityState as Props | undefined)?.disabled);
  const choose = async () => { await view.press(/10[:.]15/i); };
  const noSend = () => { expect(fetchMock).not.toHaveBeenCalled(); expect(post).not.toHaveBeenCalled(); };
  const change = async (mode: 'scope' | 'api') => {
    if (platform === 'web') { view.rerender({ ...props, scopeKey: 'held-B' }); await view.settle(); view.rerender(props); }
    else if (mode === 'api') { seam.mobile = { ...seam.mobile, api: { post: vi.fn() } }; view.rerender(); }
    else { seam.mobile = { ...seam.mobile, identity: memberB }; view.rerender(); await view.settle(); seam.mobile = { ...seam.mobile, identity: memberA }; view.rerender(); }
    await view.settle();
  };
  return { view, choose, noSend, enabled, refreshFacts, props, change };
}

describe.each(['web', 'native'] as const)('independent actual %s PTF booking', platform => {
  it.each([true, false])('shows current returned times, trainer and late consequence flag=%s before exact command', async lateCancelConsumes => {
    currentFacts.policy = { data: { cancelWindowHours: 12, lateCancelConsumes }, error: null };
    const h = await setup(platform); await h.choose(); h.noSend();
    for (const word of ['Held own strength', 'Mira held trainer']) expect(h.view.text()).toContain(word);
    expect(h.view.text()).toMatch(/10[:.]15/); expect(h.view.text()).toMatch(/11[:.]15/);
    expect(h.view.text()).toContain(lateCancelConsumes ? 'This is inside your cancellation window. Cancelling will use 1 session from your pack.' : "This is inside your cancellation window. Cancelling won't use a session from your pack.");
    await h.view.press(confirm);
    expect(post).toHaveBeenCalledTimes(1); const [path, body] = post.mock.calls[0]!;
    expect(path).toBe('/api/member/pt-bookings'); expect(body).toEqual({ orderId: id(40), sessionId: expect.stringMatching(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i), startsAt: slot.startsAt });
    h.view.unmount();
  });

  it.each(['missing policy', 'failed policy', 'gone own pack', 'pack closed', 'slot gone', 'failed slots'])('fresh %s prevents a new command', async missing => {
    const h = await setup(platform);
    if (missing === 'missing policy') currentFacts.policy = { data: null, error: null };
    if (missing === 'failed policy') currentFacts.policy = { data: null, error: 'Please try again.' };
    if (missing === 'gone own pack') currentFacts.pack = null;
    if (missing === 'pack closed') currentFacts.pack = { ...pack, state: 'closed', canBook: false };
    if (missing === 'slot gone') currentFacts.slots = { data: [], error: null };
    if (missing === 'failed slots') currentFacts.slots = { data: null, error: 'Please try again.' };
    await h.choose(); expect(h.enabled(confirm)).toHaveLength(0); h.noSend(); h.view.unmount();
  });

  it('changed policy at final refresh requires another explicit confirmation of new facts', async () => {
    const h = await setup(platform); await h.choose();
    currentFacts.policy = { data: { cancelWindowHours: 12, lateCancelConsumes: false }, error: null };
    await h.view.press(confirm); h.noSend();
    expect(h.view.text()).toContain("Cancelling won't use a session from your pack.");
    await h.view.press(confirm); expect(post).toHaveBeenCalledTimes(1); h.view.unmount();
  });

  it('closing and reopening refreshes policy and starts a new sheet identity', async () => {
    const h = await setup(platform); await h.choose();
    post.mockRejectedValueOnce(new Error('Unknown first sheet result')); await h.view.press(confirm);
    expect(post).toHaveBeenCalledTimes(1); const firstBody = post.mock.calls[0]![1];
    const sheet = h.view.nodes().find(node => typeof node.props.onClose === 'function'); expect(sheet).toBeDefined(); (sheet!.props.onClose as () => void)(); await h.view.settle();
    currentFacts.policy = { data: { cancelWindowHours: 0, lateCancelConsumes: false }, error: null };
    await h.choose(); expect(h.view.text()).toContain('You can cancel for free until'); expect(post).toHaveBeenCalledTimes(1);
    await h.view.press(confirm); expect(post).toHaveBeenCalledTimes(2); expect(post.mock.calls[1]![1].sessionId).not.toBe(firstBody.sessionId); h.view.unmount();
  });

  it.each(['booked', 'cancelled_by_member', 'attended'] as const)('explicit uncertain retry retains exact body despite closed pack/gone slot and renders current %s', async status => {
    const h = await setup(platform); await h.choose(); post.mockRejectedValueOnce(new Error('Unknown network outcome')); await h.view.press(confirm);
    expect(post).toHaveBeenCalledTimes(1); const original = post.mock.calls[0]![1]; expect(h.view.text()).not.toMatch(/successfully booked|booking confirmed/i);
    currentFacts = { ...currentFacts, pack: { ...pack, state: 'closed', canBook: false }, slots: { data: [], error: null } };
    post.mockImplementationOnce(async (_path, body) => ({ ok: true, data: { ...body, endsAt: slot.endsAt, status, inCancelWindow: true, replayed: true } }));
    await h.view.settle(); expect(post).toHaveBeenCalledTimes(1); await h.view.press(retry);
    expect(post).toHaveBeenCalledTimes(2); expect(post.mock.calls[1]).toEqual(['/api/member/pt-bookings', original]);
    expect(h.view.text()).toContain(status === 'booked' ? 'Booked' : status === 'attended' ? 'Attended' : 'Cancelled by you');
    if (status !== 'booked') expect(h.view.text()).not.toMatch(/successfully booked|booking confirmed/i); h.view.unmount();
  });

  it.each(['missing fields', 'wrong order', 'wrong start'])('a %s answer cannot announce acceptance', async malformed => {
    const h = await setup(platform); await h.choose();
    post.mockImplementationOnce(async (_path, body) => ({ ok: true, data: malformed === 'missing fields' ? { sessionId: body.sessionId } : { ...body, orderId: malformed === 'wrong order' ? id(99) : body.orderId, startsAt: malformed === 'wrong start' ? '2026-10-04T04:30:00Z' : body.startsAt, endsAt: slot.endsAt, status: 'booked', inCancelWindow: true, replayed: false } } as never));
    await h.view.press(confirm); expect(post).toHaveBeenCalledTimes(1); expect(h.view.text()).not.toMatch(/successfully booked|booking confirmed/i); h.view.unmount();
  });

  it('offline suppresses transport and reconnect never auto-replays', async () => {
    const h = await setup(platform); await h.choose(); seam.online = false; (navigator as { onLine: boolean }).onLine = false;
    for (const listener of seam.listeners) listener({ isConnected: false, isInternetReachable: false }); window.dispatchEvent(new Event('offline')); await h.view.settle();
    const retained = h.view.controls(confirm)[0]; const callback = retained?.props.onPress ?? retained?.props.onClick; if (typeof callback === 'function') callback(); await h.view.settle(); h.noSend();
    seam.online = true; (navigator as { onLine: boolean }).onLine = true; for (const listener of seam.listeners) listener({ isConnected: true, isInternetReachable: true }); window.dispatchEvent(new Event('online')); await h.view.settle(); h.noSend(); h.view.unmount();
  });

  it.each(platform === 'web' ? ['unmount', 'scope'] as const : ['unmount', 'scope', 'api'] as const)('ready retained confirmation remains dead after %s', async revoke => {
    const h = await setup(platform); await h.choose(); const button = h.enabled(confirm)[0]; expect(button).toBeDefined(); const callback = button?.props.onClick ?? button?.props.onPress;
    if (revoke === 'unmount') h.view.unmount(); else await h.change(revoke);
    const reads = [seam.nativeTraining.mock.calls.length, seam.nativeSlots.mock.calls.length, seam.nativePolicy.mock.calls.length, h.refreshFacts.mock.calls.length];
    if (typeof callback === 'function') callback(); await Promise.resolve(); await Promise.resolve(); h.noSend();
    expect([seam.nativeTraining.mock.calls.length, seam.nativeSlots.mock.calls.length, seam.nativePolicy.mock.calls.length, h.refreshFacts.mock.calls.length]).toEqual(reads); if (revoke !== 'unmount') h.view.unmount();
  });

  it('discarded preparation cannot publish old sheet facts or start further reads after caller turnover', async () => {
    const h = await setup(platform); const pending = deferred<Facts>();
    if (platform === 'web') h.refreshFacts.mockReturnValueOnce(pending.promise);
    else seam.nativePolicy.mockReturnValueOnce(pending.promise.then(value => value.policy));
    await h.choose();
    currentFacts = { ...facts(), pack: { ...pack, programmeName: 'Current replacement programme' } };
    await h.change('scope');
    const reads = [h.refreshFacts.mock.calls.length, seam.nativeSlots.mock.calls.length, seam.nativePolicy.mock.calls.length];
    pending.resolve({ ...facts(), pack: { ...pack, programmeName: 'Revoked delayed programme' } }); await h.view.settle();
    expect(h.view.text()).not.toContain('Revoked delayed programme');
    expect([h.refreshFacts.mock.calls.length, seam.nativeSlots.mock.calls.length, seam.nativePolicy.mock.calls.length]).toEqual(reads); h.noSend(); h.view.unmount();
  });

  it('a pending command dispatches once and its late success cannot publish into a returned caller lifetime', async () => {
    const h = await setup(platform); await h.choose(); const pending = deferred<Record<string, unknown>>(); post.mockReturnValueOnce(pending.promise);
    const button = h.enabled(confirm)[0]; expect(button).toBeDefined(); const callback = button?.props.onPress ?? button?.props.onClick;
    if (typeof callback === 'function') { callback(); callback(); } await h.view.settle(); expect(post).toHaveBeenCalledTimes(1);
    const body = post.mock.calls[0]![1]; await h.change('scope'); const refreshes = seam.refresh.mock.calls.length;
    pending.resolve({ ok: true, data: { ...body, endsAt: slot.endsAt, status: 'booked', inCancelWindow: true, replayed: false } }); await h.view.settle();
    expect(post).toHaveBeenCalledTimes(1); expect(seam.refresh).toHaveBeenCalledTimes(refreshes); expect(h.view.text()).not.toMatch(/successfully booked|booking confirmed/i); h.view.unmount();
  });
});

describe('actual PTF route and refreshed caller boundaries', () => {
  async function page(orderId = id(40)) { const path = '../../apps/web/app/member/classes/training/book/[orderId]/page'; const module = await import(path) as { default: (props: { params: Promise<{ orderId: string }> }) => Promise<unknown> }; return module.default({ params: Promise.resolve({ orderId }) }); }
  function findForm(tree: unknown): Props | null { if (Array.isArray(tree)) { for (const node of tree) { const match = findForm(node); if (match) return match; } return null; } if (!tree || typeof tree !== 'object') return null; const node = tree as Node; if (typeof node.props?.refreshFacts === 'function' && node.props.orderId === id(40)) return node.props; return findForm(node.props?.children); }
  it('web reads exact 14 inclusive gym-local dates and same-caller server refresh uses the newly supplied client', async () => {
    const result = await page(); const form = findForm(result); expect(form).not.toBeNull();
    expect(seam.slots).toHaveBeenCalledWith(seam.mobile.supabase, id(40), '2026-10-03', '2026-10-16');
    const fresh = { marker: 'new authenticated caller client' }; seam.audience.mockResolvedValue({ identity: memberA, supabase: fresh }); vi.clearAllMocks();
    const factsNow = await (form!.refreshFacts as () => Promise<unknown>)(); expect(factsNow).not.toBeNull(); expect(seam.training).toHaveBeenCalledWith(fresh); expect(seam.policy).toHaveBeenCalledWith(fresh); expect(seam.slots).toHaveBeenCalledWith(fresh, id(40), '2026-10-03', '2026-10-16');
  });
  it.each([{ ...memberA, userId: id(7) }, { ...memberA, tenantId: id(8) }, { ...memberA, memberId: id(9) }])('server refresh rejects changed complete scope before member feature reads: %j', async identity => {
    const form = findForm(await page()); expect(form).not.toBeNull(); seam.audience.mockResolvedValue({ identity, supabase: { marker: 'foreign' } }); vi.clearAllMocks();
    expect(await (form!.refreshFacts as () => Promise<unknown>)()).toBeNull(); expect(seam.training).not.toHaveBeenCalled(); expect(seam.slots).not.toHaveBeenCalled(); expect(seam.policy).not.toHaveBeenCalled();
  });
  it('native reads exact 14 inclusive gym-local dates through its supplied caller', async () => { const h = await setup('native'); expect(seam.nativeSlots).toHaveBeenCalledWith(seam.mobile.supabase, id(40), '2026-10-03', '2026-10-16'); h.view.unmount(); });
  it.each(['bad-reference', id(99)])('native invalid or foreign order %s cannot select current own pack or send', async orderId => {
    seam.params = { orderId }; const h = await setup('native'); expect(h.enabled(/10[:.]15|Confirm/i)).toHaveLength(0); h.noSend(); h.view.unmount();
  });
  it('native non-member route makes no member reads', async () => { seam.mobile.identity = { kind: 'unlinked' }; const h = await setup('native'); expect(seam.nativeTraining).not.toHaveBeenCalled(); expect(seam.nativeSlots).not.toHaveBeenCalled(); expect(seam.nativePolicy).not.toHaveBeenCalled(); h.noSend(); h.view.unmount(); });
  it('native provider readiness gates every member read and command', async () => { seam.mobile.ready = false; const h = await setup('native'); expect(seam.nativeTraining).not.toHaveBeenCalled(); expect(seam.nativeSlots).not.toHaveBeenCalled(); expect(seam.nativePolicy).not.toHaveBeenCalled(); h.noSend(); h.view.unmount(); });
  it.each(['bad-reference', id(99)])('web invalid or foreign order %s never reaches slot selection', async orderId => {
    let result: unknown;
    try { result = await page(orderId); } catch (error) { expect(error).toEqual(new Error('held-not-found')); }
    expect(findForm(result)).toBeNull(); expect(seam.slots).not.toHaveBeenCalled(); expect(post).not.toHaveBeenCalled();
  });
});
