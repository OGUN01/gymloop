import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { businessNouns } from '@gymloop/shared';
import { describe, expect, it, vi } from 'vitest';
const query = vi.hoisted(() => vi.fn(() => { throw new Error('Gym row must not read plans'); }));
vi.mock('@gymloop/shared', async (load) => ({ ...await load<typeof import('@gymloop/shared')>(), readPlanCatalogue: query }));
vi.mock('next/navigation', () => ({ usePathname: () => '/member/plans' }));
vi.mock('../../lib/member-portal', () => ({ loadMemberPortal: async () => ({ errorMessage: null, nouns: businessNouns('gym'), businessType: 'gym', gym: { name: 'PLC Gym', gym_code: 'PLC71A', timezone: 'Asia/Kolkata', branchName: 'Main', branchAddress: null, city: null, state: null }, member: { full_name: 'Aarav', member_code: '71' }, membership: null, receipts: [], addOns: [], latestMessage: null }) }));
describe('PLC-015/023 static Gym entry', () => {
  it('links the catalogue immediately before Messages without reading it', async () => {
    const { default: Page } = await import('../member/my-gym/page');
    const html = renderToStaticMarkup(await Page());
    expect(html).toContain('href="/member/plans"'); expect(html).toContain('Plans &amp; prices'); expect(html).toContain('What each plan costs and includes');
    expect(html.indexOf('href="/member/plans"')).toBeLessThan(html.indexOf('href="/member/messages"')); expect(query).not.toHaveBeenCalled();
  });
  it('keeps the Gym destination current on the catalogue page', async () => {
    const { MemberNavigation } = await import('../member/member-navigation');
    const html = renderToStaticMarkup(createElement(MemberNavigation));
    expect(html).toMatch(/<a\b(?=[^>]*\bhref="\/member\/(?:my-gym|gym)")(?=[^>]*\baria-current="page")[^>]*>(?:(?!<\/a>)[\s\S])*My gym(?:(?!<\/a>)[\s\S])*<\/a>/);
  });
});
