// Independent rendered holdout: approved public contracts, never implementation/visible tests.
import { createElement, type ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { AnnouncementsSection } from '../../apps/mobile/components/announcements';
import type { useAnnouncements } from '../../apps/mobile/lib/use-announcements';

type Feed = ReturnType<typeof useAnnouncements>;
type Press = { label: string; expanded: boolean | undefined; press: () => unknown };
type HostProps = { children?: ReactNode; title?: string; meta?: ReactNode; status?: ReactNode; onPress?: () => unknown; expanded?: boolean; accessibilityLabel?: string };
const h = vi.hoisted(() => ({ cells: [] as unknown[], cursor: 0, presses: [] as Press[] }));
vi.mock('react', async original => ({
  ...await original<Record<string, unknown>>(),
  useState: (initial: unknown) => {
    const index = h.cursor++;
    if (!(index in h.cells)) h.cells[index] = typeof initial === 'function' ? initial() : initial;
    return [h.cells[index], (value: unknown) => { h.cells[index] = typeof value === 'function' ? value(h.cells[index]) : value; }];
  },
}));
vi.mock('react-native', async () => {
  const { createElement: element } = await import('react');
  return { View: ({ children }: HostProps) => element('div', null, children), Text: ({ children }: HostProps) => element('span', null, children), Image: () => element('img', { alt: '' }) };
});
vi.mock('../../apps/mobile/lib/mobile-context', () => ({ useMobile: () => ({
  identity: { kind: 'member', tenantId: '77950000-0000-4000-8000-000000000001', userId: '77950000-0000-4000-8000-000000000002', memberId: '77950000-0000-4000-8000-000000000003' },
  nouns: { place: 'gym', member: 'member', members: 'members', class: 'class', classes: 'classes' },
  palette: { secondaryText: '#666666' },
}) }));
vi.mock('../../apps/mobile/components/ui', async () => {
  const { createElement: element } = await import('react');
  const text = ({ children }: HostProps) => element('span', null, children);
  return {
    FONT: { regular: 'held-font' }, Body: text, Eyebrow: text, Status: text,
    Row: ({ title, meta, status, onPress, expanded, accessibilityLabel }: HostProps) => {
      if (onPress) h.presses.push({ label: accessibilityLabel ?? title ?? '', expanded, press: onPress });
      return element('div', null, element('button', { 'aria-label': accessibilityLabel ?? title, 'aria-expanded': expanded }, title), meta, status);
    },
    ActionButton: ({ children, onPress }: HostProps) => {
      if (onPress) h.presses.push({ label: String(children), expanded: undefined, press: onPress });
      return element('button', null, children);
    },
    StateMessage: ({ children }: HostProps) => element('div', { role: 'status' }, children),
  };
});

const announcementId = '77950000-0000-4000-8000-000000000050';
const savedAt = '2026-10-03T06:17:00Z';
const card: Feed['cards'][number] = {
  announcementId, kind: 'transactional', title: 'Held closure for maintenance',
  body: 'The training floor closes Sunday.\nThe full announcement explains that it opens again Monday morning.',
  imageUrl: null, versionNo: 1, publishedAt: '2026-10-02T06:00:00Z',
  editedAt: null, changeNote: null, expiresAt: null, readAt: null, readState: 'unread',
};
function feed(overrides: Partial<Feed> = {}): Feed {
  return { cards: [card], loading: false, error: null, stale: false, fetchedAt: savedAt, reload: vi.fn(async () => undefined), markRead: vi.fn(async () => undefined), ...overrides };
}
function render(value: Feed) {
  h.cursor = 0; h.presses = [];
  return renderToStaticMarkup(createElement(AnnouncementsSection, { feed: value, timezone: 'Asia/Kolkata' }));
}
function press(label: string) {
  const control = h.presses.find(item => item.label === label);
  expect(control, `reachable native control: ${label}`).toBeDefined();
  return control!.press();
}
beforeEach(() => { h.cells = []; h.cursor = 0; h.presses = []; });

describe('ANC approved saved-copy feedback actual rendered native section', () => {
  it.each([
    { name: 'server or malformed refresh', error: 'Announcements could not be refreshed. Try again.' },
    { name: 'unknown network refresh', error: 'Announcements could not be refreshed. Try again.' },
    { name: 'confirmed unreachable refresh', error: 'Announcements will appear when you\u0027re back online.' },
  ])('$name keeps saved cards, timestamp and actionable failure simultaneously', async ({ name, error }) => {
    const value = feed({ stale: true, error });
    const html = render(value);
    expect(html).toContain(card.title);
    expect(html).toContain('Saved copy');
    // The saved instant is 11:47 gym-local time; a date without its fetch time is insufficient.
    expect(html).toMatch(/11:47/);
    expect(html).toContain(error.replaceAll("'", '&#x27;'));
    expect(html).toContain('Try again');
    if (name !== 'confirmed unreachable refresh') expect(html).not.toMatch(/offline|back online/i);
    expect(h.presses.find(item => item.label === card.title)?.expanded).toBe(false);
    await press(card.title);
    const expanded = render(value);
    expect(expanded).toContain('The full announcement explains that it opens again Monday morning.');
    expect(h.presses.find(item => item.label === card.title)?.expanded).toBe(true);
    expect(value.markRead).toHaveBeenCalledWith(announcementId, card.versionNo);
    expect(expanded).toContain('Saved copy'); expect(expanded).toContain('Try again');
    await press('Try again'); expect(value.reload).toHaveBeenCalledTimes(1);
  });

  it.each(['Please sign in again to see announcements.', 'You do not have permission to see announcements.'])('definitive refusal renders only sanitized retry state: %s', async error => {
    const value = feed({ cards: [], error, stale: false, fetchedAt: null });
    const html = render(value);
    expect(html).toContain(error); expect(html).toContain('Try again');
    expect(html).not.toContain(card.title); expect(html).not.toContain('Saved copy');
    expect(html).not.toMatch(/offline|back online/i);
    expect(h.presses.map(item => item.label)).not.toContain(card.title);
    expect(value.markRead).not.toHaveBeenCalled();
    await press('Try again'); expect(value.reload).toHaveBeenCalledTimes(1); expect(value.markRead).not.toHaveBeenCalled();
  });

  it('a failed first load has feedback and retry without invented saved cards or time', async () => {
    const value = feed({ cards: [], error: 'Announcements could not be refreshed. Try again.', fetchedAt: null });
    const html = render(value);
    expect(html).toContain(value.error); expect(html).toContain('Try again');
    expect(html).not.toContain('Saved copy'); expect(html).not.toContain(card.title); expect(html).not.toContain('11:47');
    await press('Try again'); expect(value.reload).toHaveBeenCalledTimes(1); expect(value.markRead).not.toHaveBeenCalled();
  });

  it('healthy cards remain expandable and acknowledge the exact version with no saved/error feedback', async () => {
    const value = feed(); const html = render(value);
    expect(html).toContain(card.title); expect(html).not.toContain('Saved copy'); expect(html).not.toContain('Try again');
    await press(card.title); expect(render(value)).toContain('The full announcement explains that it opens again Monday morning.');
    expect(value.markRead).toHaveBeenCalledWith(announcementId, card.versionNo);
  });

  it('the ordinary offline saved-card path retains its gym-local time and expansion', async () => {
    const value = feed({ stale: true }); const html = render(value);
    expect(html).toContain(card.title); expect(html).toContain('Saved copy'); expect(html).toMatch(/11:47/);
    await press(card.title); expect(render(value)).toContain('The full announcement explains that it opens again Monday morning.');
    expect(value.markRead).toHaveBeenCalledWith(announcementId, card.versionNo);
  });

  it('ordinary empty and loading feeds keep the announcement section absent', () => {
    expect(render(feed({ cards: [], fetchedAt: null }))).toBe('');
    expect(render(feed({ cards: [], loading: true, fetchedAt: null }))).toBe('');
  });
});
