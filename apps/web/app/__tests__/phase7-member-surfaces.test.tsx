import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';

const portal = {
  errorMessage: null,
  member: { full_name: 'Aarav Sharma' },
  gym: { name: 'Iron Box Fitness', branchName: 'Vijay Nagar', gym_code: 'IRNBX1', branchAddress: '12 Main Road', city: 'Indore', state: 'MP', timezone: 'Asia/Kolkata' },
  membership: { status: 'active', endsOn: '2026-09-30', planName: 'Monthly' },
  visits: [
    { id: 'visit-1', checked_in_at: '2026-09-14T04:30:00Z', source: 'qr' },
    { id: 'visit-2', checked_in_at: '2026-09-16T04:30:00Z', source: 'qr' },
  ],
  weekVisits: 2,
  weeklyGoal: 4,
  latestMessage: null,
} as const;

vi.mock('../../lib/member-portal', () => ({ loadMemberPortal: vi.fn(async () => portal) }));

describe('Phase 7 member surfaces', () => {
  it('makes Home action dominant and exposes a truthful seven-day week row', async () => {
    const page = (await import('../member/page')).default;
    const html = renderToStaticMarkup(await page());
    expect(html).toMatch(/class="[^"]*member-primary-action--dominant[^"]*"/);
    expect(html).toContain('Scan to check in');
    expect((html.match(/class="member-week-day"/g) ?? []).length).toBe(7);
    expect(html).toContain('2 / 4');
  });

  it('keeps the approved check-in action prominent on My gym', async () => {
    const page = (await import('../member/my-gym/page')).default;
    const html = renderToStaticMarkup(await page());
    expect(html).toContain('Scan to check in');
    expect(html).toMatch(/(?:href="\/member\/check-in"[^>]*class|class="[^"]*member-primary-action[^"]*"[^>]*href="\/member\/check-in")/);
  });
});
