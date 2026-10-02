import { createElement, isValidElement, type ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { businessNouns } from '@gymloop/shared';
import { beforeEach, describe, expect, it, vi } from 'vitest';
const state = vi.hoisted(() => ({ count: 4, fail: false, calls: 0 }));
const cards = () => Array.from({ length: state.count }, (_, index) => ({ announcementId: `75000000-0000-4000-8000-${String(index + 201).padStart(12, '0')}`, kind: index === 0 ? 'transactional' : 'promotional', title: `Notice ${index + 1}`, body: 'Plain text <script>no markup</script> https://example.test', imageUrl: null, versionNo: index === 0 ? 2 : 1, publishedAt: '2026-10-02T00:00:00Z', editedAt: index === 0 ? '2026-10-02T01:00:00Z' : null, expiresAt: null, changeNote: index === 0 ? 'Opening time corrected' : null, readState: index === 0 ? 'updated' : 'unread', readAt: null }));
vi.mock('../../lib/member-announcements', () => ({ loadMemberAnnouncementFeed: async () => { state.calls++; if (state.fail) throw new Error('PRIVATE SQL detail'); return { asOf: '2026-10-02T01:30:00Z', announcements: cards() }; } }));
vi.mock('../../lib/member-portal', () => ({ loadMemberPortal: async () => ({ errorMessage: null, nouns: businessNouns('dance'), businessType: 'dance', member: { full_name: 'Aarav Sharma', member_code: '75' }, gym: { name: 'ANC Academy', gym_code: 'ANC75A', business_type: 'dance', timezone: 'Asia/Kolkata', branchName: 'Main' }, membership: null, visits: [], weekStart: '2026-09-28', weekVisits: 0, weeklyGoal: 3, streak: { current: 0, unit: 'week', rule: 'weekly_goal' }, latestMessage: null }) }));
const db = { from: () => { const result = { data: { business_type: 'dance', timezone: 'Asia/Kolkata' }, error: null }; const chain = { select: () => chain, eq: () => chain, maybeSingle: async () => result }; return chain; } };
vi.mock('../../lib/identity-session', () => ({ requireAudience: async () => ({ supabase: db, identity: { kind: 'member', userId: '75000000-0000-4000-8000-000000000906', tenantId: '75000000-0000-4000-8000-000000000001', memberId: '75000000-0000-4000-8000-000000000101' } }) }));
vi.mock('../../lib/business-type', () => ({ loadBusinessType: async () => 'dance', loadBusinessNouns: async () => businessNouns('dance') }));
// Resolve only server async nodes; client hooks remain under React's renderer.
const resolveServer = async (node: ReactNode): Promise<ReactNode> => {
  if (Array.isArray(node)) return Promise.all(node.map(resolveServer));
  if (!isValidElement(node)) return node;
  if (typeof node.type === 'function' && node.type.constructor.name === 'AsyncFunction') return resolveServer(await (node.type as (props: unknown) => Promise<ReactNode>)(node.props));
  const props = node.props as { children?: ReactNode };
  return createElement(node.type, { ...props }, await resolveServer(props.children));
};
const render = async () => { const { default: Page } = await import('../member/page'); return renderToStaticMarkup(await resolveServer(await Page())); };
beforeEach(() => { state.count = 4; state.fail = false; state.calls = 0; });
describe('ANC-020 Home inline announcement section', () => {
  it('initially offers three calm expandable cards and Show all without a read command', async () => {
    const fetch = vi.fn(); vi.stubGlobal('fetch', fetch);
    try {
      const html = await render(); expect(html).toContain('From your academy'); expect(html).toContain('Show all 4');
      expect(html).toContain('Notice 1'); expect(html).toContain('Notice 3'); expect(html).not.toContain('Notice 4');
      expect((html.match(/aria-expanded="false"/g) ?? []).length).toBeGreaterThanOrEqual(3);
      expect(html).toContain('Updated'); expect(html).toContain('New'); expect(html).toContain('Edited');
      expect(html).not.toContain('<script>'); expect(html).not.toContain('href="https://example.test"'); expect(fetch).not.toHaveBeenCalled();
    } finally { vi.unstubAllGlobals(); }
  });
  it('empty section is absent and Home check-in remains', async () => {
    state.count = 0; const html = await render(); expect(html).not.toContain('From your academy'); expect(html).toContain('/member/check-in');
  });
  it('feed failure has one inline retry sentence and leaves Home usable', async () => {
    state.fail = true; const html = await render(); expect(html).toContain('Announcements couldn&#x27;t be loaded. Try again.'); expect(html).toContain('/member/check-in'); expect(html).not.toContain('PRIVATE SQL');
  });
});
