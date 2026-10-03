// Independent rendered saved-copy regressions from the frozen ANC public packet.
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { businessNouns } from '@gymloop/shared';
import { AnnouncementsSection } from '../../components/announcements';
type Props = Record<string, unknown>;
type Node = { type: unknown; props: Props };
type Slot = { value?: unknown; deps?: readonly unknown[] | undefined; cleanup?: (() => void) | undefined };
const seam = vi.hoisted(() => ({ stores: new Map<string, Slot[]>(), path: '', cursor: 0, effects: [] as Array<() => void> }));
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

vi.mock('../mobile-context', () => ({ useMobile: () => ({ identity: { kind: 'member', tenantId: 'saved-tenant', userId: 'saved-user', memberId: 'saved-member' }, nouns: businessNouns('gym'), palette: {} }) }));
vi.mock('../use-business-nouns', () => ({ useBusinessNouns: () => businessNouns('gym') }));
vi.mock('react-native', () => ({ Image: 'Image', Text: 'Text', View: 'View' }));
vi.mock('../../components/ui', () => {
  const host = (type: string) => (props: Props) => ({ type, props });
  return { ActionButton: host('ActionButton'), Body: host('Body'), Eyebrow: host('Eyebrow'), FONT: {}, Row: host('Row'), StateMessage: host('StateMessage'), Status: host('Status') };
});
type Feed = Parameters<typeof AnnouncementsSection>[0]['feed'];
const card = { announcementId: '75000000-0000-4000-8000-000000000301', kind: 'transactional' as const,
  title: 'Tomorrow opening time', body: 'Doors open at seven. Bring your membership card.', imageUrl: null,
  versionNo: 3, publishedAt: '2026-10-02T00:00:00Z', editedAt: null, expiresAt: null, changeNote: null,
  readState: 'unread' as const, readAt: null };
const fetchedAt = '2026-10-02T01:30:00Z';
const reload = vi.fn(async () => {}); const markRead = vi.fn(async () => {});
let feed: Feed; let nodes: Node[];
function visit(value: unknown, path: string): void {
  if (Array.isArray(value)) { value.forEach((child, index) => visit(child, path + '/' + index)); return; }
  if (value === null || typeof value !== 'object' || !('type' in value) || !('props' in value)) return;
  const node = value as Node;
  if (typeof node.type === 'function') {
    const prior = seam.path; const cursor = seam.cursor; seam.path = path; seam.cursor = 0;
    const output: unknown = node.type(node.props); seam.path = prior; seam.cursor = cursor;
    visit(output, path + '/render'); return;
  }
  nodes.push(node);
  for (const key of ['children', 'title', 'meta', 'status', 'expanded']) visit(node.props[key], path + '/' + key);
}
function draw() { nodes = []; visit({ type: AnnouncementsSection, props: { feed, timezone: 'Asia/Kolkata' } }, 'root'); seam.effects.splice(0).forEach(effect => effect()); }
function words(value: unknown): string {
  if (typeof value === 'string' || typeof value === 'number') return String(value);
  if (Array.isArray(value)) return value.map(words).join(' ');
  if (value !== null && typeof value === 'object' && 'props' in value) return words((value as Node).props.children);
  return '';
}
function text() { return nodes.map(node => ['children', 'title', 'meta', 'detail', 'message'].map(key => words(node.props[key])).join(' ')).join(' '); }
function button(label: RegExp) { return nodes.find(node => [node.props.children, node.props.title, node.props.accessibilityLabel].some(value => label.test(words(value))) && typeof node.props.onPress === 'function'); }
async function press(label: RegExp) { const node = button(label); expect(node).toBeDefined(); if (typeof node?.props.onPress === 'function') await node.props.onPress(); draw(); }
beforeEach(() => {
  seam.stores.forEach(slots => slots.forEach(slot => slot.cleanup?.())); seam.stores.clear(); seam.effects = []; vi.clearAllMocks();
  feed = { cards: [card], stale: false, fetchedAt, loading: false, error: null, reload, markRead }; nodes = [];
});
describe('ANC actual native saved-copy rendering', () => {
  it.each(['Could not refresh announcements. Please try again.', 'You are offline. Try again when back online.'])('keeps saved cards, timestamp and retry reachable alongside %s', async error => {
    feed = { ...feed, stale: true, error }; draw();
    expect(text()).toContain(card.title); expect(text()).toContain('Saved copy');
    expect(text()).toMatch(/2 Oct|Oct 2|02 Oct|2\/10\/2026/); expect(text()).toMatch(/7:00|07:00/);
    expect(text()).toContain(error); expect(button(/Try again/i)).toBeDefined();
    expect(markRead).not.toHaveBeenCalled();
    await press(/Tomorrow opening time/);
    expect(text()).toContain(card.body);
    expect(markRead).toHaveBeenCalledWith(card.announcementId, card.versionNo);
    await press(/Try again/i); expect(reload).toHaveBeenCalledTimes(1);
  });
  it('renders only refused feedback and retry when the authoritative feed has no cards', async () => {
    feed = { ...feed, cards: [], stale: false, fetchedAt: null, error: 'You do not have permission to do this.' }; draw();
    expect(text()).toContain(feed.error); expect(text()).not.toContain('Saved copy');
    expect(button(/Tomorrow opening time/)).toBeUndefined(); expect(text()).not.toContain(card.body);
    expect(markRead).not.toHaveBeenCalled(); await press(/Try again/i); expect(reload).toHaveBeenCalledTimes(1);
  });
  it('keeps ordinary healthy cards expandable without saved-copy or failure feedback', async () => {
    draw(); expect(text()).toContain(card.title); expect(text()).not.toContain('Saved copy');
    expect(button(/Try again/i)).toBeUndefined(); await press(/Tomorrow opening time/);
    expect(text()).toContain(card.body); expect(markRead).toHaveBeenCalledWith(card.announcementId, card.versionNo);
  });
  it('retains the established saved-copy timestamp without a refresh error', () => {
    feed = { ...feed, stale: true }; draw();
    expect(text()).toContain(card.title); expect(text()).toContain('Saved copy');
    expect(text()).toMatch(/2 Oct|Oct 2|02 Oct|2\/10\/2026/); expect(text()).toMatch(/7:00|07:00/);
  });
  it('keeps an empty healthy section absent with no receipt or retry control', () => {
    feed = { ...feed, cards: [], fetchedAt: null }; draw();
    expect(button(/Try again/i)).toBeUndefined(); expect(text()).not.toContain('Saved copy');
    expect(text()).not.toContain(card.title); expect(markRead).not.toHaveBeenCalled();
  });
});
