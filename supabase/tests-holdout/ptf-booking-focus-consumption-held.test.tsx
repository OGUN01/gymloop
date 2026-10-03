import { ptCommandAnswer } from '../../packages/shared/src/api/pt-front';
import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import type { PtPack, MemberTraining, PtPolicyRead, PtSession } from '@gymloop/shared';
import { businessNouns, UI_TOKENS, formatDateTime } from '@gymloop/shared';

// Independent declaration-only author. These hosts preserve callbacks and children;
// they make no geometry, dot, axe, screen-reader or real-device claim.
type Props = Record<string, unknown>;
type Node = { type: unknown; props: Props };
type Cell = { value?: unknown; deps?: unknown[] | undefined; cleanup?: (() => void) | undefined };
const seam = vi.hoisted(() => ({
  active: null as null | { cells: Cell[]; cursor: number; effects: (() => void)[] },
  mobile: {} as Props, focus: true, online: true, listeners: new Set<(state: Props) => void>(),
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
vi.mock('expo-router', async () => { const React = await import('react'); return ({ useIsFocused: () => seam.focus, useFocusEffect: (callback: () => void | (() => void)) => React.useEffect(() => seam.focus ? callback() : undefined, [callback, seam.focus]), useLocalSearchParams: () => seam.params, useRouter: () => ({ push: vi.fn(), replace: vi.fn() }), router: { push: vi.fn() } }); });
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
  return Object.fromEntries(['Screen', 'Title', 'Eyebrow', 'ActionButton', 'Body', 'EmptyState', 'ErrorRetry', 'LoadingState', 'Row', 'RowAction', 'SearchField', 'Sheet', 'SheetHeader', 'StateMessage', 'Status', 'LedgerSection', 'Display', 'Rule'].map(name => [name, host(name)]));
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
type Facts = { pack: PtPack | null; slots: { data: Slot[] | null; error: string | null }; policy: PtPolicyRead; sessions?: { data: PtSession[] | null; error: string | null } };
type BookingBody = { orderId: string; sessionId: string; startsAt: string };
const id = (n: number) => `77930000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const memberA = { kind: 'member', userId: id(1), tenantId: id(2), memberId: id(3) };
const memberB = { kind: 'member', userId: id(4), tenantId: id(5), memberId: id(6) };
const nouns = businessNouns('gym');
const slot: Slot = { startsAt: '2026-10-03T04:30:00Z', endsAt: '2026-10-03T05:30:00Z', timezone: 'Asia/Kathmandu' };
const pack: PtPack = { orderId: id(40), programmeName: 'Held own strength', trainerKey: id(30), trainerName: 'Mira held trainer', sessionsTotal: 10, sessionsUsed: 3, sessionsScheduled: 2, sessionsRemaining: 5, startsOn: '2026-09-01', expiresOn: '2026-12-01', state: 'live', canBook: true, timezone: 'Asia/Kolkata' };
function facts(): Facts { return { pack: { ...pack }, slots: { data: [{ ...slot }], error: null }, policy: { data: { cancelWindowHours: 12, lateCancelConsumes: true }, error: null } }; }
function training(current: Facts): MemberTraining { return { trainers: { data: [], error: null }, programmes: { data: [], error: null }, packs: { data: current.pack ? [current.pack] : [], error: null }, upcoming: { data: [], error: null }, history: current.sessions ?? { data: [], error: null } }; }
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(done => { resolve = done; }); return { promise, resolve }; }
const confirm = /^Confirm(?: booking)?$/i;
const retry = /^(?:Retry(?:.*booking)?|Try again|Confirm(?: booking)?)$/i;
let currentFacts: Facts;
let post: ReturnType<typeof vi.fn<(path: string, body: BookingBody) => Promise<Record<string, unknown>>>>;
let fetchMock: ReturnType<typeof vi.fn>;
beforeEach(() => {
  vi.resetAllMocks(); vi.useFakeTimers(); vi.setSystemTime(new Date('2026-10-02T20:00:00Z')); currentFacts = facts();
  seam.focus = true; seam.online = true; seam.listeners.clear(); seam.params = { orderId: id(40) };
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


function retained(h: Awaited<ReturnType<typeof setup>>, pattern = confirm) {
  const control = h.enabled(pattern)[0]; expect(control).toBeDefined();
  return (control!.props.onClick ?? control!.props.onPress) as () => void;
}
async function cycleFocus(h: Awaited<ReturnType<typeof setup>>) {
  seam.focus = false; h.view.rerender(); await h.view.settle();
  seam.focus = true; h.view.rerender(); await h.view.settle();
}
function recorded(body: BookingBody, consumed: boolean): PtSession {
  return { ...body, endsAt: slot.endsAt, timezone: slot.timezone, programmeName: pack.programmeName,
    trainerKey: pack.trainerKey, trainerName: pack.trainerName, status: 'cancelled_by_member', consumed,
    cancelledAt: '2026-10-02T20:00:00Z', cancelCutoff: '2026-10-02T16:30:00Z', lateNow: true,
    consumesNow: !consumed, canCancel: false };
}
const neutral = 'Cancelled. Reload to check whether a session was used.';
async function uncertain(platform: 'web' | 'native') {
  const h = await setup(platform); await h.choose();
  post.mockRejectedValueOnce(new Error('Lost acknowledgement')); await h.view.press(confirm);
  expect(post).toHaveBeenCalledTimes(1); const body = post.mock.calls[0]![1];
  post.mockImplementationOnce(async () => ({ ok: true, data: { ...body, endsAt: slot.endsAt,
    status: 'cancelled_by_member', inCancelWindow: false, replayed: true } }));
  return { h, body };
}
describe('held actual native mounted focus lifetime', () => {
  it.each(['ready confirmation', 'uncertain retry'])('%s stays permanently dead after blur and return', async kind => {
    const h = await setup('native'); await h.choose();
    if (kind === 'uncertain retry') { post.mockRejectedValueOnce(new Error('Lost')); await h.view.press(confirm); }
    const callback = retained(h, kind === 'uncertain retry' ? retry : confirm);
    await cycleFocus(h); const sends = post.mock.calls.length;
    const reads = [seam.nativeTraining.mock.calls.length, seam.nativeSlots.mock.calls.length, seam.nativePolicy.mock.calls.length];
    callback(); await h.view.settle(); expect(post).toHaveBeenCalledTimes(sends);
    expect([seam.nativeTraining.mock.calls.length, seam.nativeSlots.mock.calls.length, seam.nativePolicy.mock.calls.length]).toEqual(reads);
    await h.choose(); await h.view.press(confirm); expect(post).toHaveBeenCalledTimes(sends + 1);
    if (sends) expect(post.mock.calls[sends]![1].sessionId).not.toBe(post.mock.calls[0]![1].sessionId);
  });
  it.each(['read', 'preflight'])('pending %s cannot publish or send after blur/refocus', async phase => {
    const h = await setup('native'); await h.choose();
    const read = deferred<MemberTraining>(); const network = deferred<Props>();
    if (phase === 'read') seam.nativeTraining.mockReturnValueOnce(read.promise);
    else seam.network.mockReturnValueOnce(network.promise);
    retained(h)(); await h.view.settle(); h.noSend(); await cycleFocus(h);
    const reads = [seam.nativeTraining.mock.calls.length, seam.nativeSlots.mock.calls.length, seam.nativePolicy.mock.calls.length];
    read.resolve(training({ ...facts(), pack: { ...pack, programmeName: 'Revoked focus result' } }));
    network.resolve({ isConnected: true, isInternetReachable: true }); await h.view.settle(); h.noSend();
    expect(h.view.text()).not.toContain('Revoked focus result');
    expect([seam.nativeTraining.mock.calls.length, seam.nativeSlots.mock.calls.length, seam.nativePolicy.mock.calls.length]).toEqual(reads);
  });
});
describe.each(['web', 'native'] as const)('held %s cancelled replay consumption', platform => {
  it.each([true, false])('reads fresh exact recorded consumption=%s before truthful acknowledgement', async consumed => {
    const { h, body } = await uncertain(platform);
    currentFacts.sessions = { data: [recorded(body, consumed)], error: null };
    currentFacts.policy = { data: { cancelWindowHours: 0, lateCancelConsumes: !consumed }, error: null };
    const read = deferred<Facts>();
    if (platform === 'web') h.refreshFacts.mockReturnValueOnce(read.promise);
    else seam.nativeTraining.mockReturnValueOnce(read.promise.then(training));
    retained(h, retry)(); await h.view.settle(); expect(post).toHaveBeenCalledTimes(2);
    expect(h.view.text()).not.toContain('Cancelled by you'); expect(h.view.text()).not.toContain('Cancelled late - session used');
    read.resolve(currentFacts); await h.view.settle();
    expect(h.view.text()).toContain(consumed ? 'Cancelled late - session used' : 'Cancelled by you');
    expect(post.mock.calls[1]).toEqual(['/api/member/pt-bookings', body]); expect(post).toHaveBeenCalledTimes(2);
  });
  it.each(['missing', 'error', 'session', 'order', 'start', 'end', 'nonboolean'] as const)('%s authoritative facts leave exact neutral copy without resubmit', async defect => {
    const { h, body } = await uncertain(platform); const own = recorded(body, true);
    if (defect === 'missing') currentFacts.sessions = { data: [], error: null };
    else if (defect === 'error') currentFacts.sessions = { data: null, error: 'retryable' };
    else {
      const row = { ...own };
      if (defect === 'session') row.sessionId = id(99);
      if (defect === 'order') row.orderId = id(99);
      if (defect === 'start') row.startsAt = '2026-10-03T04:31:00Z';
      if (defect === 'end') row.endsAt = '2026-10-03T05:31:00Z';
      if (defect === 'nonboolean') Object.assign(row, { consumed: null });
      currentFacts.sessions = { data: [row], error: null };
    }
    await h.view.press(retry); expect(h.view.text()).toContain(neutral);
    expect(h.view.text()).not.toContain('Cancelled by you'); expect(h.view.text()).not.toContain('Cancelled late - session used');
    await h.view.settle(); expect(post).toHaveBeenCalledTimes(2);
  });
  it('caller revocation while consumption read waits prevents publication', async () => {
    const { h, body } = await uncertain(platform); const read = deferred<Facts>();
    if (platform === 'web') h.refreshFacts.mockReturnValueOnce(read.promise);
    else seam.nativeTraining.mockReturnValueOnce(read.promise.then(training));
    retained(h, retry)(); await h.view.settle(); expect(post).toHaveBeenCalledTimes(2);
    await h.change('scope'); read.resolve({ ...facts(), sessions: { data: [recorded(body, true)], error: null } });
    await h.view.settle(); expect(h.view.text()).not.toContain('Cancelled late - session used');
    expect(h.view.text()).not.toContain('Cancelled by you'); expect(post).toHaveBeenCalledTimes(2);
  });
});

describe('held focus fresh return independence', () => {
  it('fresh native sheet after return can book with a fresh UUID', async () => {
    const h = await setup('native'); await h.choose();
    post.mockRejectedValueOnce(new Error('Lost first lifetime')); await h.view.press(confirm);
    const oldBody = post.mock.calls[0]![1]; await cycleFocus(h);
    await h.choose(); await h.view.press(confirm); expect(post).toHaveBeenCalledTimes(2);
    expect(post.mock.calls[1]![1].sessionId).not.toBe(oldBody.sessionId);
  });
});
describe.each(['web', 'native'] as const)('held %s failed consumption refresh', platform => {
  it('a failed fresh training read leaves acknowledged neutral feedback and never replays automatically', async () => {
    const { h } = await uncertain(platform);
    if (platform === 'web') h.refreshFacts.mockResolvedValueOnce(null as never);
    else seam.nativeTraining.mockResolvedValueOnce({ ...training(facts()), upcoming: { data: null, error: 'retryable' }, history: { data: null, error: 'retryable' } });
    await h.view.press(retry); expect(h.view.text()).toContain(neutral); await h.view.settle();
    expect(post).toHaveBeenCalledTimes(2);
  });
});

function nodeWords(value: unknown): string {
  if (value == null || typeof value === 'boolean') return '';
  if (Array.isArray(value)) return value.map(nodeWords).join(' ');
  if (typeof value === 'object') return nodeWords((value as Node).props?.children);
  return String(value);
}
describe.each(['web', 'native'] as const)('held %s absolute cutoff and status vocabulary', platform => {
  it.each([true, false])('already-late sheet names exact slot-zone cutoff before Confirm, consumption=%s', async lateCancelConsumes => {
    currentFacts.policy = { data: { cancelWindowHours: 12, lateCancelConsumes }, error: null };
    const h = await setup(platform); await h.choose(); h.noSend();
    expect(h.view.text()).toContain(formatDateTime('2026-10-02T16:30:00Z', slot.timezone));
    expect(h.view.text()).toContain(slot.timezone);
    expect(h.view.text()).toContain(lateCancelConsumes ? 'This is inside your cancellation window. Cancelling will use 1 session from your pack.' : "This is inside your cancellation window. Cancelling won't use a session from your pack.");
  });
  it('fresh window change recomputes absolute cutoff in selected slot zone and needs renewed confirmation', async () => {
    const h = await setup(platform); await h.choose();
    currentFacts.policy = { data: { cancelWindowHours: 10, lateCancelConsumes: false }, error: null };
    await h.view.press(confirm); h.noSend();
    expect(h.view.text()).toContain(formatDateTime('2026-10-02T18:30:00Z', slot.timezone));
    expect(h.view.text()).not.toContain(formatDateTime('2026-10-02T16:30:00Z', slot.timezone));
    expect(h.view.text()).toContain(slot.timezone);
    expect(h.view.text()).toContain("This is inside your cancellation window. Cancelling won't use a session from your pack.");
  });
  it('unestablished consumption acknowledgement is ordinary feedback rather than a seventh status word', async () => {
    const { h } = await uncertain(platform); currentFacts.sessions = { data: [], error: null };
    await h.view.press(retry); expect(h.view.text()).toContain(neutral);
    const statuses = h.view.nodes().filter(node => node.type === 'Status' || Object.hasOwn(node.props, 'data-status'));
    for (const status of statuses) {
      expect(nodeWords(status.props.children)).not.toContain(neutral);
      for (const field of ['label', 'value', 'status', 'data-status']) expect(String(status.props[field] ?? '')).not.toContain(neutral);
    }
  });
});

describe('held PT applicability within generated booking enum', () => {
  it('registered book decoder rejects otherwise exact CLS-only session_cancelled row', () => {
    expect(ptCommandAnswer('book', [{ order_id: pack.orderId, session_id: id(90), starts_at: slot.startsAt,
      ends_at: slot.endsAt, status: 'session_cancelled', in_cancel_window: true, replayed: false }])).toBeNull();
  });
});
describe.each(['web', 'native'] as const)('held actual %s CLS-only PT answer boundary', platform => {
  it('matching CLS status keeps original uncertain command retryable without automatic dispatch or invented status', async () => {
    const h = await setup(platform); await h.choose();
    post.mockImplementationOnce(async (_path, body) => ({ ok: true, data: { ...body, endsAt: slot.endsAt,
      status: 'session_cancelled', inCancelWindow: true, replayed: false } }));
    await h.view.press(confirm); expect(post).toHaveBeenCalledTimes(1);
    const original = post.mock.calls[0]![1];
    expect(h.view.text()).not.toMatch(/Unavailable|successfully booked|booking confirmed/i);
    expect(h.enabled(retry).length).toBeGreaterThan(0);
    expect(h.enabled(/reload/i).length).toBeGreaterThan(0);
    const statuses = h.view.nodes().filter(node => node.type === 'Status' || Object.hasOwn(node.props, 'data-status'));
    for (const status of statuses) {
      expect(nodeWords(status.props.children)).not.toMatch(/Unavailable|session.cancelled/i);
      for (const field of ['label', 'value', 'status', 'data-status']) expect(String(status.props[field] ?? '')).not.toMatch(/Unavailable|session.cancelled/i);
    }
    await h.view.settle(); expect(post).toHaveBeenCalledTimes(1);
    currentFacts = { ...currentFacts, pack: { ...pack, state: 'closed', canBook: false }, slots: { data: [], error: null } };
    post.mockImplementationOnce(async (_path, body) => ({ ok: true, data: { ...body, endsAt: slot.endsAt,
      status: 'booked', inCancelWindow: true, replayed: true } }));
    await h.view.press(retry); expect(post).toHaveBeenCalledTimes(2);
    expect(post.mock.calls[1]).toEqual(['/api/member/pt-bookings', original]); expect(h.view.text()).toContain('Booked');
  });
});
