import { beforeEach, expect, it, vi } from 'vitest';
import { createElement, isValidElement, type ReactNode } from 'react';
import { businessNouns, UI_TOKENS } from '@gymloop/shared';
const test = vi.hoisted(() => ({ cursor: 0, slots: [] as unknown[], effects: [] as Array<{ slot: number; callback: () => unknown }>, cleanups: [] as Array<(() => void) | undefined>, deps: [] as Array<unknown[] | undefined>, calls: [] as Array<{ path: string; body: unknown; resolve: (value: unknown) => void }>, identity: { kind: 'member', userId: '75000000-0000-4000-8000-000000000906', tenantId: '75000000-0000-4000-8000-000000000001', memberId: '75000000-0000-4000-8000-000000000101' }, offline: false }));
vi.mock('react', async (original) => {
  const actual = await original<typeof import('react')>();
  const changed = (old: unknown[] | undefined, next: unknown[] | undefined) => !old || !next || old.length !== next.length || old.some((value, index) => !Object.is(value, next[index]));
  const useState = (initial: unknown) => { const slot = test.cursor++; const slots = test.slots; if (!(slot in slots)) slots[slot] = typeof initial === 'function' ? (initial as () => unknown)() : initial; return [slots[slot], (next: unknown) => { if (slots !== test.slots) return; slots[slot] = typeof next === 'function' ? (next as (old: unknown) => unknown)(slots[slot]) : next; }]; };
  return { ...actual, useMemo: (make: () => unknown) => make(), useId: () => 'anc-lifetime', useState, useRef: (initial: unknown) => useState({ current: initial })[0],
    useReducer: (reducer: (old: unknown, event: unknown) => unknown, initial: unknown, init?: (value: unknown) => unknown) => { const slot = test.cursor++; const slots = test.slots; if (!(slot in slots)) slots[slot] = init ? init(initial) : initial; return [slots[slot], (event: unknown) => { if (slots === test.slots) slots[slot] = reducer(slots[slot], event); }]; },
    useCallback: (callback: unknown, deps: unknown[]) => { const slot = test.cursor++; if (changed(test.deps[slot], deps)) { test.slots[slot] = callback; test.deps[slot] = deps; } return test.slots[slot]; },
    useEffect: (callback: () => unknown, deps?: unknown[]) => { const slot = test.cursor++; if (changed(test.deps[slot], deps)) { test.deps[slot] = deps; test.effects.push({ slot, callback }); } },
  };
});
const host = (name: string) => (props: Record<string, unknown>) => createElement(name, props, props.children as ReactNode);
vi.mock('react-native', () => ({ View: host('view'), Text: host('text'), Pressable: host('pressable'), Image: host('image'), Platform: { OS: 'android', select: (choices: Record<string, unknown>) => choices.android ?? choices.default }, useWindowDimensions: () => ({ width: 390, height: 844, fontScale: 1, scale: 1 }), ActivityIndicator: host('loading'), StyleSheet: { create: (value: unknown) => value, hairlineWidth: 1 } }));
vi.mock('lucide-react-native', () => new Proxy({}, { get: (_target, name) => name === 'then' ? undefined : host(String(name)), has: () => true }));
vi.mock('react-native-svg', () => new Proxy({}, { get: (_target, name) => name === 'then' ? undefined : host(String(name)), has: () => true }));
vi.mock('expo-haptics', () => ({ impactAsync: vi.fn(async () => undefined), selectionAsync: vi.fn(async () => undefined), notificationAsync: vi.fn(async () => undefined), ImpactFeedbackStyle: { Light: 'light', Medium: 'medium' }, NotificationFeedbackType: { Success: 'success' } }));
vi.mock('expo-font', () => ({ useFonts: () => [true, null], isLoaded: () => true }));
// Unit semantic host seam only: real ANC component supplies the content.
// Row metadata stays single-line and cannot satisfy the body-preview assertion.
vi.mock('../../components/ui', () => new Proxy({}, {
  get: (_target, name) => name === 'then' ? undefined : name === 'FONT'
    ? new Proxy({}, { get: () => 'font' }) : name === 'Row'
      ? (props: Record<string, unknown>) => createElement('row', {
        accessibilityRole: 'button', accessibilityLabel: props.accessibilityLabel ?? props.title ?? props.label,
        accessibilityState: { expanded: props.expanded }, onPress: props.onPress ?? props.onToggle,
      }, createElement('text', { numberOfLines: 1 }, (props.meta ?? props.subtitle ?? props.detail) as ReactNode), props.children as ReactNode)
      : host(String(name)), has: () => true,
}));
vi.mock('../mobile-context', () => ({ useMobile: () => ({ palette: UI_TOKENS.colors.light, nouns: businessNouns('gym') }) }));
const { AnnouncementsSection } = await import('../../components/announcements');
const id = '75000000-0000-4000-8000-000000000201';
const card = { announcementId: id, kind: 'transactional' as const, title: 'Closure title', body: 'Distinct separate body preview', imageUrl: null, versionNo: 2, publishedAt: '2026-10-02T00:00:00Z', editedAt: '2026-10-02T01:00:00Z', expiresAt: null, changeNote: 'Changed time', readState: 'updated' as const, readAt: null };
const feed = { cards: [card], stale: false, fetchedAt: null, loading: false, error: null, reload: vi.fn(async () => undefined), markRead: vi.fn(async () => undefined) };
const nodes = (node: ReactNode): Array<Record<string, unknown>> => {
  if (Array.isArray(node)) return node.flatMap(nodes);
  if (!isValidElement<Record<string, unknown>>(node)) return [];
  if (typeof node.type === 'function') return nodes((node.type as (props: unknown) => ReactNode)(node.props));
  return [node.props, ...nodes(node.props.children as ReactNode)];
};
const text = (node: ReactNode): string => Array.isArray(node) ? node.map(text).join(' ') : isValidElement<Record<string, unknown>>(node) ? text(node.props.children as ReactNode) : typeof node === 'string' ? node : '';
const render = () => { test.cursor = 0; return nodes(createElement(AnnouncementsSection, { feed: feed as unknown as Parameters<typeof AnnouncementsSection>[0]['feed'], timezone: 'Asia/Kolkata' })); };
beforeEach(() => { test.slots = []; test.deps = []; test.cleanups = []; test.effects = []; });
it('ANC-Q3/Q9 native collapsed card gives a two-line body preview separately from metadata and title button', () => {
  const rendered = render();
  const preview = rendered.filter(node => text(node.children as ReactNode).includes(card.body) && node.numberOfLines === 2);
  expect(preview).toHaveLength(1);
  const control = rendered.find(node => node.accessibilityLabel === card.title && (node.accessibilityState as { expanded?: boolean } | undefined)?.expanded === false);
  expect(control).toBeDefined(); expect(control?.accessibilityRole).toBe('button'); expect(typeof (control?.onPress ?? control?.onToggle)).toBe('function');
  const open = (control?.onPress ?? control?.onToggle) as () => void; open();
  const expanded = render().find(node => node.accessibilityLabel === card.title && (node.accessibilityState as { expanded?: boolean } | undefined)?.expanded === true);
  expect(expanded).toBeDefined(); expect(feed.markRead).toHaveBeenCalledWith(id, 2);
});
