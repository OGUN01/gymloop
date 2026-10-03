import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PtSession } from '@gymloop/shared';

type Host = { type: unknown; props: Record<string, unknown> };
type Effect = { deps: unknown[] | undefined; cleanup?: () => void };
const h = vi.hoisted(() => {
  const state: unknown[] = [];
  const effects: Effect[] = [];
  let index = 0;
  let queued: Array<() => void> = [];
  let tree: unknown;
  let render: () => unknown = () => null;
  const node = (type: unknown, props: Record<string, unknown> | null, ...children: unknown[]): Host => ({ type, props: { ...props, ...(children.length ? { children } : {}) } });
  const useState = (initial: unknown) => {
    const position = index++;
    if (!(position in state)) state[position] = typeof initial === 'function' ? (initial as () => unknown)() : initial;
    return [state[position], (value: unknown) => { state[position] = typeof value === 'function' ? (value as (old: unknown) => unknown)(state[position]) : value; }];
  };
  const useRef = (initial: unknown) => { const position = index++; if (!(position in state)) state[position] = { current: initial }; return state[position]; };
  const useMemo = (make: () => unknown) => { index++; return make(); };
  const useEffect = (effect: () => (() => void) | void, deps?: unknown[]) => {
    const position = index++;
    const old = effects[position];
    if (!old || !deps || deps.some((value, key) => !Object.is(value, old.deps?.[key]))) {
      queued.push(() => { old?.cleanup?.(); const cleanup = effect(); effects[position] = { deps, ...(cleanup ? { cleanup } : {}) }; });
    }
  };
  const walk = (value: unknown): Host[] => {
    if (Array.isArray(value)) return value.flatMap(walk);
    if (!value || typeof value !== 'object' || !('props' in value)) return [];
    const item = value as Host;
    if (typeof item.type === 'function') return walk((item.type as (props: Record<string, unknown>) => unknown)(item.props));
    if (item.props.visible === false) return [];
    return [item, ...walk(item.props.children), ...walk(item.props.trailing)];
  };
  const words = (value: unknown): string => {
    if (Array.isArray(value)) return value.map(words).join(' ');
    if (typeof value === 'string' || typeof value === 'number') return String(value);
    if (!value || typeof value !== 'object' || !('props' in value)) return '';
    const item = value as Host;
    if (typeof item.type === 'function') return words((item.type as (props: Record<string, unknown>) => unknown)(item.props));
    if (item.props.visible === false) return '';
    return [item.props.title, item.props.detail, item.props.meta, item.props.accessibilityLabel, item.props.children, item.props.trailing].map(words).join(' ');
  };
  const load = vi.fn(); const post = vi.fn(); const fetch = vi.fn(); const refresh = vi.fn();
  const nouns = { place: 'gym', session: 'session', sessions: 'sessions', class: 'class', classes: 'classes', member: 'member', members: 'members', trainer: 'trainer' };
  const identity = { kind: 'member', userId: '11111111-1111-4111-8111-111111111111', tenantId: '22222222-2222-4222-8222-222222222222', memberId: '33333333-3333-4333-8333-333333333333' };
  const mobile = { identity, ready: true, api: { post }, supabase: {}, nouns, palette: {}, session: null, appearance: 'light', businessType: 'gym', webOrigin: 'https://example.com', setAppearance: vi.fn(), signOut: vi.fn() };
  return { node, useState, useRef, useMemo, useEffect, walk, words, load, post, fetch, refresh, nouns, mobile,
    mount(component: () => unknown) { effects.forEach(effect => effect?.cleanup?.()); effects.length = 0; state.length = 0; queued = []; render = component; },
    paint() { index = 0; tree = render(); const pending = queued; queued = []; pending.forEach(effect => effect()); return tree; },
    tree: () => tree,
  };
});
vi.mock('react', () => ({ default: { createElement: h.node }, createElement: h.node, Fragment: 'fragment', useState: h.useState, useRef: h.useRef, useEffect: h.useEffect, useLayoutEffect: h.useEffect, useMemo: h.useMemo, useCallback: (callback: unknown) => h.useMemo(() => callback) }));
vi.mock('react/jsx-runtime', () => ({ jsx: h.node, jsxs: h.node, Fragment: 'fragment' }));
vi.mock('react-native', () => ({ View: 'view', Text: 'text', Pressable: 'button', ScrollView: 'scroll', Image: 'image', ActivityIndicator: 'loading', StyleSheet: { create: (styles: unknown) => styles }, Platform: { OS: 'android' } }));
vi.mock('expo-network', () => ({ getNetworkStateAsync: vi.fn(async () => ({ isConnected: true, isInternetReachable: true })), addNetworkStateListener: vi.fn(() => ({ remove: vi.fn() })) }));
vi.mock('expo-router', () => ({ useRouter: () => ({ push: vi.fn() }) }));
vi.mock('next/navigation', () => ({ useRouter: () => ({ refresh: h.refresh }) }));
vi.mock('../../apps/web/app/member/classes/class-actions', () => ({ ClassConfirmation: (props: Record<string, unknown>) => props.visible === false ? null : h.node('dialog', props, props.children, h.node('button', { onClick: props.onConfirm, disabled: props.pending, children: 'Confirm' }), h.node('button', { onClick: props.onCancel, children: 'Cancel' })) }));
vi.mock('../../apps/mobile/lib/mobile-context', () => ({ useMobile: () => h.mobile }));
vi.mock('../../apps/mobile/lib/training', () => ({ loadTraining: h.load, loadTrainingHistory: vi.fn(async () => ({ data: [], error: null })) }));
vi.mock('../../apps/mobile/components/ui', () => Object.fromEntries(['Body', 'Status', 'ActionButton', 'Row', 'Sheet', 'SheetHeader', 'EmptyState', 'ErrorRetry', 'LoadingState', 'LedgerSection', 'StateMessage'].map(name => [name, (props: Record<string, unknown>) => h.node(name, props)])));

