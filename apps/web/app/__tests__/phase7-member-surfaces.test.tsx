import { renderToStaticMarkup } from 'react-dom/server';
import { businessNouns } from '@gymloop/shared';
import { describe, expect, it, vi } from 'vitest';

const portal = {
  errorMessage: null,
  businessType: 'gym', nouns: businessNouns('gym'),
  member: { full_name: 'Aarav Sharma', member_code: 'CALL25-1', email: null, phone: '9876543210', weekly_goal_visits: 4, rest_days: [] },
  gym: { name: 'Iron Box Fitness', branchName: 'Vijay Nagar', gym_code: 'IRNBX1', branchAddress: '12 Main Road', city: 'Indore', state: 'MP', timezone: 'Asia/Kolkata' },
  membership: { startsOn: '2026-09-01', status: 'active', endsOn: '2026-09-30', planName: 'Monthly' },
  visits: [
    { id: 'visit-1', checked_in_at: '2026-09-14T04:30:00Z', source: 'qr' },
    { id: 'visit-2', checked_in_at: '2026-09-16T04:30:00Z', source: 'qr' },
  ],
  weekVisits: 2,
  weeklyGoal: 4,
  latestMessage: null,
  receipts: [], addOns: [], consents: [],
  weekStart: '2026-09-14', streak: { current: 0, unit: 'week', missed: [] },
} as const;

vi.mock('server-only', () => ({}));
vi.mock('next/navigation', () => ({ redirect: (path: string) => { throw new Error(`REDIRECT:${path}`); } }));
vi.mock('../../lib/supabase/server', () => ({ createServerSupabase: async () => ({
  auth: { getClaims: async () => ({ data: { claims: { sub: 'a6400000-0000-4000-8000-000000000001', role: 'authenticated', app_role: 'member', tenant_id: 'a6400000-0000-4000-8000-000000000002', member_id: 'a6400000-0000-4000-8000-000000000003' } }, error: null }) },
}) }));
vi.mock('../../lib/member-announcements', () => ({ loadMemberAnnouncementFeed: async () => ({ asOf: '2026-09-16T12:00:00Z', announcements: [] }) }));

vi.mock('../../lib/member-portal', () => ({ loadMemberPortal: vi.fn(async () => portal) }));

describe('Phase 7 member surfaces', () => {
  it('makes Home action dominant and exposes a truthful seven-day week row', async () => {
    const page = (await import('../member/page')).default;
    const html = renderToStaticMarkup(await page());
    expect(html).toMatch(/class="[^"]*member-primary-action--dominant[^"]*"/);
    expect(html).toContain('Scan to check in');
    expect((html.match(/class="member-week-day"/g) ?? []).length).toBe(7);
    // Chalkline (ADR-170): the week reads as a sentence, "2 of 4 visits this week".
    expect(html.replace(/<[^>]+>/g, ' ')).toMatch(/2\s+of\s+4\s+visits this week/);
  });

  it('keeps the approved check-in action prominent on canonical Gym and its historical alias', async () => {
    const page = (await import('../member/gym/page')).default;
    const alias = (await import('../member/my-gym/page')).default;
    expect(alias).toBe(page);
    const html = renderToStaticMarkup(await page());
    expect(html).toContain('Scan to check in');
    expect(html).toMatch(/(?:href="\/member\/check-in"[^>]*class|class="[^"]*member-primary-action[^"]*"[^>]*href="\/member\/check-in")/);
  });
});
