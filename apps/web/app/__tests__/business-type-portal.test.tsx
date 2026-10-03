import { renderToStaticMarkup } from 'react-dom/server';
import type { ReactNode } from 'react';
import { businessNouns } from '@gymloop/shared';
import { beforeEach, describe, expect, it, vi } from 'vitest';
const state = vi.hoisted(() => ({ type: 'gym' as 'gym' | 'dance', empty: false }));
const stored = 'Stored gym member trainer message';
const db = { from: (table: string) => {
  const result = { data: table === 'organizations' ? { name: 'BIZ Academy', gym_code: 'BIZ70A', timezone: 'Asia/Kolkata', business_type: state.type } : table === 'branches' ? { name: 'Main' } : [], error: null };
  const chain: Record<string, unknown> = { then: (resolve: (v: unknown) => unknown) => Promise.resolve(result).then(resolve) };
  for (const method of ['select', 'eq', 'in', 'is', 'order', 'limit', 'maybeSingle', 'single']) chain[method] = () => chain;
  return chain;
}, rpc: async () => ({ data: [], error: null }) };
vi.mock('../../lib/identity-session', () => ({ requireAudience: async () => ({ supabase: db, identity: { kind: 'member', userId: '70000000-0000-4000-8000-000000000906', tenantId: '70000000-0000-4000-8000-000000000001', memberId: '70000000-0000-4000-8000-000000000101' } }) }));
vi.mock('../../lib/business-type', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../lib/business-type')>()),
  loadBusinessType: async () => state.type, loadBusinessNouns: async () => businessNouns(state.type),
}));
vi.mock('../../lib/member-portal', () => ({ loadMemberPortal: async () => ({ errorMessage: null, nouns: businessNouns(state.type), businessType: state.type,
  member: { full_name: 'Aarav Sharma', email: 'aarav@example.test', phone: '+917000000101', member_code: 'BIZ-101' },
  gym: { name: 'BIZ Academy', gym_code: 'BIZ70A', business_type: state.type, businessType: state.type, timezone: 'Asia/Kolkata', branchName: 'Main', branchAddress: null, city: null, state: null },
  membership: { planName: 'Monthly', status: 'active', startsOn: '2026-10-01', endsOn: '2026-10-31' },
  visits: state.empty ? [] : [{ id: 'visit', checked_in_at: '2026-10-01T06:00:00Z', source: 'qr' }],
  weekStart: '2026-09-28', weekVisits: 1, weeklyGoal: 3, streak: { current: 1, unit: 'week', rule: 'weekly_goal' }, receipts: [], addOns: [], latestMessage: { id: 'notice', body: stored, status: 'sent', sentAt: '2026-10-01T06:00:00Z' },
}) }));
vi.mock('../../lib/member-messages', () => ({ loadMemberMessages: async () => ({ messages: [], consents: [], errorMessage: null, nouns: businessNouns(state.type) }) }));
vi.mock('../../lib/auth-actions', () => ({ signOut: vi.fn() }));
// ANC is an independent Home composition; keep BIZ pages and navigation real.
vi.mock('../../lib/member-announcements', () => ({ loadMemberAnnouncementFeed: async () => ({ asOf: '2026-10-03T00:00:00Z', announcements: [] }) }));
vi.mock('next-themes', () => ({ useTheme: () => ({ theme: 'system', setTheme: vi.fn() }) }));
vi.mock('next/navigation', () => ({ usePathname: () => '/member', redirect: vi.fn(), notFound: vi.fn() }));

const pages = {
  home: () => import('../member/page'), activity: () => import('../member/activity/page'),
  checkIn: () => import('../member/check-in/page'), gym: () => import('../member/my-gym/page'),
  messages: () => import('../member/messages/page'), you: () => import('../member/you/page'),
  addOns: () => import('../member/add-ons/page'),
};
const visible = (html: string) => {
  const labels = [...html.matchAll(/(?:aria-label|alt|title)="([^"]*)"/g)].map((match) => match[1]);
  return `${html.replace(/<[^>]*>/g, ' ')} ${labels.join(' ')}`.replaceAll(stored, '').replaceAll('&#x27;', "'").replaceAll('&amp;', '&');
};
beforeEach(() => { state.type = 'gym'; state.empty = false; });
describe('BIZ-012/013 Tier A rendered text and accessible names', () => {
  it.each(Object.keys(pages) as Array<keyof typeof pages>)('dance %s has no stray default nouns', async (name) => {
    state.type = 'dance'; const page = await pages[name](); const html = renderToStaticMarkup(await (page.default as (props: object) => Promise<ReactNode>)({}));
    expect(visible(html)).not.toMatch(/\b(?:gym|member|members|trainer)\b/i);
    if (name === 'home') expect(html).toContain(stored);
  });
  it('the empty activity sentence varies too', async () => {
    state.type = 'dance'; state.empty = true;
    const html = renderToStaticMarkup(await (await pages.activity()).default());
    expect(html).toContain('Your visits appear here once the academy confirms a check-in.');
  });
  it('gym wording stays exact on the specified legacy surfaces', async () => {
    const home = renderToStaticMarkup(await (await pages.home()).default());
    const activity = renderToStaticMarkup(await (await pages.activity()).default());
    const gym = renderToStaticMarkup(await (await pages.gym()).default());
    expect(home).toContain('Latest from your gym'); expect(home).toContain('aria-label="Your gym"');
    expect(activity).toContain('Gym QR'); expect(gym).toContain('Gym code');
  });
  it('member layout supplies place and accessibility nouns to navigation', async () => {
    state.type = 'dance'; const { default: Layout } = await import('../member/layout');
    const html = renderToStaticMarkup(await Layout({ children: 'Body' }));
    expect(visible(html)).not.toMatch(/\b(?:gym|member|members|trainer)\b/i);
    // Gym is secondary in the approved five-tab IA; place glyphs belong there.
    const links = [...html.matchAll(/<a\b([^>]*)>([\s\S]*?)<\/a>/g)].map((match): { attributes: string; text: string } => ({ attributes: match[1] ?? '', text: (match[2] ?? '').replace(/<[^>]*>/g, '').trim() }));
    expect(links.map((link) => link.text)).toEqual(['Home', 'Batches', 'Shop', 'Activity', 'You']);
    expect(links.map((link) => link.attributes.match(/href="([^"]+)"/)?.[1])).toEqual(['/member', '/member/classes', '/member/shop', '/member/activity', '/member/you']);
    expect(html).not.toMatch(/lucide-dumbbell/);
  });
});
