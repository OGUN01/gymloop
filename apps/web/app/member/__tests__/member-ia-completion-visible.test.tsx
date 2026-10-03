import { renderToStaticMarkup } from 'react-dom/server';
import { businessNouns } from '@gymloop/shared';
import { beforeEach, describe, expect, it, vi } from 'vitest';
vi.mock('../../../lib/identity-session', () => ({ requireAudience: async () => ({ identity: { kind: 'member', userId: 'ia-user', tenantId: 'ia-tenant', memberId: 'ia-member' }, supabase: {} }) }));
vi.mock('../../../lib/business-type', () => ({ loadBusinessNouns: async () => businessNouns('gym'), loadBusinessOrganization: async () => ({ name: 'IA Fitness', timezone: 'Asia/Kolkata', business_type: 'gym' }) }));
vi.mock('../../../lib/training', () => ({ loadMemberTraining: async () => ({ trainers: { data: [{ trainerKey: 'ia-trainer', displayName: 'IA Coach', qualification: 'Recorded qualification', bio: 'Recorded bio', specialities: [], imageUrl: null, branchName: 'North', isProfileListed: true }], error: null }, programmes: { data: [], error: null }, packs: { data: [], error: null }, upcoming: { data: [], error: null }, history: { data: [], error: null } }), loadMemberTrainingHistory: async () => ({ data: [], error: null }) }));
vi.mock('../../../lib/shop', () => ({ loadMemberShop: async () => ({ items: [], reservations: [], truncated: false, serverTime: '2026-10-03T06:00:00Z' }) }));
const state = vi.hoisted(() => ({ failed: false, moneyFailed: false }));
vi.mock('../../../lib/member-portal', () => ({ loadMemberPortal: async () => ({
  errorMessage: state.failed ? 'Unable to load your membership. Try again.' : null,
  nouns: businessNouns('gym'), businessType: 'gym',
  member: { full_name: 'IA Member', member_code: 'IA101', email: 'ia@example.test', phone: '+917000000101', weekly_goal_visits: 3, rest_days: [] },
  gym: { name: 'IA Fitness', gym_code: 'IA-GYM', timezone: 'Asia/Kolkata', branchName: 'North', branchAddress: 'Recorded address', city: 'Mumbai', state: 'MH' },
  membership: { planName: 'Recorded annual', status: 'active', startsOn: '2026-10-01', endsOn: '2027-09-30' },
  visits: [], weekVisits: 0, weeklyGoal: 3, weekStart: '2026-09-28', streak: { current: 0, unit: 'week', rule: 'weekly_goal' },
  receipts: state.moneyFailed ? null : [{ id: 'receipt-ia', amountPaise: '9007199254740993', currency: 'INR', paidAt: '2026-10-01T06:00:00Z', receiptNumber: 'IA/101', status: 'paid' }],
  addOns: [], latestMessage: null,
}) }));
vi.mock('../announcements-section', () => new Proxy({}, { get: (_target, name) => name === 'then' ? undefined : () => null, has: () => true }));
vi.mock('../../../lib/member-announcements', () => ({ loadMemberAnnouncementFeed: async () => ({ asOf: '2026-10-03T06:00:00Z', announcements: [] }) }));
vi.mock('../../../lib/auth-actions', () => ({ signOut: vi.fn() }));
vi.mock('next-themes', () => ({ useTheme: () => ({ theme: 'system', setTheme: vi.fn() }) }));
vi.mock('next/navigation', () => ({ useRouter: () => ({ refresh: vi.fn(), push: vi.fn() }), useSearchParams: () => new URLSearchParams(), usePathname: () => '/member', redirect: vi.fn(), notFound: vi.fn() }));
beforeEach(() => { state.failed = false; state.moneyFailed = false; });
const pages = { home: () => import('../page'), you: () => import('../you/page'), gym: () => { const path = '../gym/page'; return import(path) as Promise<{ default: () => Promise<import('react').ReactNode> }>; }, alias: () => import('../my-gym/page') };
async function render(name: keyof typeof pages) { return renderToStaticMarkup(await (await pages[name]()).default()); }
describe('frozen member IA completion public web pages', () => {
  it('Home business name opens canonical Gym and membership opens its fragment', async () => {
    const html = await render('home');
    expect(html).toMatch(/<a[^>]*href="\/member\/gym"[^>]*>[\s\S]*?IA Fitness[\s\S]*?<\/a>/);
    expect(html).toContain('href="/member/gym#membership"');
  });
  it('You provides canonical business and membership destinations', async () => {
    const html = await render('you'); expect(html).toContain('href="/member/gym"'); expect(html).toContain('href="/member/gym#membership"');
  });
  it.each(['gym', 'alias'] as const)('%s retains membership facts and exposes distinct feature/history/legal entries', async name => {
    const html = await render(name); expect(html).toContain('id="membership"');
    for (const value of ['IA Fitness', 'Recorded annual', 'IA-GYM', 'North', 'Recorded address', 'IA/101']) expect(html).toContain(value);
    expect(html.replaceAll(',', '')).toContain('90071992547409.93');
    for (const href of ['/member/plans', '/member/classes/training#trainers', '/member/shop#services', '/member/add-ons', '/member/messages', '/member/activity', '/privacy', '/terms']) expect(html).toContain(`href="${href}"`);
    expect(html).toMatch(/Trainers &amp; programmes/i); expect(html).toContain('Other services'); expect(html).toMatch(/Orders.*completed returns/i);
  });
  it('compatibility alias renders the same canonical page without redirects', async () => { expect(await render('alias')).toBe(await render('gym')); });
  it.each(['gym', 'alias'] as const)('%s keeps failed receipt reads distinct from successful absence', async name => {
    state.moneyFailed = true; const html = await render(name); expect(html).toMatch(/could not|unable|unavailable|try again|retry/i); expect(html).not.toContain('IA/101'); expect(html).not.toMatch(/no receipts|no payments/i);
  });
  it('Training trainers destination has a stable anchor on its actual section', async () => { const { default: Page } = await import('../classes/training/page'); const html = renderToStaticMarkup(await Page({ searchParams: Promise.resolve({}) })); expect(html).toContain('id="trainers"'); expect(html).toContain('IA Coach'); });
  it('Shop preserves an addressable honest empty services section', async () => { const { default: Page } = await import('../shop/page'); const html = renderToStaticMarkup(await Page({ searchParams: Promise.resolve({}) })); expect(html).toContain('id="services"'); expect(html).toMatch(/no services|services.*(?:yet|available)|hasn.*added/i); });
  it('failed portal does not invent successful membership facts', async () => { state.failed = true; const html = await render('gym'); expect(html).toMatch(/unable|try again/i); expect(html).not.toContain('Recorded annual'); });
});