const base: PtSession = { sessionId: '44444444-4444-4444-8444-444444444444', orderId: '55555555-5555-4555-8555-555555555555', programmeName: 'Recorded training', trainerKey: '66666666-6666-4666-8666-666666666666', trainerName: 'Asha', startsAt: '2026-10-05T18:15:00Z', endsAt: '2026-10-05T19:30:00Z', timezone: 'Asia/Kolkata', status: 'booked', consumed: false, cancelledAt: null, cancelCutoff: '2026-10-05T12:15:00Z', lateNow: false, consumesNow: false, canCancel: true };
let current: PtSession | null;
let scope = 'caller-a';
const settle = async () => { for (const unused of Array.from({ length: 12 })) { void unused; await Promise.resolve(); h.paint(); } };
const press = async (caption: RegExp) => {
  const button = h.walk(h.tree()).find(item => (typeof item.props.onPress === 'function' || typeof item.props.onClick === 'function') && caption.test(h.words(item)) && item.props.disabled !== true);
  expect(button, `enabled action ${caption}`).toBeDefined();
  const action = button?.props.onPress ?? button?.props.onClick;
  await (action as () => unknown)(); await settle();
};
const displayed = () => {
  const confirmation = h.walk(h.tree()).find(item => item.type === 'dialog' || item.type === 'Sheet');
  expect(confirmation, 'current cancellation confirmation').toBeDefined();
  return h.words(confirmation).replace(/\s+/g, ' ');
};
const duration = (minutes: string, seconds?: string) => {
  const text = displayed();
  if (seconds) expect(text).toMatch(new RegExp(`(?:${minutes}\\.5\\s*(?:min|minute)|${minutes}\\s*(?:min|minute)[^\\d]{0,20}${seconds}\\s*(?:s\\b|sec|second)|1\\s*(?:h\\b|hour)[^\\d]{0,20}30\\s*(?:min|minute)[^\\d]{0,20}${seconds}\\s*(?:s\\b|sec|second))`, 'i'));
  else if (minutes === '120') expect(text).toMatch(/(?:120\s*(?:min|minute)|2\s*(?:h\b|hour))/i);
  else expect(text).toMatch(new RegExp(`(?:${minutes}\\s*(?:min|minute)|1\\s*(?:h\\b|hour)[^\\d]{0,20}15\\s*(?:min|minute))`, 'i'));
};
const localClock = (iso: string) => {
  const date = new Date(iso);
  const text = displayed().toLowerCase();
  const clock = new Intl.DateTimeFormat('en-IN', { timeZone: 'Asia/Kolkata', hour: 'numeric', minute: '2-digit', hour12: true }).format(date).toLowerCase().replace(/\s+/g, ' ');
  const clock24 = new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Kolkata', hour: '2-digit', minute: '2-digit', hour12: false }).format(date);
  expect(text.includes(clock) || text.includes(clock24), `local clock ${clock}`).toBe(true);
};
beforeEach(() => {
  vi.useFakeTimers(); vi.setSystemTime(new Date('2026-10-03T00:00:00Z'));
  current = { ...base }; scope = 'caller-a'; h.mobile.identity.memberId = '33333333-3333-4333-8333-333333333333';
  h.load.mockReset().mockImplementation(async () => ({ trainers: { data: [], error: null }, programmes: { data: [], error: null }, packs: { data: [], error: null }, history: { data: [], error: null }, upcoming: { data: current ? [current] : [], error: null } }));
  h.post.mockReset().mockResolvedValue({ ok: true, data: { sessionId: base.sessionId, status: 'cancelled_by_member', late: false, consumed: false, sessionsRemaining: 1, replayed: false } });
  h.fetch.mockReset().mockResolvedValue({ json: async () => ({ ok: true, data: { sessionId: base.sessionId, status: 'cancelled_by_member', late: false, consumed: false, sessionsRemaining: 1, replayed: false } }) });
  vi.stubGlobal('fetch', h.fetch); vi.stubGlobal('navigator', { onLine: true }); vi.stubGlobal('window', { addEventListener: vi.fn(), removeEventListener: vi.fn() });
});
describe.each(['web', 'native'] as const)('%s held recorded cancellation interval', platform => {
  const mount = async () => {
    if (platform === 'native') { const { TrainingSection } = await import('../../apps/mobile/components/training-section'); h.mount(() => TrainingSection()); }
    else { const { PtCancelButton } = await import('../../apps/web/app/member/classes/training/pt-actions'); h.mount(() => PtCancelButton({ session: base, scopeKey: scope, nouns: h.nouns, refreshSession: async () => current })); }
    h.paint(); await settle();
  };
  const sends = () => platform === 'native' ? h.post : h.fetch;
  it.each([
    { end: '2026-10-05T19:30:00Z', minutes: '75', seconds: undefined },
    { end: '2026-10-05T20:15:00Z', minutes: '120', seconds: undefined },
    { end: '2026-10-05T19:45:30Z', minutes: '90', seconds: '30' },
  ])('shows exact stored duration and both local clocks ($minutes minutes)', async ({ end, minutes, seconds }) => {
    current = { ...base, endsAt: end }; await mount(); await press(/cancel/i);
    duration(minutes, seconds); localClock(base.startsAt); localClock(end);
    expect(displayed()).toMatch(/(?:5|05).*oct|oct.*(?:5|05)/i); expect(displayed()).toMatch(/(?:6|06).*oct|oct.*(?:6|06)/i);
    expect(sends()).not.toHaveBeenCalled();
  });
  it.each(['invalid', '', base.startsAt, '2026-10-05T18:14:59Z'])('unusable current interval cannot authorize a command (%s)', async end => {
    await mount(); current = { ...base, endsAt: end }; await press(/cancel/i);
    const confirm = h.walk(h.tree()).find(item => /confirm/i.test(h.words(item)) && (typeof item.props.onPress === 'function' || typeof item.props.onClick === 'function') && item.props.disabled !== true);
    if (confirm) { await ((confirm.props.onPress ?? confirm.props.onClick) as () => unknown)(); await settle(); }
    expect(sends()).not.toHaveBeenCalled();
  });
  it('changed end renews duration and requires another explicit confirmation', async () => {
    await mount(); await press(/cancel/i); current = { ...base, endsAt: '2026-10-05T20:15:00Z' };
    await press(/confirm/i); expect(sends()).not.toHaveBeenCalled(); duration('120'); localClock(current.endsAt);
    await press(/confirm/i); expect(sends()).toHaveBeenCalledTimes(1);
    if (platform === 'native') expect(h.post).toHaveBeenCalledWith('/api/member/pt-bookings/cancel', { sessionId: base.sessionId });
    else expect(h.fetch.mock.calls[0]?.[0]).toBe('/api/member/pt-bookings/cancel');
  });
  it.each(['invalid', ''])('missing or invalid start refuses confirmation (%s)', async startsAt => {
    await mount(); current = { ...base, startsAt }; await press(/cancel/i);
    const confirm = h.walk(h.tree()).find(item => /confirm/i.test(h.words(item)) && (typeof item.props.onPress === 'function' || typeof item.props.onClick === 'function') && item.props.disabled !== true);
    if (confirm) { await ((confirm.props.onPress ?? confirm.props.onClick) as () => unknown)(); await settle(); }
    expect(sends()).not.toHaveBeenCalled();
  });
  it.each([false, true])('duration preserves current late consequence and absolute cutoff (consumes=%s)', async consumes => {
    current = { ...base, lateNow: true, consumesNow: consumes }; await mount(); await press(/cancel/i);
    duration('75'); localClock(base.cancelCutoff as string); expect(displayed()).toMatch(/late/i);
    expect(displayed()).toMatch(consumes ? /(?:used|uses|consume)/i : /(?:not|no|free|kept|returned|remaining)/i);
    expect(sends()).not.toHaveBeenCalled();
  });
  it('wrong session cannot revive the displayed interval', async () => {
    await mount(); await press(/cancel/i); current = { ...base, sessionId: '77777777-7777-4777-8777-777777777777' }; await press(/confirm/i);
    expect(sends()).not.toHaveBeenCalled();
  });
  it('A to B to A cannot revive a retained confirmation handler', async () => {
    await mount(); await press(/cancel/i);
    const confirm = h.walk(h.tree()).find(item => /confirm/i.test(h.words(item)) && (typeof item.props.onPress === 'function' || typeof item.props.onClick === 'function'));
    expect(confirm).toBeDefined(); const old = (confirm?.props.onPress ?? confirm?.props.onClick) as () => unknown;
    scope = 'caller-b'; h.mobile.identity = { ...h.mobile.identity, memberId: '88888888-8888-4888-8888-888888888888' }; h.paint(); await settle();
    scope = 'caller-a'; h.mobile.identity = { ...h.mobile.identity, memberId: '33333333-3333-4333-8333-333333333333' }; h.paint(); await settle();
    await old(); await settle(); expect(sends()).not.toHaveBeenCalled();
  });
});
